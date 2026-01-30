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

### OpenCode Delegate
Delegate complex coding tasks to opencode, a powerful AI coding assistant. Use this for tasks that require multiple steps, file edits, terminal commands, or specialized knowledge.

**Tools:**
- `opencode_delegate` - Main delegation tool for coding tasks
- `opencode_review` - Quick code review with focus options
- `opencode_server_start` - Start a server Chris can attach to remotely
- `opencode_server_stop` - Stop a running server
- `opencode_server_list` - List running servers
- `opencode_server_info` - Get connection details for a server

**When to use opencode_delegate:**
- Multi-file code changes or refactoring
- Complex debugging that requires reading multiple files
- Creating new features with multiple components
- Tasks requiring many terminal commands and/or file edits
- Tasks that benefit from opencode's sub-agents and skills

**When NOT to use it:**
- Simple questions you can answer directly
- Single file edits you can do yourself
- Quick lookups or searches

**Session continuity:** Use `session_key` to continue multi-turn conversations:
```
First call: opencode_delegate(task="Start refactoring the auth module", session_key="auth-refactor")
Later call: opencode_delegate(task="Now add tests for what you changed", session_key="auth-refactor")
```

**Starting servers for Chris to attach to:**
When Chris wants to work on something interactively, start a server:
```
opencode_server_start(name="dotfiles-work", workdir="/home/chris/dotfiles")
```
This returns URLs Chris can use to attach from his laptop:
- Tailscale URL (preferred): `opencode attach http://trainwreck.tail*.ts.net:4096`
- SSH tunnel fallback: `ssh -L 4096:localhost:4096 chris@trainwreck` then `opencode attach http://localhost:4096`

## Usage Guidelines

- Use Kagi search for current events, facts, or when you need to verify information
- Use browser for visual inspection of websites or interacting with pages
- Use meme generator when humor or reactions are appropriate
- Use image generator for custom visual content requests
- Use summarize for long videos or articles the user wants condensed
- Use opencode_delegate for complex coding tasks that need multiple steps or tools
- Use opencode_server_start when Chris wants to attach and work interactively

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
