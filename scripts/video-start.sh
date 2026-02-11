#!/bin/bash
#
# video-start.sh - Check prereqs, cache, and start processing if needed
# Called by vision-hook.sh with the video source URL/path
#
# Usage: video-start.sh [url-or-path]
#

SOURCE="$1"
PLUGIN_ROOT="$VISION_PLUGIN_ROOT"
CONFIG_FILE="$HOME/.claude/claude-vision/config.json"
CACHE_BASE="$HOME/.claude/claude-vision/video-cache"

# First check prerequisites
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "STATUS:NOT_CONFIGURED"
    echo "MESSAGE:claude-vision is not configured. Run /claude-vision-setup first."
    exit 0
fi

# Read config
MODE=$(grep -o '"mode"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
DOCKER_PULL_STATUS=$(grep -o '"docker_pull_status"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
LOCAL_TOOLS=$(grep -o '"local_tools"[[:space:]]*:[[:space:]]*[^,}]*' "$CONFIG_FILE" | cut -d':' -f2 | tr -d ' ')

# Check if tools are available
if [[ "$MODE" == "docker" ]]; then
    if [[ "$DOCKER_PULL_STATUS" == "in-progress" ]]; then
        # Get progress from log - calculate % from layer completion
        LOG_FILE="$PLUGIN_ROOT/docker-pull.log"
        PROGRESS="starting..."
        if [[ -f "$LOG_FILE" ]]; then
            # Count total layers and completed layers
            TOTAL=$(grep -cE "Pulling fs layer|Already exists" "$LOG_FILE" 2>/dev/null || echo 0)
            DONE=$(grep -cE "Pull complete|Already exists" "$LOG_FILE" 2>/dev/null || echo 0)
            if [[ "$TOTAL" -gt 0 ]]; then
                PCT=$((DONE * 100 / TOTAL))
                PROGRESS="${PCT}% (${DONE}/${TOTAL} layers)"
            fi
        fi
        echo "STATUS:DOCKER_PULLING"
        echo "PROGRESS:$PROGRESS"
        echo "MESSAGE:Docker image is being pulled ($PROGRESS). Please wait and try again in a moment."
        exit 0
    elif [[ "$DOCKER_PULL_STATUS" == "failed" ]]; then
        echo "STATUS:DOCKER_FAILED"
        echo "MESSAGE:Docker image pull failed. Run /claude-vision-setup to retry."
        exit 0
    elif [[ "$DOCKER_PULL_STATUS" != "complete" ]]; then
        # Check if image actually exists
        if ! docker image inspect claude-vision:lite &>/dev/null && ! docker image inspect ghcr.io/ellyseum/claude-vision:lite &>/dev/null; then
            echo "STATUS:DOCKER_MISSING"
            echo "MESSAGE:Docker image not found. Run /claude-vision-setup to configure."
            exit 0
        fi
    fi
elif [[ "$MODE" == "none" ]]; then
    echo "STATUS:NO_TOOLS"
    echo "MESSAGE:No video processing tools available. Install ffmpeg + yt-dlp or Docker."
    exit 0
fi

# If no source provided, we can only check prereqs
if [[ -z "$SOURCE" ]]; then
    echo "STATUS:READY"
    echo "MESSAGE:Video processing is available. Provide a URL or path to analyze."
    exit 0
fi

# Check cache
get_hash() {
    echo -n "$1" | md5sum | cut -d' ' -f1
}

HASH=$(get_hash "$SOURCE")
CACHE_DIR="$CACHE_BASE/$HASH"

# Check if fully cached (metadata.json = processing completed)
if [[ -f "$CACHE_DIR/metadata.json" ]]; then
    FRAME_COUNT=$(ls "$CACHE_DIR/frames"/*.jpg 2>/dev/null | wc -l)
    HAS_SUBS="false"
    [[ -f "$CACHE_DIR/subtitles.srt" ]] && HAS_SUBS="true"

    echo "STATUS:CACHED"
    echo "CACHE:$CACHE_DIR"
    echo "FRAME_COUNT:$FRAME_COUNT"
    echo "HAS_SUBS:$HAS_SUBS"
    echo "MESSAGE:Video already cached with $FRAME_COUNT frames."
    exit 0
fi

# Not cached - start processing in background
LOG_FILE="/tmp/video-process-$$.log"
mkdir -p "$CACHE_BASE"

# Start background processing
nohup "$PLUGIN_ROOT/scripts/video-process.sh" "$SOURCE" "$LOG_FILE" &>/dev/null &
BG_PID=$!

echo "STATUS:PROCESSING"
echo "LOG:$LOG_FILE"
echo "PID:$BG_PID"
echo "CACHE:$CACHE_DIR"
echo "MESSAGE:Started video processing. Use TaskOutput or poll the log file to wait for completion."
