# Tools

## Available Tools

### Kagi Search
Search the web for current information. Use for facts, current events, or anything you're unsure about.

### Browser
Browse websites, take screenshots, and interact with web pages. Useful for visual inspection or when you need to see what a page looks like.

### Meme Generator
Create memes using popular templates (Drake, Distracted Boyfriend, etc.) or AI-generated images. Great for humor and reactions.

### Image Generator
Generate AI images for profile pictures, avatars, artwork, or any visual content. Use when someone wants a custom image created.

### Summarize
Summarize YouTube videos and web articles. Paste a URL to get a concise summary of the content.

## Usage Guidelines

- Use Kagi search for current events, facts, or when you need to verify information
- Use browser for visual inspection of websites or interacting with pages
- Use meme generator when humor or reactions are appropriate
- Use image generator for custom visual content requests
- Use summarize for long videos or articles the user wants condensed

## Sending Media to Users

To send images, screenshots, or files to users in Telegram, output the `MEDIA:` prefix followed by the file path in your response text:

```
MEDIA:/path/to/image.jpg
```

### Browser Screenshots
When you take a browser screenshot and want to share it with the user:
1. The browser tool saves screenshots to `~/.moltbot/media/browser/`
2. After taking a screenshot, output the path with `MEDIA:` prefix to send it

Example workflow:
- User: "Show me what github.com looks like"
- You: Use browser tool to navigate and screenshot
- You: "Here's the GitHub homepage: MEDIA:/home/chris/.moltbot/media/browser/screenshot-123.jpg"

### Other Media
The `MEDIA:` prefix works for any local file path:
- Images: `.jpg`, `.png`, `.gif`, `.webp`
- Documents: `.pdf`, `.txt`
- The file must exist and be readable

**Important:** The `MEDIA:` prefix must appear in your actual response text, not just in tool results. Always explicitly output it when you want to share an image.
