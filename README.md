# claude-vision

Visual context skills for Claude Code. Gives Claude the ability to see your clipboard, screenshots, and videos.

## What's Included

| Skill | Description |
|-------|-------------|
| `/clipboard` | Read text or images from your clipboard |
| `/screenshot` | Analyze your latest screenshot |
| `/video` | Analyze YouTube videos or local recordings |
| `/claude-vision-setup` | Interactive setup wizard |

## Quick Start

```bash
# Clone the plugin
git clone https://github.com/ellyseum/claude-vision.git ~/.claude/plugins/claude-vision

# Start Claude with the plugin
claude --plugin-dir ~/.claude/plugins/claude-vision

# Run setup
/claude-vision-setup
```

## Docker Images

| Image | Size | Includes | Use Case |
|-------|------|----------|----------|
| **Lite** | ~500 MB | ffmpeg, yt-dlp | YouTube, screen recordings |
| **Full** | ~10 GB | ffmpeg, yt-dlp, whisper | Local videos needing transcription |

**Which should I choose?**

- **Lite** - For most users. YouTube has auto-captions, screen recordings usually don't need audio.
- **Full** - Only if you have local videos where you need to transcribe speech.

### GPU Acceleration (Full image only)

Whisper transcription speed:

| Setup | Speed | 1 hour video |
|-------|-------|--------------|
| CPU | ~10x realtime | ~6 minutes |
| GPU (CUDA) | ~50x realtime | ~1 minute |

To enable GPU:
1. NVIDIA GPU + drivers installed
2. Install [nvidia-container-toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html)
3. `cv-run` will auto-detect and enable GPU

## Platform Support

| Feature | WSL | macOS | Linux |
|---------|-----|-------|-------|
| Clipboard (text) | Yes | Yes | Yes (xclip) |
| Clipboard (image) | Yes | Yes (pngpaste) | Yes (xclip) |
| Screenshot | Yes | Yes | Yes |
| Video analysis | Yes | Yes | Yes |

### Prerequisites

**Clipboard/screenshot:**
- **WSL:** PowerShell (built-in)
- **macOS:** `brew install pngpaste` (for images)
- **Linux:** `apt install xclip`

**Video processing:** Docker (required)

## Usage

### Clipboard

```bash
/clipboard what is this?
/clipboard explain this code
/clipboard describe what you see
```

### Screenshot

```bash
/screenshot what's the error here?
/screenshot
```

### Video

```bash
# YouTube (uses auto-captions)
/video https://youtube.com/watch?v=xyz summarize this

# Local recordings
/video what went wrong in my screen recording

# Follow-up questions (cached)
/video follow-up what was the error message?

# Cache management
/video --list
/video --clear
```

## cv-run CLI

The `cv-run` script manages Docker:

```bash
cv-run ffmpeg -i video.mp4 ...   # Run ffmpeg in container
cv-run yt-dlp https://...        # Run yt-dlp
cv-run whisper audio.mp3         # Run whisper (full image only)

# Get images (pick one)
cv-run --pull-lite               # Pull lite from ghcr.io (fast)
cv-run --pull-full               # Pull full from ghcr.io (fast)
cv-run --build-lite              # Build lite locally (~1 min)
cv-run --build-full              # Build full locally (~6 min)

# Container management
cv-run --status                  # Show detailed status
cv-run --stop                    # Stop container
cv-run --rm                      # Remove container
```

Images are hosted at `ghcr.io/ellyseum/claude-vision`.

## Configuration

Config file: `~/.claude/claude-vision/config.json`

```json
{
    "mode": "docker",
    "os": "wsl",
    "image_variant": "lite",
    "screenshot_dir": "/mnt/c/Users/yourname/Pictures/Screenshots",
    "created": "2026-02-02T...",
    "version": "1.0"
}
```

## Project Structure

```
claude-vision/
├── .claude-plugin/           # Plugin metadata
├── Dockerfile                # Full image (ffmpeg, yt-dlp, whisper)
├── Dockerfile.lite           # Lite image (ffmpeg, yt-dlp only)
├── README.md
├── bin/
│   └── cv-run                # Docker/local command router
├── hooks/
│   └── session-start.sh
└── skills/
    ├── clipboard/
    ├── screenshot/
    ├── video/
    └── claude-vision-setup/
```

## Troubleshooting

### Docker not running

```bash
# Start Docker daemon
sudo systemctl start docker

# Or open Docker Desktop
```

### Image not found

```bash
cv-run --pull-lite    # or --pull-full (recommended, fast)
cv-run --build-lite   # or --build-full (if pull fails)
```

### GPU not working in container

```bash
# Check nvidia-smi works on host
nvidia-smi

# Install nvidia-container-toolkit
# See: https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html

# Recreate container
cv-run --rm
cv-run ffmpeg -version  # Will recreate with GPU
```

### Clipboard permission denied (WSL)

Make sure you're in a proper terminal, not a headless SSH session.

### xclip not found (Linux)

```bash
sudo apt install xclip
```

### pngpaste not found (macOS)

```bash
brew install pngpaste
```

## License

MIT
