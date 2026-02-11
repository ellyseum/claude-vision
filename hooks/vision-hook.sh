#!/bin/bash
#
# Vision hook - handles prep for clipboard and screenshot
# Works for both UserPromptSubmit and PreToolUse events
#

INPUT=$(cat)
PLUGIN_ROOT="$CLAUDE_PLUGIN_ROOT"

# Determine which skill/command was invoked
PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty')
SKILL_NAME=$(echo "$INPUT" | jq -r '.tool_input.skill // empty')
SKILL_ARGS=$(echo "$INPUT" | jq -r '.tool_input.args // empty')

# Check if this is a vision command
IS_VISION=""
if [[ "$PROMPT" == "/clipboard"* ]] || [[ "$SKILL_NAME" == *"clipboard"* ]]; then
    IS_VISION="clipboard"
elif [[ "$PROMPT" == "/screenshot"* ]] || [[ "$SKILL_NAME" == *"screenshot"* ]]; then
    IS_VISION="screenshot"
elif [[ "$PROMPT" == "/video"* ]] || [[ "$SKILL_NAME" == *"video"* ]]; then
    IS_VISION="video"
fi

# Not a vision command we handle - exit silently
if [[ -z "$IS_VISION" ]]; then
    exit 0
fi

# Run the appropriate prep script
case "$IS_VISION" in
    clipboard)
        RESULT=$("$PLUGIN_ROOT/scripts/clipboard-prep.sh" 2>/dev/null)
        CONTEXT="Clipboard contents: $RESULT"
        ;;
    screenshot)
        RESULT=$("$PLUGIN_ROOT/scripts/screenshot-prep.sh" 2>/dev/null)
        CONTEXT="Screenshot: $RESULT"
        ;;
    video)
        # Extract URL or path from prompt OR skill args
        # Matches: youtube.com, youtu.be, or file paths
        VIDEO_SOURCE=$(echo "$PROMPT $SKILL_ARGS" | grep -oE '(https?://[^ ]+|/[^ ]+\.(mp4|mkv|webm|mov))' | head -1)
        RESULT=$("$PLUGIN_ROOT/scripts/video-start.sh" "$VIDEO_SOURCE" 2>/dev/null)
        # Format for easy parsing - put key values on labeled lines
        STATUS=$(echo "$RESULT" | grep "^STATUS:" | cut -d: -f2)
        LOG=$(echo "$RESULT" | grep "^LOG:" | cut -d: -f2)
        CACHE=$(echo "$RESULT" | grep "^CACHE:" | cut -d: -f2)
        MSG=$(echo "$RESULT" | grep "^MESSAGE:" | cut -d: -f2-)

        CONTEXT="=== VIDEO HOOK RESULT ===
STATUS: $STATUS
LOG_FILE: $LOG
CACHE_DIR: $CACHE
MESSAGE: $MSG
=== USE THESE EXACT PATHS ==="
        ;;
esac

# Output based on event type
if [[ -n "$PROMPT" ]]; then
    # UserPromptSubmit - plain stdout becomes context
    echo "$CONTEXT"
else
    # PreToolUse - need JSON format
    ESCAPED=$(echo "$CONTEXT" | jq -Rs .)
    cat << EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": $ESCAPED
  }
}
EOF
fi
