#!/bin/bash
#
# video-prereq.sh - Check if video processing is available
# Returns status + message for the video skill to use
#

CONFIG_FILE="$HOME/.claude/claude-vision/config.json"
PLUGIN_ROOT="$VISION_PLUGIN_ROOT"
LOG_FILE="$PLUGIN_ROOT/docker-pull.log"

# Check if config exists
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "STATUS:NOT_CONFIGURED"
    echo "MESSAGE:claude-vision is not configured yet. Please wait for setup to complete or run /claude-vision-setup."
    exit 0
fi

# Read config values
MODE=$(grep -o '"mode"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
DOCKER_PULL_STATUS=$(grep -o '"docker_pull_status"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
DOCKER_PULL_START=$(grep -o '"docker_pull_start"[[:space:]]*:[[:space:]]*[0-9]*' "$CONFIG_FILE" | grep -o '[0-9]*$')

# Function to parse docker pull log for progress
get_pull_progress() {
    if [[ ! -f "$LOG_FILE" ]]; then
        echo "starting..."
        return
    fi

    # Check if complete or failed
    if grep -q "^COMPLETE$" "$LOG_FILE" 2>/dev/null; then
        echo "complete"
        return
    fi
    if grep -q "^FAILED$" "$LOG_FILE" 2>/dev/null; then
        echo "failed"
        return
    fi

    # Parse the last downloading line for progress
    # Format: "a2abf6c4d29d: Downloading [==>      ]  1.234MB/50.12MB"
    LAST_DL=$(grep -E "Downloading|Extracting" "$LOG_FILE" 2>/dev/null | tail -1)
    if [[ -n "$LAST_DL" ]]; then
        # Extract the size info (e.g., "1.234MB/50.12MB")
        SIZES=$(echo "$LAST_DL" | grep -oE '[0-9.]+[kMG]?B/[0-9.]+[kMG]?B' | tail -1)
        if [[ -n "$SIZES" ]]; then
            echo "$SIZES"
            return
        fi
    fi

    # Check for "Pull complete" lines to show layer progress
    COMPLETE_LAYERS=$(grep -c "Pull complete" "$LOG_FILE" 2>/dev/null || echo 0)
    TOTAL_LAYERS=$(grep -c "Pulling fs layer\|Already exists" "$LOG_FILE" 2>/dev/null || echo 0)
    if [[ "$TOTAL_LAYERS" -gt 0 ]]; then
        echo "${COMPLETE_LAYERS}/${TOTAL_LAYERS} layers"
        return
    fi

    echo "in progress..."
}

# Determine availability based on mode
case "$MODE" in
    local)
        echo "STATUS:READY_LOCAL"
        echo "MESSAGE:Ready to process video using local tools."
        ;;
    docker)
        case "$DOCKER_PULL_STATUS" in
            complete)
                echo "STATUS:READY_DOCKER"
                echo "MESSAGE:Ready to process video using Docker."
                ;;
            in-progress)
                # Calculate elapsed time
                NOW=$(date +%s)
                if [[ -n "$DOCKER_PULL_START" && "$DOCKER_PULL_START" -gt 0 ]]; then
                    ELAPSED=$((NOW - DOCKER_PULL_START))
                    MINS=$((ELAPSED / 60))
                    SECS=$((ELAPSED % 60))
                    if [[ $MINS -gt 0 ]]; then
                        ELAPSED_STR="${MINS}m ${SECS}s"
                    else
                        ELAPSED_STR="${SECS}s"
                    fi
                else
                    ELAPSED_STR="unknown"
                    ELAPSED=0
                fi

                # Get progress from log
                PROGRESS=$(get_pull_progress)

                # Check if log says complete but config not updated yet
                if [[ "$PROGRESS" == "complete" ]]; then
                    echo "STATUS:READY_DOCKER"
                    echo "MESSAGE:Docker pull just finished. Ready to process video."
                    exit 0
                fi

                echo "STATUS:DOCKER_PULLING"
                echo "ELAPSED:$ELAPSED"
                echo "PROGRESS:$PROGRESS"
                echo "MESSAGE:Docker image is being pulled (${ELAPSED_STR} elapsed, progress: ${PROGRESS}). Usually takes 1-2 minutes. I can wait and retry automatically if you'd like."
                ;;
            failed)
                echo "STATUS:DOCKER_FAILED"
                echo "MESSAGE:Docker image pull failed. You can retry with /claude-vision-setup or install local tools (ffmpeg + yt-dlp)."
                ;;
            *)
                echo "STATUS:DOCKER_UNKNOWN"
                echo "MESSAGE:Docker pull status unknown. Try running /claude-vision-setup."
                ;;
        esac
        ;;
    none|"")
        echo "STATUS:NO_TOOLS"
        echo "MESSAGE:Video analysis requires either local tools (ffmpeg + yt-dlp) or Docker. Neither is available."
        ;;
    *)
        echo "STATUS:UNKNOWN_MODE"
        echo "MESSAGE:Unknown mode in config. Try running /claude-vision-setup."
        ;;
esac
