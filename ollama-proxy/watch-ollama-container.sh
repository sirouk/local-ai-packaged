#!/bin/bash
set -e
LOG_FILE="/tmp/ollama-container-watch.log"

# Wait for Docker to be available
for i in {1..30}; do
  if docker info >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

# Listen for events on the specific container name
# When the container stops/dies, stop Ollama on host
(docker events --filter container=ollama --format '{{.Action}}' 2>>"$LOG_FILE" | while read -r action; do
  case "$action" in
    stop|die|kill)
      echo "Detected ollama container action: $action — stopping host Ollama" | tee -a "$LOG_FILE"
      bash ./ollama-proxy/stop-host-ollama.sh || true
      exit 0
      ;;
    *)
      echo "Event: $action" >>"$LOG_FILE"
      ;;
  esac
done) &
