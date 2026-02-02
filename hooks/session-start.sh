#!/bin/bash
# Session start hook for claude-vision
# Checks config and guides user through setup if needed

CONFIG_FILE="$HOME/.claude/claude-vision/config.json"

# Check if setup has been run
if [ ! -f "$CONFIG_FILE" ]; then
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "  claude-vision plugin detected - first time setup needed"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    echo "  Run /claude-vision-setup to configure"
    echo ""
    exit 0
fi

# Config exists - check image status
IMAGE_VARIANT=$(grep -o '"image_variant"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
IMAGE_VARIANT="${IMAGE_VARIANT:-full}"

if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
    if ! docker image inspect "claude-vision:$IMAGE_VARIANT" &>/dev/null; then
        echo "claude-vision: Image not found. Run: cv-run --pull-$IMAGE_VARIANT"
    fi
fi
