#!/bin/bash
#
# clipboard-prep.sh - Get clipboard contents using pre-detected platform
#
# Uses env vars exported by SessionStart hook:
#   VISION_OS_TYPE - wsl, macos, or linux
#   VISION_PLUGIN_ROOT - plugin directory
#
# Output format:
#   TYPE:TEXT
#   <text content>
#
#   TYPE:IMAGE
#   /path/to/saved/image.png
#
#   TYPE:FILES
#   /path/to/file1
#   /path/to/file2
#
#   TYPE:VIDEO_URL
#   https://youtube.com/...
#
#   TYPE:VIDEO_FILE
#   /path/to/video.mp4
#
#   TYPE:EMPTY
#

# Use env var if set, otherwise detect
if [[ -n "$VISION_OS_TYPE" ]]; then
    OS_TYPE="$VISION_OS_TYPE"
elif [[ -f /proc/version ]] && grep -qi microsoft /proc/version 2>/dev/null; then
    OS_TYPE="wsl"
elif [[ "$(uname)" == "Darwin" ]]; then
    OS_TYPE="macos"
else
    OS_TYPE="linux"
fi
TEMP_DIR="/tmp/claude-vision"
mkdir -p "$TEMP_DIR"

detect_and_get_clipboard() {
    case "$OS_TYPE" in
        wsl)
            # Check clipboard type first
            CLIP_TYPE=$(powershell.exe -command '
                Add-Type -AssemblyName System.Windows.Forms
                if ([System.Windows.Forms.Clipboard]::ContainsFileDropList()) {
                    Write-Output "FILES"
                } elseif ([System.Windows.Forms.Clipboard]::ContainsImage()) {
                    Write-Output "IMAGE"
                } elseif ([System.Windows.Forms.Clipboard]::ContainsText()) {
                    Write-Output "TEXT"
                } else {
                    Write-Output "EMPTY"
                }
            ' 2>/dev/null | tr -d '\r')

            case "$CLIP_TYPE" in
                FILES)
                    echo "TYPE:FILES"
                    # Get file paths, convert to WSL paths
                    powershell.exe -command '
                        Add-Type -AssemblyName System.Windows.Forms
                        $files = [System.Windows.Forms.Clipboard]::GetFileDropList()
                        foreach ($f in $files) { Write-Output $f }
                    ' 2>/dev/null | while IFS= read -r win_path; do
                        win_path=$(echo "$win_path" | tr -d '\r')
                        # Convert Windows path to WSL path
                        wsl_path=$(echo "$win_path" | sed 's|\\|/|g' | sed 's|^\([A-Za-z]\):|/mnt/\L\1|')
                        echo "$wsl_path"

                        # Check if it's a video file
                        if [[ "$wsl_path" =~ \.(mp4|mkv|webm|mov|avi)$ ]]; then
                            # Re-output as video
                            echo "TYPE:VIDEO_FILE" >&2
                            echo "$wsl_path" >&2
                        fi
                    done
                    ;;
                IMAGE)
                    echo "TYPE:IMAGE"
                    IMG_PATH="$TEMP_DIR/clipboard.png"
                    # Save image to temp file
                    WIN_TEMP=$(wslpath -w "$IMG_PATH")
                    powershell.exe -command "
                        Add-Type -AssemblyName System.Windows.Forms
                        \$img = [System.Windows.Forms.Clipboard]::GetImage()
                        if (\$img) { \$img.Save('$WIN_TEMP') }
                    " 2>/dev/null
                    echo "$IMG_PATH"
                    ;;
                TEXT)
                    TEXT=$(powershell.exe -command "Get-Clipboard" 2>/dev/null | tr -d '\r')
                    # Check if text is a video URL
                    if [[ "$TEXT" =~ youtube\.com|youtu\.be ]]; then
                        echo "TYPE:VIDEO_URL"
                        echo "$TEXT"
                    elif [[ "$TEXT" =~ \.(mp4|mkv|webm|mov|avi)$ ]] && [[ -f "$TEXT" ]]; then
                        echo "TYPE:VIDEO_FILE"
                        echo "$TEXT"
                    else
                        echo "TYPE:TEXT"
                        echo "$TEXT"
                    fi
                    ;;
                *)
                    echo "TYPE:EMPTY"
                    ;;
            esac
            ;;

        macos)
            # Check for image first (requires pngpaste)
            IMG_PATH="$TEMP_DIR/clipboard.png"
            if command -v pngpaste &>/dev/null && pngpaste "$IMG_PATH" 2>/dev/null; then
                echo "TYPE:IMAGE"
                echo "$IMG_PATH"
            else
                TEXT=$(pbpaste 2>/dev/null)
                if [[ -z "$TEXT" ]]; then
                    echo "TYPE:EMPTY"
                elif [[ "$TEXT" =~ youtube\.com|youtu\.be ]]; then
                    echo "TYPE:VIDEO_URL"
                    echo "$TEXT"
                elif [[ "$TEXT" =~ \.(mp4|mkv|webm|mov|avi)$ ]] && [[ -f "$TEXT" ]]; then
                    echo "TYPE:VIDEO_FILE"
                    echo "$TEXT"
                else
                    echo "TYPE:TEXT"
                    echo "$TEXT"
                fi
            fi
            ;;

        linux)
            # Check for image
            IMG_PATH="$TEMP_DIR/clipboard.png"
            if xclip -selection clipboard -t TARGETS -o 2>/dev/null | grep -q image/png; then
                xclip -selection clipboard -t image/png -o > "$IMG_PATH" 2>/dev/null
                echo "TYPE:IMAGE"
                echo "$IMG_PATH"
            else
                TEXT=$(xclip -selection clipboard -o 2>/dev/null)
                if [[ -z "$TEXT" ]]; then
                    echo "TYPE:EMPTY"
                elif [[ "$TEXT" =~ youtube\.com|youtu\.be ]]; then
                    echo "TYPE:VIDEO_URL"
                    echo "$TEXT"
                elif [[ "$TEXT" =~ \.(mp4|mkv|webm|mov|avi)$ ]] && [[ -f "$TEXT" ]]; then
                    echo "TYPE:VIDEO_FILE"
                    echo "$TEXT"
                else
                    echo "TYPE:TEXT"
                    echo "$TEXT"
                fi
            fi
            ;;
    esac
}

detect_and_get_clipboard
