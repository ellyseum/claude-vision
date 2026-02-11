---
name: claude-vision-setup
description: Interactive setup wizard for claude-vision - configures Docker images and platform settings
---

## Instructions

When invoked with `/claude-vision-setup`:

### Step 1: Read Environment Detection

The environment has already been detected by a hook. Check the system-reminder for "Environment detection results:" which contains key=value pairs:

- `OS_TYPE` - wsl, macos, or linux
- `DOCKER_OK` - true/false
- `GPU_OK` - true/false
- `GPU_NAME` - GPU model name (if detected)
- `NVIDIA_TOOLKIT` - true/false
- `CONFIG_EXISTS` - true/false
- `IMAGE_VARIANT` - lite/full (if config exists)
- `SCREENSHOT_DIR` - path (if config exists)

Present a summary to the user:
- OS: [detected]
- Docker: Available/Not available
- GPU: [name] with NVIDIA Container Toolkit / Not detected

If CONFIG_EXISTS=true, also show current settings.

### Step 2: Existing Config Flow

If CONFIG_EXISTS=true, use AskUserQuestion:

**Question:** "What would you like to do?"

**Options:**
1. **Keep current settings** - Verify everything works
2. **Reconfigure** - Start fresh with new settings
3. **Switch image variant** - Change between lite/full
4. **Update screenshot directory** - Change where screenshots are found

If they choose "Keep current settings", skip to Step 6 (Verify Setup).

### Step 3: Image Choice (new config or reconfigure)

Use AskUserQuestion:

**Question:** "Which Docker image do you want?"

**Options:**

1. **Lite (Recommended)**
   - ~500 MB, includes ffmpeg + yt-dlp
   - For YouTube videos, screen recordings

2. **Full (with Whisper)**
   - ~4 GB, includes ffmpeg + yt-dlp + whisper
   - For local videos needing speech transcription
   - GPU speeds up transcription (detected: [GPU_OK])

### Step 4: Screenshot Directory

Based on OS_TYPE, suggest default:
- **wsl:** `/mnt/c/Users/<username>/Pictures/Screenshots`
- **macos:** `~/Pictures/Screenshots`
- **linux:** `~/Pictures/Screenshots`

Use AskUserQuestion with suggested default + "Custom path" option.

### Step 5: Save Configuration

```bash
mkdir -p "$HOME/.claude/claude-vision"

cat > "$HOME/.claude/claude-vision/config.json" << EOF
{
    "mode": "docker",
    "os": "$OS_TYPE",
    "image_variant": "$IMAGE_VARIANT",
    "screenshot_dir": "$SCREENSHOT_DIR",
    "created": "$(date -Iseconds)",
    "version": "1.0"
}
EOF
```

### Step 6: Verify Setup

```bash
cv-run --status
```

If cv-run fails, check if Docker image exists and offer to pull/build.

### Step 7: Show Summary

```
=== claude-vision Setup Complete ===

Configuration:
  OS: $OS_TYPE
  Image: $IMAGE_VARIANT
  Screenshot dir: $SCREENSHOT_DIR
  GPU: $GPU_STATUS

Available commands:
  /clipboard    - Read from clipboard (text or image)
  /screenshot   - Analyze latest screenshot
  /video        - Analyze videos (YouTube or local)
```

---

## Notes

- Config: `~/.claude/claude-vision/config.json`
- Video cache: `~/.claude/claude-vision/video-cache/`
- Use `cv-run --status` to check container status
- Use `cv-run --stop` to stop container when not in use
