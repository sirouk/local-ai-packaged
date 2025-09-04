#!/bin/bash
set -e
LOG_FILE="/tmp/ollama-container-watch.log"
PID_FILE="/tmp/ollama-host.pid"

echo "Starting bidirectional Ollama lifecycle management..." | tee -a "$LOG_FILE"

# Wait for Docker to be available
for i in {1..30}; do
  if docker info >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

# Function to check if host Ollama is running and responsive
check_host_ollama() {
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if kill -0 "$PID" 2>/dev/null && curl -s http://localhost:11434/api/version >/dev/null 2>&1; then
            return 0  # Running and responsive
        fi
    fi
    return 1  # Not running or not responsive
}

# Function to restart host Ollama
restart_host_ollama() {
    echo "Restarting host Ollama..." | tee -a "$LOG_FILE"
    bash ./ollama-proxy/start-host-ollama.sh 2>>"$LOG_FILE" || {
        echo "Failed to restart host Ollama" | tee -a "$LOG_FILE"
        return 1
    }
    return 0
}

# Start background Docker container monitoring
(docker events --filter container=ollama --format '{{.Action}}' 2>>"$LOG_FILE" | while read -r action; do
  case "$action" in
    stop|die|kill)
      echo "Detected ollama container action: $action — stopping host Ollama" | tee -a "$LOG_FILE"
      bash ./ollama-proxy/stop-host-ollama.sh || true
      exit 0
      ;;
    start)
      echo "Detected ollama container start — ensuring host Ollama is running" | tee -a "$LOG_FILE"
      if ! check_host_ollama; then
          restart_host_ollama || true
      fi
      ;;
    *)
      echo "Event: $action" >>"$LOG_FILE"
      ;;
  esac
done) &
DOCKER_WATCHER_PID=$!

# Start background host Ollama monitoring
(while true; do
    sleep 30  # Check every 30 seconds
    
    # Only check if Docker container is running
    if docker ps --filter "name=ollama" --format "{{.Status}}" | grep -q "Up"; then
        if ! check_host_ollama; then
            echo "Host Ollama died - attempting restart..." | tee -a "$LOG_FILE"
            if restart_host_ollama; then
                echo "Host Ollama restarted successfully" | tee -a "$LOG_FILE"
            else
                echo "Failed to restart host Ollama - will retry in 30s" | tee -a "$LOG_FILE"
            fi
        fi
    else
        echo "Docker container not running - stopping host monitoring" | tee -a "$LOG_FILE"
        break
    fi
done) &
HOST_WATCHER_PID=$!

echo "Bidirectional watcher started (Docker PID=$DOCKER_WATCHER_PID, Host PID=$HOST_WATCHER_PID)" | tee -a "$LOG_FILE"

# Wait for either watcher to exit
wait $DOCKER_WATCHER_PID $HOST_WATCHER_PID
