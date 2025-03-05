"""
Kitty to Claude integration utility

This script facilitates sending text to Claude from kitty terminal with structured
metadata to ensure Claude understands the source and context of the message.

Usage:
  kitty-claude "Some message"                     # Send direct message
  echo "content" | kitty-claude                   # Pipe content
  echo "content" | kitty-claude --file="test.py"  # Pipe with metadata

Structured JSON headers ensure Claude knows what's passed from editor tools.
"""

import sys
import os
import subprocess
import json
import argparse
import platform
import datetime
import mimetypes
from pathlib import Path

# Try to import pygments for better file type detection
try:
    from pygments.lexers import get_lexer_for_filename
    from pygments.util import ClassNotFound

    HAVE_PYGMENTS = True
except ImportError:
    HAVE_PYGMENTS = False


def get_claude_window():
    """Find a Claude window in kitty."""
    try:
        # Run kitty @ ls to get window information
        kitty_ls = subprocess.run(
            ["kitty", "@", "ls"], capture_output=True, text=True, check=True
        )

        # Parse the JSON output
        kitty_data = json.loads(kitty_ls.stdout)

        # First try to find window by process name
        for os_window in kitty_data:
            for tab in os_window.get("tabs", []):
                for window in tab.get("windows", []):
                    # Check foreground processes
                    for proc in window.get("foreground_processes", []):
                        cmdline = proc.get("cmdline", [])
                        for cmd in cmdline:
                            if "claude-code" in cmd:
                                return window.get("id")

        # If not found, try by window title
        for os_window in kitty_data:
            for tab in os_window.get("tabs", []):
                for window in tab.get("windows", []):
                    if "claude" in window.get("title", "").lower():
                        return window.get("id")

        return None

    except Exception as e:
        print(f"Error finding Claude window: {e}", file=sys.stderr)
        return None


def send_to_claude(message):
    """Send message to Claude window or launch new Claude instance."""
    # Early exit for empty messages
    if not message or message.strip() == "":
        print("Error: Empty message. Nothing sent to Claude.", file=sys.stderr)
        return False

    # Check if running in kitty
    if "KITTY_WINDOW_ID" not in os.environ:
        # Not in kitty, use claude-code directly
        try:
            subprocess.run(["claude-code", message], check=True)
            return True
        except subprocess.CalledProcessError as e:
            print(f"Error launching claude-code: {e}", file=sys.stderr)
            return False

    # Find Claude window
    claude_win = get_claude_window()

    if claude_win:
        # Send text to existing Claude window
        try:
            # Send the message
            # Escape message for terminal (replace \n with actual newlines)
            escaped_message = message.replace("\\n", "\n")
            subprocess.run(
                [
                    "kitty",
                    "@",
                    "send-text",
                    f"--match=id:{claude_win}",
                    escaped_message,
                ],
                check=True,
            )
            # Send Enter key using the keyboard approach
            subprocess.run(
                ["kitty", "@", "send-key", f"--match=id:{claude_win}", "enter"],
                check=True,
            )
            # Focus the window
            subprocess.run(
                ["kitty", "@", "focus-window", f"--match=id:{claude_win}"], check=True
            )
            return True
        except subprocess.CalledProcessError as e:
            print(f"Error sending text to Claude window: {e}", file=sys.stderr)
            return False
    else:
        # No Claude window found - error instead of launching a new instance
        print("Error: No Claude window found. Please open a Claude window first.", file=sys.stderr)
        return False


def detect_file_type(filename):
    """Detect file type and language from filename."""
    if not filename:
        return None

    file_info = {}

    # Get file extension and basename
    path = Path(filename)
    file_info["extension"] = path.suffix
    file_info["basename"] = path.name

    # Try to get mimetype
    mime_type, _ = mimetypes.guess_type(filename)
    if mime_type:
        file_info["mime_type"] = mime_type

    # Try to get language from Pygments
    if HAVE_PYGMENTS:
        try:
            lexer = get_lexer_for_filename(filename)
            file_info["language"] = lexer.name
            aliases = lexer.aliases[0] if lexer.aliases else None
            file_info["language_code"] = aliases
        except ClassNotFound:
            pass

    return file_info


def create_structured_message(args, content=""):
    """Create a structured message with metadata and content."""
    # Skip metadata completely if requested
    if args.no_metadata:
        if args.header:
            return f"{args.header}\n\n{content}" if content else args.header
        return content

    # Basic metadata always included
    metadata = {
        "source": "editor_integration",
        "tool": "kitty-claude",
        "timestamp": datetime.datetime.now().isoformat(),
        "system": platform.system(),
        "hostname": platform.node(),
        "editor": "helix",  # Assuming helix as the default editor
    }

    # Add optional metadata if provided
    if args.file:
        metadata["file"] = args.file
        # Add file type information
        file_info = detect_file_type(args.file)
        if file_info:
            metadata["file_info"] = file_info

    if args.line:
        metadata["line"] = args.line
    if args.column:
        metadata["column"] = args.column
    if args.type:
        metadata["content_type"] = args.type
    if args.saved:
        metadata["saved"] = True
    if args.syntax:
        metadata["syntax"] = args.syntax
    if args.snippet:
        metadata["snippet"] = True

    # Create a standard header
    header_lines = [
        "```json",
        json.dumps(metadata, indent=2),
        "```",
        "",
        "The above JSON contains metadata about the following content.",
    ]

    # Add custom header if provided
    if args.header:
        header_lines.append(args.header)

    # Combine arguments as message text if provided
    message_text = " ".join(args.message) if args.message else ""

    # Determine if we should add code block formatting
    should_format_as_code = False
    code_language = ""

    # Try to determine if this is code that should be formatted
    if args.file and not args.no_metadata:
        # Get file extension
        ext = Path(args.file).suffix.lstrip(".")

        # If syntax is explicitly specified, use that
        if args.syntax:
            should_format_as_code = True
            code_language = args.syntax
        # Otherwise try to detect from file info
        elif "file_info" in metadata and "language_code" in metadata["file_info"]:
            should_format_as_code = True
            code_language = metadata["file_info"]["language_code"]
        # Fallback to common extension mapping
        elif ext in [
            "py",
            "js",
            "ts",
            "java",
            "c",
            "cpp",
            "cs",
            "go",
            "rs",
            "rb",
            "php",
            "sh",
            "nix",
            "html",
            "css",
            "json",
            "xml",
            "yaml",
            "md",
        ]:
            should_format_as_code = True
            code_language = ext

    # Create the final message
    final_message = []

    # Always include the structured header (unless no-metadata was specified)
    final_message.extend(header_lines)

    # Add a separator between header and content
    final_message.append("")

    # Command line message takes precedence, then stdin content
    if message_text:
        final_message.append(message_text)

        # If we also have content from stdin, add it after the message text
        if content:
            final_message.append("")
            final_message.append("Additional content from stdin:")
            if should_format_as_code:
                final_message.append(f"```{code_language}")
                final_message.append(content)
                final_message.append("```")
            else:
                final_message.append(content)
    elif content:
        # Just content from stdin
        if should_format_as_code:
            final_message.append(f"```{code_language}")
            final_message.append(content)
            final_message.append("```")
        else:
            final_message.append(content)

    # Join everything with newlines
    return "\n".join(final_message)


def main():
    """Main function to handle inputs and send to Claude."""
    # Create the argument parser
    parser = argparse.ArgumentParser(
        description="Send messages to Claude with structured metadata"
    )
    parser.add_argument("--file", help="Source filename the content is from")
    parser.add_argument("--line", help="Line number in the source file")
    parser.add_argument("--column", help="Column position in the source file")
    parser.add_argument(
        "--type", help="Content type (function, comment, selection, etc.)"
    )
    parser.add_argument(
        "--saved", action="store_true", help="Flag if content is from saved file"
    )
    parser.add_argument("--header", help="Custom header message")
    parser.add_argument("--syntax", help="Force specific syntax highlighting language")
    parser.add_argument(
        "--no-metadata", action="store_true", help="Skip metadata header completely"
    )
    parser.add_argument(
        "--snippet",
        action="store_true",
        help="Mark as a code snippet rather than full file",
    )
    parser.add_argument(
        "message", nargs="*", help="Message text (optional if stdin is provided)"
    )

    # Parse command line arguments
    args = parser.parse_args()

    # Try to read content from stdin if it's not a terminal
    content = ""
    if not sys.stdin.isatty():
        content = sys.stdin.read()

    # If we have no content from stdin and no message arguments, error out
    if not content and not args.message:
        print("Error: No input provided (neither arguments nor stdin)", file=sys.stderr)
        return 1

    # Create the structured message
    message = create_structured_message(args, content)

    # Send the message to Claude
    if send_to_claude(message):
        return 0
    else:
        return 1


if __name__ == "__main__":
    sys.exit(main())
