#!/bin/bash
#
# claude-vision SessionStart hook
# First run: detect everything, auto-configure, output summary
# Subsequent runs: read cached config, output summary
#

PLUGIN_ROOT="$CLAUDE_PLUGIN_ROOT"
CONFIG_FILE="$HOME/.claude/claude-vision/config.json"
CONFIG_DIR="$HOME/.claude/claude-vision"

# Export plugin root and add bin to PATH
if [[ -n "$CLAUDE_ENV_FILE" ]]; then
    echo "export VISION_PLUGIN_ROOT=\"$PLUGIN_ROOT\"" >> "$CLAUDE_ENV_FILE"
    echo "export PATH=\"\$PATH:$PLUGIN_ROOT/bin\"" >> "$CLAUDE_ENV_FILE"
fi

# If config exists, just output cached summary
if [[ -f "$CONFIG_FILE" ]]; then
    # Read cached values
    OS_TYPE=$(grep -o '"os"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
    DOCKER_OK=$(grep -o '"docker"[[:space:]]*:[[:space:]]*[^,}]*' "$CONFIG_FILE" | cut -d':' -f2 | tr -d ' ')
    GPU_NAME=$(grep -o '"gpu_name"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
    SCREENSHOT_DIR=$(grep -o '"screenshot_dir"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
    IMAGE_VARIANT=$(grep -o '"image_variant"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
    LOCAL_TOOLS=$(grep -o '"local_tools"[[:space:]]*:[[:space:]]*[^,}]*' "$CONFIG_FILE" | cut -d':' -f2 | tr -d ' ')

    SUMMARY="claude-vision ready:
- OS: $OS_TYPE
- Screenshot dir: $SCREENSHOT_DIR
- Docker: $DOCKER_OK, Image: ${IMAGE_VARIANT:-none}
- Local tools: $LOCAL_TOOLS
- GPU: ${GPU_NAME:-none}"

    cat << EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "$SUMMARY"
  }
}
EOF
    exit 0
fi

# First run - detect everything and create config
mkdir -p "$CONFIG_DIR"

# Detect OS
OS_TYPE="linux"
if [[ -f /proc/version ]] && grep -qi microsoft /proc/version 2>/dev/null; then
    OS_TYPE="wsl"
elif [[ "$(uname)" == "Darwin" ]]; then
    OS_TYPE="macos"
fi

# Check Docker
DOCKER_OK="false"
if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
    DOCKER_OK="true"
fi

# Check GPU
GPU_OK="false"
GPU_NAME=""
NVIDIA_TOOLKIT="false"
if command -v nvidia-smi &>/dev/null && nvidia-smi &>/dev/null 2>&1; then
    GPU_OK="true"
    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
    if [[ "$DOCKER_OK" == "true" ]] && docker info 2>/dev/null | grep -qi nvidia; then
        NVIDIA_TOOLKIT="true"
    fi
fi

# Check local tools
LOCAL_FFMPEG="false"
LOCAL_YTDLP="false"
LOCAL_WHISPER="false"
command -v ffmpeg &>/dev/null && LOCAL_FFMPEG="true"
command -v yt-dlp &>/dev/null && LOCAL_YTDLP="true"
command -v whisper &>/dev/null && LOCAL_WHISPER="true"

LOCAL_TOOLS="false"
if [[ "$LOCAL_FFMPEG" == "true" && "$LOCAL_YTDLP" == "true" ]]; then
    LOCAL_TOOLS="true"
fi

# Auto-detect screenshot directory
SCREENSHOT_DIR=""
case "$OS_TYPE" in
    wsl)
        # Find Windows user's Screenshots folder
        for dir in /mnt/c/Users/*/Pictures/Screenshots; do
            if [[ -d "$dir" ]]; then
                SCREENSHOT_DIR="$dir"
                break
            fi
        done
        ;;
    macos)
        if [[ -d "$HOME/Pictures/Screenshots" ]]; then
            SCREENSHOT_DIR="$HOME/Pictures/Screenshots"
        elif [[ -d "$HOME/Desktop" ]]; then
            SCREENSHOT_DIR="$HOME/Desktop"
        fi
        ;;
    linux)
        if [[ -d "$HOME/Pictures/Screenshots" ]]; then
            SCREENSHOT_DIR="$HOME/Pictures/Screenshots"
        elif [[ -d "$HOME/Pictures" ]]; then
            SCREENSHOT_DIR="$HOME/Pictures"
        fi
        ;;
esac

# Determine mode
MODE="none"
IMAGE_VARIANT=""
DOCKER_PULL_STATUS=""
DOCKER_PULL_MSG=""

if [[ "$LOCAL_TOOLS" == "true" ]]; then
    MODE="local"
elif [[ "$DOCKER_OK" == "true" ]]; then
    MODE="docker"
    IMAGE_VARIANT="lite"
    # Check if image already exists
    if docker image inspect ghcr.io/ellyseum/claude-vision:lite &>/dev/null; then
        DOCKER_PULL_STATUS="complete"
    else
        DOCKER_PULL_STATUS="in-progress"
        DOCKER_PULL_START=$(date +%s)
        DOCKER_PULL_MSG="Docker image not found - pulling from registry in background"
        # Start background pull
        nohup "$PLUGIN_ROOT/scripts/docker-pull.sh" &>/dev/null &
    fi
fi

# Write config
cat > "$CONFIG_FILE" << EOF
{
    "os": "$OS_TYPE",
    "mode": "$MODE",
    "docker": $DOCKER_OK,
    "docker_pull_status": "${DOCKER_PULL_STATUS:-n/a}",
    "docker_pull_start": ${DOCKER_PULL_START:-0},
    "gpu": $GPU_OK,
    "gpu_name": "$GPU_NAME",
    "nvidia_toolkit": $NVIDIA_TOOLKIT,
    "local_tools": $LOCAL_TOOLS,
    "local_ffmpeg": $LOCAL_FFMPEG,
    "local_ytdlp": $LOCAL_YTDLP,
    "local_whisper": $LOCAL_WHISPER,
    "screenshot_dir": "$SCREENSHOT_DIR",
    "image_variant": "$IMAGE_VARIANT",
    "created": "$(date -Iseconds)"
}
EOF

# Output first-run summary
SUMMARY="claude-vision first-time setup complete:
- OS: $OS_TYPE
- Screenshot dir: ${SCREENSHOT_DIR:-not found}
- Docker: $DOCKER_OK
- Local tools: $LOCAL_TOOLS (ffmpeg: $LOCAL_FFMPEG, yt-dlp: $LOCAL_YTDLP)
- GPU: ${GPU_NAME:-none}
- Mode: $MODE"

# Add docker pull message if applicable
if [[ -n "$DOCKER_PULL_MSG" ]]; then
    SUMMARY="$SUMMARY
- $DOCKER_PULL_MSG"
fi

cat << EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "$SUMMARY"
  }
}
EOF
