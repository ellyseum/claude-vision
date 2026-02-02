---
name: screenshot
description: Read the latest screenshot and respond to a prompt about it
---

## Instructions

When this skill is invoked with `/screenshot <prompt>`:

### Step 1: Setup Check

**IMPORTANT:** Before doing anything else, check if claude-vision is configured:

```bash
CONFIG_FILE="$HOME/.claude/claude-vision/config.json"
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "claude-vision is not configured yet. Starting setup..."
fi
```

If the config file doesn't exist, **immediately run `/claude-vision-setup`** to configure, then return here and continue with the user's original request.

### Step 2: Get Screenshot Directory

```bash
SCREENSHOT_DIR=$(grep -o '"screenshot_dir"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
# Expand ~ if present
SCREENSHOT_DIR="${SCREENSHOT_DIR/#\~/$HOME}"

if [[ -z "$SCREENSHOT_DIR" ]] || [[ ! -d "$SCREENSHOT_DIR" ]]; then
    echo "Screenshot directory not configured or not found: $SCREENSHOT_DIR"
    echo "Run /claude-vision-setup to reconfigure."
    exit 1
fi

echo "Screenshot directory: $SCREENSHOT_DIR"
```

### Step 2: Find Latest Screenshot

Find the newest image file in the configured directory:

```bash
LATEST=$(find "$SCREENSHOT_DIR" -maxdepth 1 -type f \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" \) -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)

if [[ -z "$LATEST" ]]; then
    echo "No screenshots found in $SCREENSHOT_DIR"
    exit 1
fi

echo "Latest screenshot: $LATEST"
```

**Note:** On macOS, `find` doesn't support `-printf`. Use this instead:
```bash
LATEST=$(find "$SCREENSHOT_DIR" -maxdepth 1 -type f \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" \) -exec stat -f '%m %N' {} \; 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
```

### Step 3: Read and Analyze

Read the image using the Read tool, then respond to the user's prompt based on what you see.

If no prompt was provided, just describe what's in the screenshot.

---

## Example Usage

- `/screenshot what do you think` - General reaction to screenshot
- `/screenshot summarize this conversation` - OCR and summarize text in image
- `/screenshot what's the error here` - Analyze error message in screenshot
- `/screenshot` - Just describe what you see

## Configuration

Screenshot directory is stored in `~/.claude/claude-vision/config.json`:

```json
{
    "screenshot_dir": "/path/to/screenshots",
    ...
}
```

Run `/claude-vision-setup` to configure.

## Default Directories by Platform

If not configured, these are typical locations:

| Platform | Default Location |
|----------|-----------------|
| WSL | `/mnt/c/Users/<user>/Pictures/Screenshots` |
| macOS | `~/Desktop` or `~/Pictures/Screenshots` |
| Linux | `~/Pictures/Screenshots` or `~/Pictures` |

## Notes

- If no arguments provided, just describe what you see
- Searches only the top level of the screenshot directory (not subdirectories)
- Supports `.png`, `.jpg`, `.jpeg` files
