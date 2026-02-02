---
name: video
description: Analyze a video or screen recording by extracting frames and describing what happened
---

## Instructions

When this command is invoked:

### Command Variants

| Command | Description |
|---------|-------------|
| `/video <url/path> <question>` | Analyze video (uses cache if available) |
| `/video <question>` | Analyze latest screen recording |
| `/video follow-up <question>` or `/video -f <question>` | Ask about the most recently analyzed video |
| `/video --list` | Show all cached videos |
| `/video --clear` | Remove all cached videos |
| `/video --clear <hash>` | Remove specific cached video |

---

## Setup Check

**IMPORTANT:** Before doing anything else, check if claude-vision is configured:

```bash
CONFIG_FILE="$HOME/.claude/claude-vision/config.json"
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "claude-vision is not configured yet. Starting setup..."
fi
```

If the config file doesn't exist, **immediately run `/claude-vision-setup`** to configure, then return here and continue with the user's original request.

---

## Cache System

All analyzed videos are cached for fast follow-up questions.

**Cache location:** `~/.claude/claude-vision/video-cache/<hash>/`

**Cache structure:**
```
~/.claude/claude-vision/video-cache/
├── <url-or-path-hash>/
│   ├── metadata.json    # URL/path, title, duration, timestamp
│   ├── subtitles.srt    # transcript (if available)
│   ├── frames/          # extracted frames
│   └── analysis.md      # summary from first analysis
```

---

## Handle Special Commands First

### `/video --list` - List Cached Videos

```bash
CACHE_DIR="$HOME/.claude/claude-vision/video-cache"
if [ -d "$CACHE_DIR" ] && [ -n "$(ls -A "$CACHE_DIR" 2>/dev/null)" ]; then
  for dir in "$CACHE_DIR"/*/; do
    if [ -f "${dir}metadata.json" ]; then
      echo "=== $(basename "$dir") ==="
      cat "${dir}metadata.json"
      echo ""
    fi
  done
else
  echo "No cached videos found."
fi
```

Present the results in a nice table showing: hash (truncated), source, title, duration, and cached date.

### `/video --clear` - Clear All Cache

```bash
rm -rf "$HOME/.claude/claude-vision/video-cache"
echo "Video cache cleared."
```

### `/video --clear <hash>` - Clear Specific Cache

```bash
HASH="<provided_hash>"
rm -rf "$HOME/.claude/claude-vision/video-cache/$HASH"
echo "Removed cache for $HASH"
```

### `/video follow-up <question>` or `/video -f <question>` - Follow-up Question

Find the most recently analyzed video by checking metadata timestamps:

```bash
CACHE_DIR="$HOME/.claude/claude-vision/video-cache"
LATEST=""
LATEST_TIME=0

for dir in "$CACHE_DIR"/*/; do
  if [ -f "${dir}metadata.json" ]; then
    TIME=$(cat "${dir}metadata.json" | grep -o '"timestamp":[0-9]*' | cut -d: -f2)
    if [ -n "$TIME" ] && [ "$TIME" -gt "$LATEST_TIME" ]; then
      LATEST_TIME=$TIME
      LATEST="$dir"
    fi
  fi
done

if [ -z "$LATEST" ]; then
  echo "No cached videos found. Run /video with a URL or path first."
  exit 1
fi

echo "Using cached video: $LATEST"
```

Then:
1. Read all frames from `$LATEST/frames/`
2. Read `$LATEST/subtitles.srt` if it exists
3. Read `$LATEST/analysis.md` for context from the previous analysis
4. Answer the follow-up question based on this cached content

---

## Standard Analysis Flow

### Step 1: Load Config

```bash
CONFIG_FILE="$HOME/.claude/claude-vision/config.json"
if [[ -f "$CONFIG_FILE" ]]; then
    OS_TYPE=$(grep -o '"os"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
else
    # Auto-detect
    if [[ -f /proc/version ]] && grep -qi microsoft /proc/version; then
        OS_TYPE="wsl"
    elif [[ "$(uname)" == "Darwin" ]]; then
        OS_TYPE="macos"
    else
        OS_TYPE="linux"
    fi
fi
```

### Step 2: Generate Cache Hash

```bash
# For URL or path
SOURCE="<url_or_path>"
HASH=$(echo -n "$SOURCE" | md5sum | cut -d' ' -f1)
CACHE_DIR="$HOME/.claude/claude-vision/video-cache/$HASH"
echo "Cache hash: $HASH"
```

### Step 3: Check Cache

```bash
if [ -d "$CACHE_DIR/frames" ] && [ -n "$(ls -A "$CACHE_DIR/frames" 2>/dev/null)" ]; then
  echo "CACHE HIT: Using cached frames and subtitles"
  # Check for subtitles
  if [ -f "$CACHE_DIR/subtitles.srt" ]; then
    echo "Subtitles available in cache"
  fi
  # Check for previous analysis
  if [ -f "$CACHE_DIR/analysis.md" ]; then
    echo "Previous analysis available"
  fi
else
  echo "CACHE MISS: Will download/extract fresh"
fi
```

**If cache exists:** Skip to Step 7 (Read Frames) - read directly from cache.

**If no cache:** Continue with download/extraction, then save to cache.

### Step 4: Determine Video Source (Cache Miss Only)

**If a YouTube URL is provided** (contains `youtube.com` or `youtu.be`):
Download the video AND grab captions/subtitles:
```bash
# Create temp directory
mkdir -p /tmp/video_dl_$$

# Download video (limit to 720p) + subtitles if available
cv-run yt-dlp -f "best[height<=720]" \
  --write-subs --write-auto-subs --sub-lang en \
  --convert-subs srt \
  -o "/tmp/video_dl_$$/video.%(ext)s" "<url>" 2>&1

# Find the downloaded file
VIDEO_FILE=$(ls /tmp/video_dl_$$/video.mp4 /tmp/video_dl_$$/video.webm /tmp/video_dl_$$/video.mkv 2>/dev/null | head -1)

# Check for subtitles
SUBS_FILE=$(ls /tmp/video_dl_$$/*.srt 2>/dev/null | head -1)
if [ -n "$SUBS_FILE" ]; then
  echo "Subtitles found: $SUBS_FILE"
fi

# Get video title from yt-dlp
TITLE=$(cv-run yt-dlp --get-title "<url>" 2>/dev/null || echo "Unknown")
```
**Important:** If subtitles exist, read them first - they provide the audio content as text. Then proceed with frame extraction for visual context.

**If a local path is provided:** Use that video file directly.
```bash
VIDEO_FILE="<provided_path>"
TITLE=$(basename "$VIDEO_FILE")
```

**If no path provided:** Find the latest screen recording. Check these locations based on OS:

**WSL:**
```bash
# Windows Game Bar recordings
SEARCH_DIRS="/mnt/c/Users/*/Videos/Captures /mnt/c/Users/*/Videos"
```

**macOS:**
```bash
SEARCH_DIRS="$HOME/Desktop $HOME/Movies"
```

**Linux:**
```bash
SEARCH_DIRS="$HOME/Videos $HOME/Pictures"
```

Find the newest video file:
```bash
find $SEARCH_DIRS -maxdepth 1 -type f \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.webm" -o -iname "*.mov" \) -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-
```

### Step 5: Get Video Duration

```bash
DURATION=$(cv-run ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$VIDEO_FILE")
echo "Duration: $DURATION seconds"
```

### Step 6: Extract Frames (Cache Miss Only)

**Create cache directory:**
```bash
mkdir -p "$CACHE_DIR/frames"
```

**Strategy:** Use scene detection for intelligent frame extraction, with fallback to time-based sampling. Cap at 30 frames max to stay within reasonable token limits.

**Option A: Scene Detection (preferred for most videos)**
Extracts frames only when the visual content changes significantly:
```bash
# Scene detection: grab frame when >30% pixels change
cv-run ffmpeg -i "$VIDEO_FILE" -vf "select='gt(scene,0.3)',showinfo" -vsync vfr -q:v 2 "$CACHE_DIR/frames/frame_%04d.jpg" 2>/dev/null

# Count frames extracted
FRAME_COUNT=$(ls "$CACHE_DIR/frames"/*.jpg 2>/dev/null | wc -l)
```

**Option B: Time-based Sampling (if scene detection gives too few/many frames)**
Calculate interval to get ~20-30 frames:
```bash
# Calculate fps to get ~25 frames (duration/25 = interval between frames)
cv-run ffmpeg -i "$VIDEO_FILE" -vf "fps=25/$DURATION" -q:v 2 "$CACHE_DIR/frames/frame_%04d.jpg" 2>/dev/null
```

**Frame Cap:** If either method produces >30 frames, keep only every Nth frame to stay under 30 total:
```bash
# If too many frames, thin them out
FRAME_COUNT=$(ls "$CACHE_DIR/frames"/*.jpg | wc -l)
if [ $FRAME_COUNT -gt 30 ]; then
  # Keep every Nth frame where N = ceiling(count/30)
  N=$(( (FRAME_COUNT + 29) / 30 ))
  ls "$CACHE_DIR/frames"/*.jpg | awk "NR % $N != 1" | xargs rm -f
fi
```

**Save subtitles to cache:**
```bash
if [ -n "$SUBS_FILE" ]; then
  cp "$SUBS_FILE" "$CACHE_DIR/subtitles.srt"
fi
```

**Save metadata:**
```bash
cat > "$CACHE_DIR/metadata.json" << EOF
{
  "source": "$SOURCE",
  "title": "$TITLE",
  "duration": $DURATION,
  "timestamp": $(date +%s),
  "cached_date": "$(date -Iseconds)"
}
EOF
```

**Cleanup temp files (but NOT the cache):**
```bash
rm -rf /tmp/video_dl_$$
```

### Step 7: Read Frames

Read all frames from cache using the Read tool:
```bash
ls "$CACHE_DIR/frames"/*.jpg | sort
```

Read them in parallel if there are many, but process them in order when describing.

Also read subtitles if available:
```bash
if [ -f "$CACHE_DIR/subtitles.srt" ]; then
  cat "$CACHE_DIR/subtitles.srt"
fi
```

### Step 8: Analyze and Respond

Based on the sequence of frames (and subtitles if available), describe what happened in the video. Consider:
- What's on screen at the start vs end
- Key transitions or changes between frames
- Any errors, popups, or notable events
- The overall narrative/flow of the session
- What was said (from subtitles)

Respond to the user's prompt based on your analysis.

### Step 9: Save Analysis Summary

After analyzing, save a brief summary for future reference:
```bash
cat > "$CACHE_DIR/analysis.md" << 'EOF'
# Video Analysis Summary

**Source:** <source>
**Analyzed:** <date>

## Summary
<2-3 sentence summary of what the video shows>

## Key Points
- <point 1>
- <point 2>
- <point 3>

## Original Question
<user's question>

## Answer Summary
<brief answer given>
EOF
```

This helps with follow-up questions by providing context from the original analysis.

---

## Example Usage

### Basic Analysis (with caching)
- `/video https://youtube.com/watch?v=xyz what is this about` - Analyze YouTube video (cached)
- `/video /path/to/recording.mp4 explain the bug` - Analyze local video (cached)
- `/video what went wrong` - Analyze latest screen recording (cached)

### Follow-up Questions
- `/video follow-up what was the error message?` - Ask about most recent video
- `/video -f how did they fix it?` - Short form follow-up

### Cache Management
- `/video --list` - See all cached videos
- `/video --clear` - Remove all cached videos
- `/video --clear abc123...` - Remove specific cached video

---

## Notes

- Frame extraction uses `cv-run ffmpeg` (Docker or local)
- YouTube downloads use `cv-run yt-dlp` (Docker or local)
- Cache persists across sessions - use `--clear` to free space
- Follow-up questions are instant since frames are already extracted
- More frames = better understanding but more tokens
- For long videos, consider asking about a specific part
- **YouTube videos:** Auto-downloads captions/subtitles when available
- **Local videos:** Audio transcription available via `cv-run whisper`
- Scene detection + subtitles + ~30 frames = good coverage for most videos
