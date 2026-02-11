#!/bin/bash
#
# screenshot-prep.sh - finds latest screenshot, outputs TYPE:IMAGE\n<path>
#

CONFIG_FILE="$HOME/.claude/claude-vision/config.json"

# Check if configured
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "TYPE:NOT_CONFIGURED"
    exit 0
fi

# Get screenshot directory from config
SCREENSHOT_DIR=$(grep -o '"screenshot_dir"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG_FILE" 2>/dev/null | cut -d'"' -f4)
SCREENSHOT_DIR="${SCREENSHOT_DIR/#\~/$HOME}"

if [[ -z "$SCREENSHOT_DIR" ]] || [[ ! -d "$SCREENSHOT_DIR" ]]; then
    echo "TYPE:DIR_NOT_FOUND"
    echo "$SCREENSHOT_DIR"
    exit 0
fi

# Detect OS for find command differences
if [[ "$(uname)" == "Darwin" ]]; then
    # macOS
    LATEST=$(find "$SCREENSHOT_DIR" -maxdepth 1 -type f \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" \) -exec stat -f '%m %N' {} \; 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
else
    # Linux/WSL
    LATEST=$(find "$SCREENSHOT_DIR" -maxdepth 1 -type f \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" \) -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
fi

if [[ -z "$LATEST" ]]; then
    echo "TYPE:NO_SCREENSHOTS"
    echo "$SCREENSHOT_DIR"
    exit 0
fi

echo "TYPE:IMAGE"
echo "$LATEST"
