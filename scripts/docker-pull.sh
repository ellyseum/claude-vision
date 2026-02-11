#!/bin/bash
#
# docker-pull.sh - Background docker pull with progress logging
# Called by session-start.sh, writes progress to log, updates config when complete
#

CONFIG_FILE="$HOME/.claude/claude-vision/config.json"
PLUGIN_ROOT="$VISION_PLUGIN_ROOT"
LOG_FILE="$PLUGIN_ROOT/docker-pull.log"
IMAGE="ghcr.io/ellyseum/claude-vision:lite"

# Clear old log
> "$LOG_FILE"

# Run docker pull and capture output
docker pull "$IMAGE" 2>&1 | while IFS= read -r line; do
    echo "$line" >> "$LOG_FILE"
done
PULL_EXIT=${PIPESTATUS[0]}

# Update config with result
if [[ -f "$CONFIG_FILE" ]]; then
    if [[ $PULL_EXIT -eq 0 ]]; then
        sed -i 's/"docker_pull_status"[[:space:]]*:[[:space:]]*"[^"]*"/"docker_pull_status": "complete"/' "$CONFIG_FILE"
        echo "COMPLETE" >> "$LOG_FILE"
    else
        sed -i 's/"docker_pull_status"[[:space:]]*:[[:space:]]*"[^"]*"/"docker_pull_status": "failed"/' "$CONFIG_FILE"
        echo "FAILED" >> "$LOG_FILE"
    fi
fi
