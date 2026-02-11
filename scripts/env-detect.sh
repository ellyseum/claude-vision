#!/bin/bash
#
# env-detect.sh - detects OS, Docker, GPU for setup skill
# Outputs key=value pairs for easy parsing
#

CONFIG_FILE="$HOME/.claude/claude-vision/config.json"

# Detect OS
OS_TYPE="linux"
if [[ -f /proc/version ]] && grep -qi microsoft /proc/version 2>/dev/null; then
    OS_TYPE="wsl"
elif [[ "$(uname)" == "Darwin" ]]; then
    OS_TYPE="macos"
fi
echo "OS_TYPE=$OS_TYPE"

# Check Docker
DOCKER_OK="false"
if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
    DOCKER_OK="true"
fi
echo "DOCKER_OK=$DOCKER_OK"

# Check GPU
GPU_OK="false"
GPU_NAME=""
NVIDIA_TOOLKIT="false"
if command -v nvidia-smi &>/dev/null && nvidia-smi &>/dev/null 2>&1; then
    GPU_OK="true"
    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
    if docker info 2>/dev/null | grep -qi nvidia; then
        NVIDIA_TOOLKIT="true"
    fi
fi
echo "GPU_OK=$GPU_OK"
echo "GPU_NAME=$GPU_NAME"
echo "NVIDIA_TOOLKIT=$NVIDIA_TOOLKIT"

# Check existing config
if [[ -f "$CONFIG_FILE" ]]; then
    echo "CONFIG_EXISTS=true"
    IMAGE_VARIANT=$(grep -o '"image_variant"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG_FILE" 2>/dev/null | cut -d'"' -f4)
    SCREENSHOT_DIR=$(grep -o '"screenshot_dir"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG_FILE" 2>/dev/null | cut -d'"' -f4)
    echo "IMAGE_VARIANT=$IMAGE_VARIANT"
    echo "SCREENSHOT_DIR=$SCREENSHOT_DIR"
else
    echo "CONFIG_EXISTS=false"
fi
