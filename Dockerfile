FROM ruby:3.3-slim
 
# Install Python + pip + PDF font support
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    python3-venv \
    fontconfig \
    && rm -rf /var/lib/apt/lists/*
 
# Install Python PDF deps in a venv to avoid system conflicts
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
RUN pip install --no-cache-dir reportlab
 
WORKDIR /app
COPY meal_planner.rb .
COPY make_pdf.py .
 
VOLUME ["/output"]
 
ENV OUTPUT_DIR=/output \
    OLLAMA_HOST=host-gateway \
    OLLAMA_PORT=11434 \
    OLLAMA_MODEL=llama3.1
 
# Default command runs the meal planner; override with make_pdf to generate PDF
CMD ["ruby", "meal_planner.rb"]