---
name: video
description: Analyze a video or screen recording by extracting frames and spawning an analysis agent
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
│   ├── frames/          # extracted frames (up to 100+)
│   └── analysis.md      # summary from previous analysis
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

---

## Standard Analysis Flow

For actual video analysis, this skill extracts frames and transcript, then **spawns the `video-analyzer` agent** with a fresh 200k context to do the heavy analysis.

### Step 1: Determine Video Source

**If follow-up question** (`/video follow-up` or `/video -f`):
Find most recent cached video:
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
```
If found, skip to Step 5 (Spawn Agent).

**If a YouTube URL is provided** (contains `youtube.com` or `youtu.be`):
```bash
mkdir -p /tmp/video_dl_$$

# Download video (limit to 720p) + subtitles if available
cv-run yt-dlp -f "best[height<=720]" \
  --write-subs --write-auto-subs --sub-lang en \
  --convert-subs srt \
  -o "/tmp/video_dl_$$/video.%(ext)s" "<url>" 2>&1

VIDEO_FILE=$(ls /tmp/video_dl_$$/video.mp4 /tmp/video_dl_$$/video.webm /tmp/video_dl_$$/video.mkv 2>/dev/null | head -1)
SUBS_FILE=$(ls /tmp/video_dl_$$/*.srt 2>/dev/null | head -1)
TITLE=$(cv-run yt-dlp --get-title "<url>" 2>/dev/null || echo "Unknown")
```

**If a local path is provided:**
```bash
VIDEO_FILE="<provided_path>"
TITLE=$(basename "$VIDEO_FILE")
```

**If no path provided:** Find the latest screen recording based on OS:

- **WSL:** `/mnt/c/Users/*/Videos/Captures`, `/mnt/c/Users/*/Videos`
- **macOS:** `$HOME/Desktop`, `$HOME/Movies`
- **Linux:** `$HOME/Videos`, `$HOME/Pictures`

```bash
find $SEARCH_DIRS -maxdepth 1 -type f \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.webm" -o -iname "*.mov" \) -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-
```

### Step 2: Check Cache

```bash
SOURCE="<url_or_path>"
HASH=$(echo -n "$SOURCE" | md5sum | cut -d' ' -f1)
CACHE_DIR="$HOME/.claude/claude-vision/video-cache/$HASH"

if [ -d "$CACHE_DIR/frames" ] && [ -n "$(ls -A "$CACHE_DIR/frames" 2>/dev/null)" ]; then
  echo "CACHE HIT: Using cached frames"
else
  echo "CACHE MISS: Will extract fresh"
fi
```

**If cache exists:** Skip to Step 5 (Spawn Agent).

### Step 3: Get Video Duration

```bash
DURATION=$(cv-run ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$VIDEO_FILE")
echo "Duration: $DURATION seconds"
```

### Step 4: Extract Frames and Transcript

**Create cache directory:**
```bash
mkdir -p "$CACHE_DIR/frames"
```

**Frame Extraction Strategy:**

Since the agent has a fresh 200k context, we can be much more generous with frames. Extract up to 100 frames for thorough coverage.

**Option A: Scene Detection (preferred)**
Use a lower threshold to catch more scene changes:
```bash
# Scene detection with 20% change threshold (more frames than before)
cv-run ffmpeg -i "$VIDEO_FILE" -vf "select='gt(scene,0.2)',showinfo" -vsync vfr -q:v 2 "$CACHE_DIR/frames/frame_%04d.jpg" 2>/dev/null

FRAME_COUNT=$(ls "$CACHE_DIR/frames"/*.jpg 2>/dev/null | wc -l)
```

**Option B: Time-based Sampling (fallback or supplement)**
If scene detection gives too few frames (<20), supplement with time-based:
```bash
# Get ~60 evenly-spaced frames
cv-run ffmpeg -i "$VIDEO_FILE" -vf "fps=60/$DURATION" -q:v 2 "$CACHE_DIR/frames/frame_%04d.jpg" 2>/dev/null
```

**Frame Cap:** Keep up to 100 frames (vs 30 before):
```bash
FRAME_COUNT=$(ls "$CACHE_DIR/frames"/*.jpg | wc -l)
if [ $FRAME_COUNT -gt 100 ]; then
  N=$(( (FRAME_COUNT + 99) / 100 ))
  ls "$CACHE_DIR/frames"/*.jpg | awk "NR % $N != 1" | xargs rm -f
fi
```

**Save subtitles to cache:**
```bash
if [ -n "$SUBS_FILE" ]; then
  cp "$SUBS_FILE" "$CACHE_DIR/subtitles.srt"
fi
```

**For local videos without subtitles (full image only):**
If using the full Docker image and no subtitles exist, offer to transcribe:
```bash
# Check if whisper is available
if cv-run whisper --help &>/dev/null; then
  # Extract audio and transcribe
  cv-run ffmpeg -i "$VIDEO_FILE" -vn -acodec pcm_s16le -ar 16000 -ac 1 "/tmp/audio_$$.wav"
  cv-run whisper "/tmp/audio_$$.wav" --model base --output_format srt --output_dir "$CACHE_DIR"
  mv "$CACHE_DIR/audio_$$.srt" "$CACHE_DIR/subtitles.srt" 2>/dev/null
fi
```

**Save metadata:**
```bash
cat > "$CACHE_DIR/metadata.json" << EOF
{
  "source": "$SOURCE",
  "title": "$TITLE",
  "duration": $DURATION,
  "frame_count": $FRAME_COUNT,
  "has_subtitles": $([ -f "$CACHE_DIR/subtitles.srt" ] && echo "true" || echo "false"),
  "timestamp": $(date +%s),
  "cached_date": "$(date -Iseconds)"
}
EOF
```

**Cleanup temp files:**
```bash
rm -rf /tmp/video_dl_$$ /tmp/audio_$$.*
```

### Step 5: Spawn Video Analyzer Agent

Now spawn the `video-analyzer` agent with all the extracted content. The agent gets a fresh 200k context.

**Prepare the agent prompt:**

```
Analyze this video and answer the user's question.

## Video Information
- Title: <title from metadata>
- Duration: <duration> seconds
- Frames extracted: <count>

## User's Question
<the user's question about the video>

## Transcript
<contents of subtitles.srt if it exists, otherwise "No transcript available">

## Frames
<read all frames from $CACHE_DIR/frames/ and include them>
```

**Use the Task tool to spawn the agent:**
```
Task tool with:
- subagent_type: "video-analyzer" (or use the general-purpose agent with the video-analyzer prompt)
- prompt: <the prepared prompt above>
```

The agent will analyze all frames and transcript with its fresh context and return a comprehensive analysis.

### Step 6: Save Analysis Summary

After receiving the agent's response, extract the brief summary and save it:
```bash
cat > "$CACHE_DIR/analysis.md" << 'EOF'
# Video Analysis Summary

**Source:** <source>
**Analyzed:** <date>

## Summary
<agent's brief summary>

## Original Question
<user's question>
EOF
```

### Step 7: Return Results

Present the agent's analysis to the user. The main conversation context stays lean - only the summary is kept, not all the frames.

---

## Why This Uses an Agent

Video analysis can involve 100+ frames and full transcripts. By spawning a dedicated agent:
- Fresh 200k context for thorough analysis
- More frames = better understanding
- Full transcripts without truncation
- Main conversation stays lean
- Follow-up questions reuse cached frames

---

## Notes

- Frame extraction uses `cv-run ffmpeg` (Docker)
- YouTube downloads use `cv-run yt-dlp` (Docker)
- Whisper transcription uses `cv-run whisper` (full image only)
- Cache persists across sessions - use `--clear` to free space
- The agent sees all frames; you only see the analysis
