---
name: clipboard
description: Read clipboard contents (text or image) and respond to a prompt about it
---

## Instructions

When this skill is invoked with `/clipboard <prompt>`:

### Step 1: Setup Check

**IMPORTANT:** Before doing anything else, check if claude-vision is configured:

```bash
CONFIG_FILE="$HOME/.claude/claude-vision/config.json"
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "claude-vision is not configured yet. Starting setup..."
fi
```

If the config file doesn't exist, **immediately run `/claude-vision-setup`** to configure, then return here and continue with the user's original request.

### Step 2: Load Configuration

```bash
CONFIG_FILE="$HOME/.claude/claude-vision/config.json"
OS_TYPE=$(grep -o '"os"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
echo "OS: $OS_TYPE"
```

### Step 2: Detect Clipboard Type

**WSL (Windows):**
```bash
powershell.exe -command "
Add-Type -AssemblyName System.Windows.Forms
if ([System.Windows.Forms.Clipboard]::ContainsFileDropList()) {
    \$files = [System.Windows.Forms.Clipboard]::GetFileDropList()
    Write-Output \"FILES:\$files\"
} elseif ([System.Windows.Forms.Clipboard]::ContainsImage()) {
    Write-Output 'IMAGE'
} elseif ([System.Windows.Forms.Clipboard]::ContainsText()) {
    Write-Output 'TEXT'
} else {
    Write-Output 'EMPTY'
}
"
```

**macOS:**
```bash
# Check for image first (requires pngpaste: brew install pngpaste)
if pngpaste - &>/dev/null; then
    echo "IMAGE"
elif [[ -n "$(pbpaste)" ]]; then
    echo "TEXT"
else
    echo "EMPTY"
fi
```

**Linux:**
```bash
# Requires xclip: apt install xclip
# Check image
if xclip -selection clipboard -t TARGETS -o 2>/dev/null | grep -q image/png; then
    echo "IMAGE"
elif xclip -selection clipboard -o &>/dev/null; then
    echo "TEXT"
else
    echo "EMPTY"
fi
```

### Step 3: Handle Based on Type

#### If FILES (WSL only - copied file from Explorer)

The output will be `FILES:C:\path\to\file.ext`

**IMPORTANT:** Don't use sed to convert paths - bash interprets `\U` in `C:\Users` as unicode escape.
Use `wslpath` or get the path directly from PowerShell:

```bash
# Get file path properly (avoids bash escape issues)
WIN_PATH=$(powershell.exe -command '
Add-Type -AssemblyName System.Windows.Forms
$files = [System.Windows.Forms.Clipboard]::GetFileDropList()
foreach ($f in $files) { Write-Output $f }
' | tr -d '\r' | head -1)

# Convert using wslpath (the proper way)
WSL_PATH=$(wslpath "$WIN_PATH")
```

Check file type:
- **Video** (`.mp4`, `.mkv`, `.webm`, `.mov`, `.avi`): Hand off to `/video` skill
- **Image** (`.png`, `.jpg`, `.jpeg`, `.gif`, `.bmp`): Read with Read tool, respond to prompt
- **Other**: Report file type, read if text-based

#### If TEXT

**WSL:**
```bash
powershell.exe -command "Get-Clipboard"
```

**macOS:**
```bash
pbpaste
```

**Linux:**
```bash
xclip -selection clipboard -o
```

Check if text is a video path/URL:
- YouTube URL (`youtube.com`, `youtu.be`) → hand off to `/video`
- Video file path → hand off to `/video`
- Otherwise → respond to prompt based on text content

#### If IMAGE

Save to temp file then read it:

**WSL:**
```bash
TEMP_IMG="/mnt/c/Users/$USER/AppData/Local/Temp/clipboard_img.png"
powershell.exe -command "Add-Type -AssemblyName System.Windows.Forms; \$img = [System.Windows.Forms.Clipboard]::GetImage(); if (\$img) { \$img.Save('$(wslpath -w "$TEMP_IMG")') }"
```

**macOS:**
```bash
TEMP_IMG="/tmp/clipboard_img.png"
pngpaste "$TEMP_IMG"
```

**Linux:**
```bash
TEMP_IMG="/tmp/clipboard_img.png"
xclip -selection clipboard -t image/png -o > "$TEMP_IMG"
```

Then read the image using the Read tool and respond to the user's prompt.

#### If EMPTY

Tell the user the clipboard is empty.

---

## Video Handoff

When a video is detected (file or URL), use the video skill's full flow:
1. Generate cache hash from path/URL
2. Check if already cached
3. If not cached: extract frames using `cv-run ffmpeg`
4. Read frames and any subtitles
5. Analyze based on user's prompt
6. Save analysis to cache

See `/video` skill for full implementation details.

---

## Example Usage

- `/clipboard what is this` - Analyze whatever's in clipboard
- `/clipboard summarize` - Summarize text or describe image/video
- `/clipboard fix this code` - If code is in clipboard, suggest fixes
- `/clipboard what happened here` - If video file copied, analyze it

## Prerequisites by Platform

| Platform | Requirements |
|----------|-------------|
| WSL | PowerShell (built-in) |
| macOS | `pngpaste` (`brew install pngpaste`) for images |
| Linux | `xclip` (`apt install xclip`) |

## Notes

- Works with text, images, and files (WSL only for files)
- Images are temporarily saved for reading
- Video files trigger the full video analysis pipeline with caching
- If no arguments provided, just describe/show what's in the clipboard
