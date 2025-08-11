#!/bin/sh
# BorgOS Ollama Initialization Script

echo "Starting Ollama initialization..."

# Start Ollama server in background
ollama serve &
OLLAMA_PID=$!

# Wait for Ollama to be ready
echo "Waiting for Ollama to start..."
max_attempts=30
attempt=0

while [ $attempt -lt $max_attempts ]; do
    if curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
        echo "Ollama is ready!"
        break
    fi
    sleep 2
    attempt=$((attempt + 1))
done

if [ $attempt -eq $max_attempts ]; then
    echo "Ollama failed to start properly"
    exit 1
fi

# Pull default models
echo "Pulling default AI models..."

# Essential model - small and fast
ollama pull gemma:2b 2>/dev/null || echo "Failed to pull gemma:2b"

# Additional useful models (optional)
if [ "${PULL_ADDITIONAL_MODELS:-true}" = "true" ]; then
    echo "Pulling additional models..."
    ollama pull llama2:7b 2>/dev/null || echo "Failed to pull llama2:7b"
    ollama pull codellama:7b 2>/dev/null || echo "Failed to pull codellama:7b"
    ollama pull mistral:7b 2>/dev/null || echo "Failed to pull mistral:7b"
fi

echo "Ollama initialization complete!"

# Keep Ollama running
wait $OLLAMA_PID