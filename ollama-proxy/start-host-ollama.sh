#!/bin/bash
set -e
PID_FILE="/tmp/ollama-host.pid"
LOG_FILE="/tmp/ollama-host.log"

echo "Starting Ollama host management..." | tee -a "$LOG_FILE"

# Function to check if Ollama is bound to 0.0.0.0:11434
check_ollama_binding() {
  # Check if port 11434 is bound to 0.0.0.0 (accessible from Docker)
  if netstat -an 2>/dev/null | grep -q "*.11434.*LISTEN" || netstat -an 2>/dev/null | grep -q "0.0.0.0.11434.*LISTEN"; then
    return 0  # Correctly bound
  else
    return 1  # Not correctly bound
  fi
}

# Stop any existing Ollama processes that aren't properly bound
if pgrep -f "ollama serve" >/dev/null 2>&1; then
  echo "Found existing Ollama process(es)..." | tee -a "$LOG_FILE"
  
  # Check if current binding is correct
  if check_ollama_binding; then
    echo "Ollama already running with correct binding (0.0.0.0:11434)" | tee -a "$LOG_FILE"
    # Get the PID of the correctly running process
    EXISTING_PID=$(pgrep -f "ollama serve" | head -1)
    echo $EXISTING_PID > "$PID_FILE"
    exit 0
  else
    echo "Ollama running with incorrect binding (likely 127.0.0.1 only), stopping..." | tee -a "$LOG_FILE"
    # Kill existing Ollama processes
    pkill -f "ollama serve" 2>/dev/null || true
    sleep 3
    # Force kill if still running
    pkill -9 -f "ollama serve" 2>/dev/null || true
    sleep 2
  fi
fi

echo "Starting Ollama with Docker-accessible binding (0.0.0.0:11434)..." | tee -a "$LOG_FILE"

# Start Ollama with proper host binding for Docker access
nohup env OLLAMA_HOST=0.0.0.0:11434 ollama serve > "$LOG_FILE" 2>&1 &
HOST_PID=$!
echo $HOST_PID > "$PID_FILE"

# Wait until port is open and correctly bound (max ~60s)
for i in {1..60}; do
  if nc -z localhost 11434 2>/dev/null && check_ollama_binding; then
    echo "Ollama started successfully on host (PID=$HOST_PID) with Docker-accessible binding" | tee -a "$LOG_FILE"
    exit 0
  fi
  sleep 1
done

echo "ERROR: Ollama did not start with correct binding (0.0.0.0:11434)" | tee -a "$LOG_FILE"
exit 1
