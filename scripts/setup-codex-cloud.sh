#!/usr/bin/env bash
set -euo pipefail

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
tools_root="$HOME/.local/share/dotfiles-cloud"
skill_source="$repo/flakes/hm-modules/modules/opencode/skills/advisor-council"
skill_link="$HOME/.agents/skills/advisor-council"

if [[ "$(uname -s)" != Linux ]]; then
  echo "This bootstrap is for a Linux Codex Cloud environment." >&2
  exit 1
fi
if [[ -e "$skill_link" || -L "$skill_link" ]] && [[ "$(readlink "$skill_link")" != "$skill_source" ]]; then
  echo "Existing skill at $skill_link points elsewhere. Resolve that before installing." >&2
  exit 1
fi
mkdir -p "$tools_root" "$(dirname -- "$skill_link")"

if command -v nix >/dev/null && nix store info >/dev/null 2>&1; then
  # Let Nix use tracked files when the setup runs from a Git checkout.
  nix build "$repo#cloud-tools" --no-update-lock-file --out-link "$tools_root/profile"
else
  # Match the OpenCode release initially used by the dotfiles flake.
  version=2.0.26
  case "$(uname -m)" in
    x86_64)
      asset=cli-linux-x64-baseline
      sha512=03e3a89e5171350878c61fdd23f61c0d0946fa289186720c4da912b1abc8c94b87bcaa34848ad352ec064b34a6b294bedb6418af1a8a4d0edb985ee326f1b019
      ;;
    aarch64|arm64)
      asset=cli-linux-arm64
      sha512=206df5e88f3056a9dda21cc502858d787f3778c03cb0a40546d31eba4d967e0e0353585a092833009cf7fe06f2b63c21e9b5dd591ed5dc5092adf8e8ada28383
      ;;
    *)
      echo "Unsupported Linux architecture for the portable OpenCode install." >&2
      exit 1
      ;;
  esac

  portable="$tools_root/opencode-$version"
  if [[ ! -x "$portable/bin/opencode" ]]; then
    temp=$(mktemp -d "$tools_root/.opencode.XXXXXXXX")
    trap 'rm -rf -- "$temp"' EXIT
    curl --fail --silent --show-error --location --retry 2 --max-time 120 \
      "https://registry.npmjs.org/@opencode/$asset/-/$asset-$version.tgz" \
      --output "$temp/opencode.tgz"
    printf '%s  %s\n' "$sha512" "$temp/opencode.tgz" | sha512sum --check --status
    tar -xOzf "$temp/opencode.tgz" package/bin/opencode > "$temp/opencode"
    chmod 755 "$temp/opencode"
    "$temp/opencode" --version >/dev/null
    mkdir -p "$portable/bin"
    mv -f -- "$temp/opencode" "$portable/bin/opencode"
  fi
  ln -sfn -- "$portable" "$tools_root/profile"
fi

"$tools_root/profile/bin/opencode" --version
"$tools_root/profile/bin/opencode" run --help >/dev/null
if [[ ! -L "$skill_link" ]]; then
  ln -s -- "$skill_source" "$skill_link"
fi
printf 'Add to PATH: %s/profile/bin\n' "$tools_root"
