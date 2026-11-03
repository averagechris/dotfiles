# ChatGPT desktop on thorny

Thorny's Home Manager packages include `chatgpt` and `chatgpt-update` from
`flakes/base-lib/packages/chatgpt-desktop.nix`. This runs the official OpenAI
x86_64 Linux Debian payload inside a Nix FHS compatibility environment. NixOS
is not an officially supported distribution.

Run `chatgpt` or select ChatGPT in the application launcher. The first launch
downloads the official package if necessary. Sign in interactively. The desktop
entry registers the `codex:` authentication callback without claiming normal
HTTP/HTTPS links or document file associations.

Run `chatgpt-update` to fetch the latest official stable package over HTTPS.
Quit and reopen the app afterward. No Nix pin, hash, or system rebuild needs
updating for app releases. The compatibility libraries update with dotfiles.
Downloads and extracted versions live in
`${XDG_DATA_HOME:-~/.local/share}/chatgpt-desktop`; switching the `current`
symlink is atomic, and older versions remain available for manual rollback.
Updates are explicit; there is no background download service. The Nix closure
contains the compatibility environment, not the downloaded application.

Keep the GUI session and app running when using features that require this
computer to be online, and enable the relevant access in the signed-in app.
Installing the app alone does not authenticate or enable remote access.
OpenAI's Linux preview currently lacks GUI Computer Use. XWayland is the
default; native Wayland is experimental (`chatgpt --ozone-platform=wayland`).

Official installation and platform notes:
<https://learn.chatgpt.com/docs/linux/linux-app>.
