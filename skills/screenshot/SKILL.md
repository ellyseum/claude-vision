---
name: screenshot
description: Read the latest screenshot and respond to a prompt about it
---

## Instructions

When this skill is invoked with `/screenshot <prompt>`:

The screenshot has already been found by a PreToolUse hook. Check the system-reminder for "Screenshot:" which contains the type and path.

Format: `TYPE:<type>\n<path or info>`

Types:
- `TYPE:IMAGE` - path to latest screenshot follows
- `TYPE:NOT_CONFIGURED` - claude-vision not set up, run `/claude-vision-setup`
- `TYPE:DIR_NOT_FOUND` - configured directory doesn't exist
- `TYPE:NO_SCREENSHOTS` - no screenshots found in directory

### Handle Based on Type

**TYPE:IMAGE**
- Read the image using the Read tool
- Respond to the user's prompt based on what you see
- If no prompt provided, just describe what's in the screenshot

**TYPE:NOT_CONFIGURED**
- Tell user to run `/claude-vision-setup` first

**TYPE:DIR_NOT_FOUND**
- Tell user the configured screenshot directory wasn't found
- Suggest running `/claude-vision-setup` to reconfigure

**TYPE:NO_SCREENSHOTS**
- Tell user no screenshots were found in the configured directory

---

## Example Usage

- `/screenshot what do you think` - General reaction to screenshot
- `/screenshot summarize this conversation` - OCR and summarize text in image
- `/screenshot what's the error here` - Analyze error message in screenshot
- `/screenshot` - Just describe what you see

## Configuration

Screenshot directory is stored in `~/.claude/claude-vision/config.json`. Run `/claude-vision-setup` to configure.

## Default Directories by Platform

| Platform | Default Location |
|----------|-----------------|
| WSL | `/mnt/c/Users/<user>/Pictures/Screenshots` |
| macOS | `~/Desktop` or `~/Pictures/Screenshots` |
| Linux | `~/Pictures/Screenshots` or `~/Pictures` |
