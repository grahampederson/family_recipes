require 'net/http'
require 'json'
require 'uri'
require 'fileutils'

MODEL      = ENV.fetch('OLLAMA_MODEL', 'llama3.1')
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
  - Prefer chicken and beef; open to some lamb
  - Higher protein, lower carb meals preferred
  - Rice preferred over potatoes for starches
CTX

def day_prompt(day)
  <<~EOF
    Act as an expert family meal planner.

    #{FAMILY_CONTEXT}

    Plan dinner for #{day} only. Provide:
    1. A meal name and brief description
    2. Full ingredient list with quantities (for 5 people)
    3. Step-by-step cooking instructions

    Format the output cleanly in Markdown. Do not include a grocery list — just the recipe.
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
  # Pull out the ingredients section to feed into the grocery consolidation prompt
  lines = markdown_text.lines
  in_ingredients = false
  ingredients = []

  lines.each do |line|
    if line.match?(/ingredient/i)
      in_ingredients = true
    elsif line.match?(/^#+\s/) && in_ingredients
      # Stop at the next heading (e.g. Instructions)
      break if ingredients.any?
    end

    ingredients << line if in_ingredients
  end

  # If we couldn't isolate ingredients, just send the full text — the LLM can handle it
  ingredients.any? ? ingredients.join : markdown_text
end

def run
  recipes_dir = ENV.fetch('OUTPUT_DIR', File.join(Dir.pwd, 'recipes'))
  FileUtils.mkdir_p(recipes_dir)
  puts "Saving files to: #{recipes_dir}\n\n"

  daily_ingredients = []

  DAYS.each_with_index do |day, i|
    puts "==> Generating #{day}'s dinner..."
    content = call_ollama(day_prompt(day), day)
    next unless content

    # Save individual day file
    filename = File.join(recipes_dir, "#{i + 1}_#{day.downcase}.md")
    File.write(filename, "# #{day} Dinner\n\n#{content}\n")
    puts "  Saved: #{filename}"

    daily_ingredients << extract_ingredients(content)
    puts
  end

  # Generate and save the consolidated grocery list
  puts "==> Generating consolidated weekly grocery list..."
  grocery_content = call_ollama(grocery_prompt(daily_ingredients), 'grocery list')

  if grocery_content
    grocery_file = File.join(recipes_dir, 'grocery_list.md')
    File.write(grocery_file, "# Weekly Grocery List\n\n#{grocery_content}\n")
    puts "  Saved: #{grocery_file}"
  end

  puts "\nDone! All files are in: #{recipes_dir}"
end

run