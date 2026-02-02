---
name: claude-vision-setup
description: Interactive setup wizard for claude-vision - configures Docker images and platform settings
---

## Instructions

When invoked with `/claude-vision-setup`:

### Step 1: Detect Environment

Run these checks and display results:

```bash
echo "=== Environment Detection ==="

# Detect OS
OS_TYPE="unknown"
if [[ -f /proc/version ]] && grep -qi microsoft /proc/version; then
    OS_TYPE="wsl"
    echo "OS: Windows (WSL)"
elif [[ "$(uname)" == "Darwin" ]]; then
    OS_TYPE="macos"
    echo "OS: macOS"
elif [[ "$(uname)" == "Linux" ]]; then
    OS_TYPE="linux"
    echo "OS: Linux"
fi

# Check Docker
DOCKER_OK="false"
if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
    DOCKER_OK="true"
    echo "Docker: Available"
else
    echo "Docker: Not available"
fi

# Check GPU
GPU_OK="false"
GPU_NAME=""
if command -v nvidia-smi &>/dev/null && nvidia-smi &>/dev/null; then
    GPU_OK="true"
    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
    echo "GPU: $GPU_NAME"

    # Check nvidia container toolkit
    if docker info 2>/dev/null | grep -qi nvidia; then
        echo "NVIDIA Container Toolkit: Installed"
    else
        echo "NVIDIA Container Toolkit: Not installed (GPU won't work in Docker)"
    fi
else
    echo "GPU: Not detected (will use CPU)"
fi

# Check for existing config
CONFIG_FILE="$HOME/.claude/claude-vision/config.json"
if [[ -f "$CONFIG_FILE" ]]; then
    echo ""
    echo "Existing configuration found:"
    cat "$CONFIG_FILE"
fi
```

### Step 2: Explain Image Options

Present this information to the user:

---

**Claude Vision requires Docker to run video processing tools. Choose an image:**

| Image | Size | Includes | Best For |
|-------|------|----------|----------|
| **Lite** | ~500 MB | ffmpeg, yt-dlp | YouTube videos, screen recordings |
| **Full** | ~10 GB | ffmpeg, yt-dlp, whisper | Local videos with speech to transcribe |

**When do you need the Full image?**
- You have local video files (not YouTube) where the audio matters
- You want to transcribe speech from recordings
- YouTube videos don't need this - they have auto-captions

**GPU Acceleration (Full image only):**

| Setup | Whisper Speed | Notes |
|-------|---------------|-------|
| CPU only | ~10x realtime | 1 hour video ≈ 6 min to transcribe |
| GPU (CUDA) | ~50x realtime | 1 hour video ≈ 1 min to transcribe |

To use GPU:
1. NVIDIA GPU required
2. Install NVIDIA drivers
3. Install [nvidia-container-toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html)

---

### Step 3: Ask Image Choice

Use AskUserQuestion to ask which image they want:

**Question:** "Which Docker image do you want?"

**Options:**

1. **Lite (Recommended for most users)**
   - Size: ~500 MB download
   - Includes: ffmpeg, yt-dlp
   - Use for: YouTube videos, screen recordings, any video where you don't need audio transcribed
   - Note: YouTube already has captions - no whisper needed

2. **Full (For local video transcription)**
   - Size: ~4 GB download
   - Includes: ffmpeg, yt-dlp, whisper
   - Use for: Local videos where you need speech-to-text (meetings, lectures, interviews)
   - GPU speeds up transcription 5x (detected: $GPU_STATUS)

**Ask:** "Do you have local videos where you need to transcribe speech? If not, Lite is all you need."

### Step 4: Ask Screenshot Directory

Based on detected OS, suggest a default:

**Defaults:**
- **WSL:** `/mnt/c/Users/<username>/Pictures/Screenshots` (detect from /mnt/c/Users/)
- **macOS:** `~/Pictures/Screenshots` or `~/Desktop`
- **Linux:** `~/Pictures/Screenshots` or `~/Pictures`

Use AskUserQuestion:
- Suggested default path
- "Custom path" option

Verify the path exists:
```bash
if [[ -d "$SCREENSHOT_DIR" ]]; then
    echo "Directory found"
else
    echo "Warning: Directory not found: $SCREENSHOT_DIR"
fi
```

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

echo "Configuration saved to ~/.claude/claude-vision/config.json"
```

### Step 6: Ask Pull vs Build

Use AskUserQuestion:

**Question:** "How do you want to get the Docker image?"

**Options:**

1. **Pull from registry (Recommended)**
   - Downloads pre-built image from ghcr.io
   - Fast: ~1 min for lite, ~5 min for full
   - Requires internet access

2. **Build locally**
   - Builds image on your machine
   - Slower: ~1 min for lite, ~6 min for full
   - Works offline, lets you modify Dockerfile

### Step 7: Get Docker Image

Based on their choices:

**If Pull:**
```bash
cv-run --pull-lite   # or --pull-full
```

**If Build:**
```bash
cv-run --build-lite  # or --build-full
```

If pull fails (network issues), offer to build locally instead.

### Step 8: Verify Setup

```bash
# Test the installation
cv-run --status

# Quick test
cv-run ffmpeg -version | head -1
cv-run yt-dlp --version
```

### Step 9: Show Summary

```
=== claude-vision Setup Complete ===

Configuration:
  Mode: docker
  OS: $OS_TYPE
  Image: $IMAGE_VARIANT
  Screenshot dir: $SCREENSHOT_DIR
  GPU: $GPU_STATUS

Available commands:
  /clipboard    - Read from clipboard (text or image)
  /screenshot   - Analyze latest screenshot
  /video        - Analyze videos (YouTube or local)

Tips:
  - YouTube videos use auto-captions (no whisper needed)
  - Run 'cv-run --status' to check container status
  - Run 'cv-run --stop' to stop the container when not in use
```

---

## Reconfiguration

If config already exists, ask:
- Keep current settings
- Reconfigure from scratch
- Switch image variant (lite ↔ full)
- Update screenshot directory

To switch variants:
```bash
# Stop and remove current container
cv-run --rm

# Update config (change image_variant)
# Rebuild with new variant
cv-run --build-lite  # or --build-full
```

---

## Troubleshooting

**Docker not available:**
- Install Docker Desktop (Windows/Mac) or docker-ce (Linux)
- Make sure Docker daemon is running

**GPU not detected in container:**
1. Verify nvidia-smi works on host
2. Install nvidia-container-toolkit:
   ```bash
   # Ubuntu/Debian
   distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
   curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add -
   curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | sudo tee /etc/apt/sources.list.d/nvidia-docker.list
   sudo apt update && sudo apt install -y nvidia-container-toolkit
   sudo systemctl restart docker
   ```
3. Remove and recreate container: `cv-run --rm` then run any command

**Build takes too long:**
- Lite image builds in ~1 minute
- Full image takes ~6 minutes (downloading PyTorch/CUDA)
- Pre-built images coming soon to ghcr.io

---

## Notes

- Config: `~/.claude/claude-vision/config.json`
- Video cache: `~/.claude/claude-vision/video-cache/`
- Container name: `claude-vision`
- Images: `claude-vision:lite` or `claude-vision:full`
