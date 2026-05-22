FROM ruby:3.3-slim

WORKDIR /app

COPY meal_planner.rb .

# Output goes to /output — mount a host directory here to get your files
VOLUME ["/output"]

ENV OUTPUT_DIR=/output \
    OLLAMA_HOST=host-gateway \
    OLLAMA_PORT=11434 \
    OLLAMA_MODEL=llama3.1

CMD ["ruby", "meal_planner.rb"]