#!/bin/bash
#
# video-process.sh - Download video and extract frames
# Runs async, writes progress to log, outputs COMPLETE when done
#
# Usage: video-process.sh <url-or-path> [log_file]
#

set -e

SOURCE="$1"
LOG_FILE="${2:-/tmp/video-process-$$.log}"
PLUGIN_ROOT="$VISION_PLUGIN_ROOT"
CONFIG_FILE="$HOME/.claude/claude-vision/config.json"
CACHE_BASE="$HOME/.claude/claude-vision/video-cache"

# Helper to log progress
log() {
    echo "[$(date +%H:%M:%S)] $1" >> "$LOG_FILE"
    echo "$1"  # Also stdout for debugging
}

# Get hash for cache key
get_hash() {
    echo -n "$1" | md5sum | cut -d' ' -f1
}

# Check mode from config
get_mode() {
    if [[ -f "$CONFIG_FILE" ]]; then
        grep -o '"mode"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4
    else
        echo "auto"
    fi
}

# Run command via cv-run or locally
run_cmd() {
    local cmd="$1"
    shift
    local mode=$(get_mode)

    if [[ "$mode" == "local" ]]; then
        "$cmd" "$@"
    else
        "$PLUGIN_ROOT/bin/cv-run" "$cmd" "$@"
    fi
}

# Initialize log
echo "STATUS:PROCESSING" > "$LOG_FILE"
log "Starting video processing for: $SOURCE"

# Determine source type and hash
HASH=$(get_hash "$SOURCE")
CACHE_DIR="$CACHE_BASE/$HASH"

# Check if already cached (must have metadata.json = processing completed)
if [[ -f "$CACHE_DIR/metadata.json" ]]; then
    log "Cache hit - already processed"
    echo "STATUS:READY" >> "$LOG_FILE"
    echo "CACHE:$CACHE_DIR" >> "$LOG_FILE"
    echo "COMPLETE" >> "$LOG_FILE"
    exit 0
fi

# Create cache directory
mkdir -p "$CACHE_DIR/frames"

# Download or locate video
TEMP_DIR="/tmp/video_dl_$$"
mkdir -p "$TEMP_DIR"

if [[ "$SOURCE" == *"youtube.com"* ]] || [[ "$SOURCE" == *"youtu.be"* ]]; then
    log "Downloading YouTube video..."

    # Get title first
    TITLE=$(run_cmd yt-dlp --get-title "$SOURCE" 2>/dev/null || echo "Unknown")
    log "Title: $TITLE"

    # Download video + subtitles
    run_cmd yt-dlp -f "best[height<=720]" \
        --write-subs --write-auto-subs --sub-lang en \
        --convert-subs srt \
        -o "$TEMP_DIR/video.%(ext)s" "$SOURCE" 2>&1 | while read line; do
            # Parse progress from yt-dlp output
            if [[ "$line" == *"[download]"*"%"* ]]; then
                PCT=$(echo "$line" | grep -oE '[0-9]+\.[0-9]%' | head -1)
                if [[ -n "$PCT" ]]; then
                    log "Download: $PCT"
                fi
            fi
        done

    VIDEO_FILE=$(ls "$TEMP_DIR"/video.mp4 "$TEMP_DIR"/video.webm "$TEMP_DIR"/video.mkv 2>/dev/null | head -1)
    SUBS_FILE=$(ls "$TEMP_DIR"/*.srt 2>/dev/null | head -1)

elif [[ -f "$SOURCE" ]]; then
    log "Using local file: $SOURCE"
    VIDEO_FILE="$SOURCE"
    TITLE=$(basename "$SOURCE")
else
    log "ERROR: Source not found: $SOURCE"
    echo "STATUS:FAILED" >> "$LOG_FILE"
    echo "ERROR:Source not found" >> "$LOG_FILE"
    exit 1
fi

if [[ -z "$VIDEO_FILE" ]] || [[ ! -f "$VIDEO_FILE" ]]; then
    log "ERROR: No video file found"
    echo "STATUS:FAILED" >> "$LOG_FILE"
    echo "ERROR:No video file" >> "$LOG_FILE"
    exit 1
fi

log "Video file: $VIDEO_FILE"

# Get duration
DURATION=$(run_cmd ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$VIDEO_FILE" 2>/dev/null || echo "0")
log "Duration: ${DURATION}s"

# Extract frames based on subtitle timestamps (storyboard mode) or scene detection
log "Extracting frames..."

if [[ -n "$SUBS_FILE" ]] && [[ -f "$SUBS_FILE" ]]; then
    # STORYBOARD MODE: Extract frames at subtitle timestamps
    log "Using subtitle timestamps for frame extraction..."

    # Parse SRT timestamps (format: 00:01:23,456 --> 00:01:25,789)
    # Extract start times, convert to seconds, dedupe (keep frames >2s apart)
    TIMESTAMPS=$(grep -E '^[0-9]{2}:[0-9]{2}:[0-9]{2},[0-9]{3} -->' "$SUBS_FILE" | \
        sed 's/ -->.*//g' | \
        awk -F'[:,]' '{print ($1*3600)+($2*60)+$3+($4/1000)}' | \
        awk 'NR==1 || $1-prev>=2 {print; prev=$1}')

    FRAME_NUM=0
    TOTAL_TIMESTAMPS=$(echo "$TIMESTAMPS" | wc -l)
    log "Found $TOTAL_TIMESTAMPS unique subtitle timestamps"

    # Cap at 100 timestamps
    if [[ $TOTAL_TIMESTAMPS -gt 100 ]]; then
        TIMESTAMPS=$(echo "$TIMESTAMPS" | awk "NR % $(( (TOTAL_TIMESTAMPS+99)/100 )) == 1")
        log "Capped to $(echo "$TIMESTAMPS" | wc -l) timestamps"
    fi

    for TS in $TIMESTAMPS; do
        FRAME_NUM=$((FRAME_NUM + 1))
        # Format timestamp as 00h00m00s for filename
        TS_INT=${TS%.*}
        HOURS=$((TS_INT / 3600))
        MINS=$(( (TS_INT % 3600) / 60 ))
        SECS=$((TS_INT % 60))
        FRAME_NAME=$(printf "frame_%02dh%02dm%02ds.jpg" $HOURS $MINS $SECS)

        run_cmd ffmpeg -ss "$TS" -i "$VIDEO_FILE" -frames:v 1 -q:v 2 "$CACHE_DIR/frames/$FRAME_NAME" 2>/dev/null

        if [[ $((FRAME_NUM % 10)) -eq 0 ]]; then
            log "Extracted $FRAME_NUM frames..."
        fi
    done

    FRAME_COUNT=$(ls "$CACHE_DIR/frames"/*.jpg 2>/dev/null | wc -l)
    log "Storyboard extraction got $FRAME_COUNT frames"
else
    # SCENE DETECTION MODE: No subtitles, use visual scene changes
    log "No subtitles - using scene detection..."

    run_cmd ffmpeg -i "$VIDEO_FILE" -vf "select='gt(scene,0.2)'" -vsync vfr -q:v 2 "$CACHE_DIR/frames/frame_%04d.jpg" 2>/dev/null

    FRAME_COUNT=$(ls "$CACHE_DIR/frames"/*.jpg 2>/dev/null | wc -l)
    log "Scene detection got $FRAME_COUNT frames"

    # If too few frames, supplement with time-based
    if [[ $FRAME_COUNT -lt 20 ]] && [[ "${DURATION%.*}" -gt 0 ]]; then
        log "Too few frames, adding time-based samples..."
        run_cmd ffmpeg -i "$VIDEO_FILE" -vf "fps=60/${DURATION%.*}" -q:v 2 "$CACHE_DIR/frames/time_%04d.jpg" 2>/dev/null
        FRAME_COUNT=$(ls "$CACHE_DIR/frames"/*.jpg 2>/dev/null | wc -l)
    fi

    # Cap at 100 frames
    if [[ $FRAME_COUNT -gt 100 ]]; then
        log "Capping from $FRAME_COUNT to 100 frames..."
        N=$(( (FRAME_COUNT + 99) / 100 ))
        ls "$CACHE_DIR/frames"/*.jpg | awk "NR % $N != 1" | xargs rm -f
        FRAME_COUNT=$(ls "$CACHE_DIR/frames"/*.jpg | wc -l)
    fi
fi

log "Final frame count: $FRAME_COUNT"

# Copy subtitles if available
if [[ -n "$SUBS_FILE" ]] && [[ -f "$SUBS_FILE" ]]; then
    cp "$SUBS_FILE" "$CACHE_DIR/subtitles.srt"
    log "Saved subtitles"
    HAS_SUBS="true"
else
    HAS_SUBS="false"
fi

# Write metadata
cat > "$CACHE_DIR/metadata.json" << EOF
{
    "source": "$SOURCE",
    "title": "$TITLE",
    "duration": ${DURATION:-0},
    "frame_count": $FRAME_COUNT,
    "has_subtitles": $HAS_SUBS,
    "timestamp": $(date +%s),
    "cached_date": "$(date -Iseconds)"
}
EOF
log "Saved metadata"

# Cleanup temp files
rm -rf "$TEMP_DIR"

# Done!
log "Processing complete!"
echo "STATUS:READY" >> "$LOG_FILE"
echo "CACHE:$CACHE_DIR" >> "$LOG_FILE"
echo "FRAME_COUNT:$FRAME_COUNT" >> "$LOG_FILE"
echo "COMPLETE" >> "$LOG_FILE"
