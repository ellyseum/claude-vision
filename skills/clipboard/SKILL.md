---
name: clipboard
description: Read clipboard contents (text or image) and respond to a prompt about it
---

## Instructions

When this skill is invoked with `/clipboard <prompt>`:

The clipboard contents have already been prepared by a PreToolUse hook. Check the system-reminder for "Clipboard contents:" which contains the type and path/content.

Format: `TYPE:<type>\n<content or path>`

Types: `TEXT`, `IMAGE`, `FILES`, `VIDEO_URL`, `VIDEO_FILE`, `EMPTY`

### Handle Based on Type

**TYPE:TEXT**
- The text content follows on subsequent lines
- Respond to the user's prompt based on the text

**TYPE:IMAGE**
- The path to the saved image follows (e.g., `/tmp/claude-vision/clipboard.png`)
- Read the image using the Read tool
- Respond to the user's prompt based on what you see

**TYPE:FILES**
- File paths follow, one per line
- Image files: Read and analyze
- Video files: Hand off to `/video` skill
- Other: Report file type, read if text-based

**TYPE:VIDEO_URL / TYPE:VIDEO_FILE**
- Hand off to `/video` skill with the URL/path and user's prompt

**TYPE:EMPTY**
- Tell the user the clipboard is empty

---

## Example Usage

- `/clipboard what is this` - Analyze whatever's in clipboard
- `/clipboard summarize` - Summarize text or describe image/video
- `/clipboard fix this code` - If code is in clipboard, suggest fixes
