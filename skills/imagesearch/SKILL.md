---
name: imagesearch
description: Visual research - search the web, find images, analyze them visually
---

## Instructions

Search the web for visual information, download and analyze relevant images, and synthesize findings.

### Usage

```
/imagesearch <query>
/imagesearch majormud color system
/imagesearch "retro BBS door game UI design"
/imagesearch what font does discord use
```

### Workflow

1. **WebSearch** for the query + relevant visual terms (add "screenshot", "UI", "design", "example" etc. as appropriate)

2. **WebFetch** promising results to extract:
   - Text information about the topic
   - Image URLs from markdown `![alt](url)` tags

3. **Download images** to `/tmp/imagesearch-$$` using curl:
   ```bash
   curl -sL "https://example.com/image.png" -o /tmp/imagesearch-$$/image-001.png
   ```

4. **Read** the downloaded images to analyze them visually

5. **Synthesize** findings into actionable information:
   - What you learned from text sources
   - What you observed in the images
   - Implementation recommendations if requested

### Tips

- Add visual search terms to queries: "screenshot", "example", "UI", "design", "color palette"
- Prioritize images from documentation, wikis, and official sources
- Skip tiny images (icons, avatars) - look for screenshots and diagrams
- If a site blocks fetching, try alternative sources
- Clean up temp files when done: `rm -rf /tmp/imagesearch-$$/`

### Image Analysis Focus

When analyzing images, pay attention to:
- Color palettes and hex values
- Typography and font choices
- Layout and spacing patterns
- UI component styles
- Visual hierarchy
- Any text visible in screenshots

### Example Session

```
User: /imagesearch majormud color system

Claude:
1. Searches "majormud color system screenshot ANSI"
2. Fetches wiki pages, finds image URLs
3. Downloads screenshots to /tmp
4. Analyzes the visual style:
   - ANSI 16-color palette
   - Cyan for system messages
   - Yellow for item names
   - Red for combat/damage
   - etc.
5. Provides implementation recommendations
```

### Limitations

- Some sites block WebFetch (403 errors) - try alternative sources
- Very large images may take time to download
- Can only analyze static images, not videos/animations
- Google Images directly is not accessible (anti-bot) - we find images through regular page content
