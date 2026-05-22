require 'net/http'
require 'json'
require 'uri'
require 'fileutils'
require 'date'

MODEL       = ENV.fetch('OLLAMA_MODEL', 'llama3.1')
OLLAMA_HOST = ENV.fetch('OLLAMA_HOST', 'host-gateway')
OLLAMA_PORT = ENV.fetch('OLLAMA_PORT', '11434').to_i

def ollama_running?(host, port)
  http = Net::HTTP.new(host, port)
  http.open_timeout = 5
  http.read_timeout = 5
  response = http.get('/')
  response.is_a?(Net::HTTPSuccess)
rescue
  false
end

unless ollama_running?(OLLAMA_HOST, OLLAMA_PORT)
  puts "ERROR: Cannot reach Ollama at #{OLLAMA_HOST}:#{OLLAMA_PORT}"
  puts
  puts "Checklist:"
  puts "  1. Is Ollama running on Windows? Check your system tray or run: ollama serve"
  puts "  2. Does Ollama listen on all interfaces? Run this in Windows CMD, then restart Ollama:"
  puts "       setx OLLAMA_HOST 0.0.0.0"
  puts "  3. Is Windows Firewall blocking port 11434? Add an inbound rule for it."
  puts "  4. Override the host if needed: docker run -e OLLAMA_HOST=192.168.x.x ..."
  exit 1
end

puts "Ollama detected at #{OLLAMA_HOST}:#{OLLAMA_PORT}. Starting meal planner...\n\n"
OLLAMA_URL = URI.parse("http://#{OLLAMA_HOST}:#{OLLAMA_PORT}/api/generate")

DAYS = %w[Monday Tuesday Wednesday Thursday Friday Saturday Sunday]

FAMILY_CONTEXT = <<~CTX
  Family details:
  - 5 people (2 adults, 3 kids)
  - Peanut allergy (strict - no peanuts or peanut products)
  - No pork of any kind
  - No fish or seafood
  - Onions are not a favorite (minimize or omit)
  - Prefer chicken and beef
  - Higher protein, lower carb meals preferred
  - Rice preferred over potatoes for starches
  - No Cauliflower
CTX

HISTORY_FILE = File.join(ENV.fetch('OUTPUT_DIR', File.join(Dir.pwd, 'recipes')), 'recipe_history.json')

# ---------------------------------------------------------------------------
# Recipe history — persists across runs so meals are never repeated
# ---------------------------------------------------------------------------

def load_history
  return [] unless File.exist?(HISTORY_FILE)
  JSON.parse(File.read(HISTORY_FILE))
rescue JSON::ParserError
  []
end

def save_history(history)
  File.write(HISTORY_FILE, JSON.pretty_generate(history))
end

def history_context(history)
  return '' if history.empty?

  lines = history.map do |entry|
    "  - #{entry['meal_name']} (served #{entry['date']}, #{entry['day']})"
  end.join("\n")

  <<~CTX
    IMPORTANT — the following meals have already been served to this family.
    Do NOT repeat or closely rehash any of these. Choose something meaningfully different:

    #{lines}

  CTX
end

# ---------------------------------------------------------------------------
# Prompts
# ---------------------------------------------------------------------------

def day_prompt(day, history)
  <<~EOF
    Act as an expert family meal planner.

    #{FAMILY_CONTEXT}

    #{history_context(history)}
    Plan dinner for #{day} only. Provide:
    1. A meal name and brief description
    2. Full ingredient list with quantities (for 5 people)
    3. Step-by-step cooking instructions

    Format the output cleanly in Markdown. Do not include a grocery list — just the recipe.
  EOF
end

def meal_name_prompt(markdown_text)
  <<~EOF
    Extract only the meal name from the following recipe markdown. 
    Reply with just the meal name — no explanation, no punctuation, no markdown.

    #{markdown_text.lines.first(10).join}
  EOF
end

def grocery_prompt(daily_ingredients)
  combined = daily_ingredients.each_with_index.map do |ingredients, i|
    "### #{DAYS[i]}\n#{ingredients}"
  end.join("\n\n")

  <<~EOF
    Act as an expert family meal planner.

    Below are the ingredient lists from a week of dinners for a family of 5.
    Consolidate these into a single, categorized grocery list for the entire week.

    #{FAMILY_CONTEXT}

    Combine duplicate ingredients, sum quantities where possible, and group by supermarket section:
    - Produce
    - Meat & Poultry
    - Dairy & Eggs
    - Pantry / Dry Goods
    - Spices & Condiments
    - Frozen
    - Other

    Format the output cleanly in Markdown. Only output the grocery list — no meal descriptions.

    Here are the weekly ingredients:

    #{combined}
  EOF
end

# ---------------------------------------------------------------------------
# Ollama
# ---------------------------------------------------------------------------

def call_ollama(prompt, label)
  request = Net::HTTP::Post.new(OLLAMA_URL.path, 'Content-Type' => 'application/json')
  request.body = { model: MODEL, prompt: prompt, stream: false }.to_json

  http = Net::HTTP.new(OLLAMA_URL.host, OLLAMA_URL.port)
  http.read_timeout = 300

  puts "  Contacting Ollama for #{label}..."
  response = http.request(request)

  if response.is_a?(Net::HTTPSuccess)
    JSON.parse(response.body)['response']
  else
    raise "HTTP error for #{label}: #{response.message}"
  end
rescue => e
  puts "  Connection failed: #{e.message}. Is your Ollama server running?"
  nil
end

def extract_ingredients(markdown_text)
  lines = markdown_text.lines
  in_ingredients = false
  ingredients = []

  lines.each do |line|
    if line.match?(/ingredient/i)
      in_ingredients = true
    elsif line.match?(/^#+\s/) && in_ingredients
      break if ingredients.any?
    end
    ingredients << line if in_ingredients
  end

  ingredients.any? ? ingredients.join : markdown_text
end

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def run
  recipes_dir = ENV.fetch('OUTPUT_DIR', File.join(Dir.pwd, 'recipes'))
  FileUtils.mkdir_p(recipes_dir)
  puts "Saving files to: #{recipes_dir}\n\n"

  history = load_history
  puts "Loaded #{history.size} previous meal(s) from history — these will be avoided.\n\n" if history.any?

  today       = Date.today
  daily_ingredients = []
  week_entries      = []  # history entries generated this run

  DAYS.each_with_index do |day, i|
    date_label = (today + i).strftime('%Y-%m-%d')
    puts "==> Generating #{day} (#{date_label}) dinner..."

    # Pass full history including meals already generated this run
    content = call_ollama(day_prompt(day, history + week_entries), day)
    next unless content

    # Ask the model to pull out just the meal name for the history record
    meal_name = call_ollama(meal_name_prompt(content), "#{day} meal name")&.strip || 'Unknown'
    puts "  Meal: #{meal_name}"

    # Save the day file
    filename = File.join(recipes_dir, "#{date_label}_#{day.downcase}.md")
    File.write(filename, "# #{day} Dinner — #{meal_name}\n\n#{content}\n")
    puts "  Saved: #{filename}"

    entry = { 'date' => date_label, 'day' => day, 'meal_name' => meal_name }
    week_entries << entry
    daily_ingredients << extract_ingredients(content)
    puts
  end

  # Persist history
  updated_history = history + week_entries
  save_history(updated_history)
  puts "Updated recipe_history.json (#{updated_history.size} total meals recorded).\n\n"

  # Consolidated grocery list
  puts "==> Generating consolidated weekly grocery list..."
  grocery_content = call_ollama(grocery_prompt(daily_ingredients), 'grocery list')

  if grocery_content
    grocery_file = File.join(recipes_dir, "#{today.strftime('%Y-%m-%d')}_grocery_list.md")
    File.write(grocery_file, "# Weekly Grocery List — w/c #{today.strftime('%d %b %Y')}\n\n#{grocery_content}\n")
    puts "  Saved: #{grocery_file}"
  end

  puts "\nDone! All files are in: #{recipes_dir}"
end

run