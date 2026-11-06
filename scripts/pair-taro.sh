#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: pair-taro

Run on suremac after taro's nix-darwin configuration is active. The script
creates or reuses taro's ~/.ssh/id_ed25519 key, adds only its public key to
suremac's ~/.ssh/authorized_keys, then verifies SSH from taro back to suremac.
On the first connection, compare taro's host-key fingerprint with the value
verified through a trusted channel before accepting it.
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

if [[ $# -ne 0 ]]; then
  usage >&2
  exit 2
fi

if [[ "${OSTYPE:-}" != darwin* ]]; then
  echo "pair-taro must run on macOS (Darwin)." >&2
  exit 1
fi

if [[ "$(/usr/bin/id -un)" == root ]]; then
  echo "Run pair-taro as chris, not root." >&2
  exit 1
fi

if [[ "$(/usr/bin/id -un)" != chris ]]; then
  echo "Run pair-taro as chris on suremac." >&2
  exit 1
fi

if [[ "$(/usr/sbin/scutil --get LocalHostName 2>/dev/null || true)" != suremac ]]; then
  echo "Activate the suremac configuration first (LocalHostName must be suremac)." >&2
  exit 1
fi

ssh_dir="$HOME/.ssh"
authorized_keys="$ssh_dir/authorized_keys"
local_key="$ssh_dir/id_ed25519"
remote="chris@taro.local"

if [[ -L "$ssh_dir" ]]; then
  echo "Refusing to use a symlink for $ssh_dir." >&2
  exit 1
fi
if [[ -e "$ssh_dir" && ! -d "$ssh_dir" ]]; then
  echo "$ssh_dir exists and is not a directory." >&2
  exit 1
fi
if [[ ! -d "$ssh_dir" ]]; then
  /bin/mkdir -m 700 "$ssh_dir"
fi
/bin/chmod 700 "$ssh_dir"

if [[ ! -f "$local_key" ]]; then
  echo "Required suremac key is missing: $local_key" >&2
  exit 1
fi

if [[ -L "$authorized_keys" ]]; then
  echo "Refusing to modify symlink $authorized_keys." >&2
  exit 1
fi
if [[ -e "$authorized_keys" && ! -f "$authorized_keys" ]]; then
  echo "$authorized_keys exists and is not a regular file." >&2
  exit 1
fi

ssh_args=(
  -p 2222
  -i "$local_key"
  -o IdentitiesOnly=yes
  -o UseKeychain=yes
  -o AddKeysToAgent=yes
)

echo "Connecting to taro. Verify its host-key fingerprint before accepting it."
/usr/bin/ssh "${ssh_args[@]}" -o StrictHostKeyChecking=ask -t "$remote" \
  'set -eu
   umask 077
   mkdir -p "$HOME/.ssh"
   chmod 700 "$HOME/.ssh"
   if [ -L "$HOME/.ssh/id_ed25519" ] || [ -L "$HOME/.ssh/id_ed25519.pub" ]; then
     echo "Refusing to replace a symlinked taro key path." >&2
     exit 1
   fi
   if [ ! -e "$HOME/.ssh/id_ed25519" ]; then
     if [ -e "$HOME/.ssh/id_ed25519.pub" ]; then
       echo "Taro has a public key but no private key at the expected path; refusing to overwrite it." >&2
       exit 1
     fi
     /usr/bin/ssh-keygen -t ed25519 -C chris@taro -f "$HOME/.ssh/id_ed25519"
   fi
   if [ ! -f "$HOME/.ssh/id_ed25519.pub" ]; then
     if [ -e "$HOME/.ssh/id_ed25519.pub" ]; then
       echo "Taro public-key path exists and is not a regular file." >&2
       exit 1
     fi
     /usr/bin/ssh-keygen -y -f "$HOME/.ssh/id_ed25519" > "$HOME/.ssh/id_ed25519.pub"
     chmod 644 "$HOME/.ssh/id_ed25519.pub"
   fi
   test -f "$HOME/.ssh/id_ed25519.pub"'

tmp_pub="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/pair-taro.XXXXXX")"
trap '/bin/rm -f "$tmp_pub"' EXIT

# Retrieve only the public key. Never read or copy taro's private key.
/usr/bin/ssh "${ssh_args[@]}" -o StrictHostKeyChecking=yes "$remote" \
  'cat "$HOME/.ssh/id_ed25519.pub"' > "$tmp_pub"

if [[ "$(/usr/bin/awk 'NF { count++ } END { print count + 0 }' "$tmp_pub")" != 1 ]]; then
  echo "Taro's public-key file must contain exactly one non-empty line." >&2
  exit 1
fi
key_type="$(/usr/bin/awk 'NF { print $1 }' "$tmp_pub")"
key_blob="$(/usr/bin/awk 'NF { print $2 }' "$tmp_pub")"
if [[ "$key_type" != ssh-ed25519 || -z "$key_blob" ]]; then
  echo "Taro's public key is not a single Ed25519 key." >&2
  exit 1
fi
/usr/bin/ssh-keygen -lf "$tmp_pub" >/dev/null

if [[ ! -e "$authorized_keys" ]]; then
  (umask 077 && : > "$authorized_keys")
fi
/bin/chmod 600 "$authorized_keys"

if ! /usr/bin/awk -v type="$key_type" -v blob="$key_blob" \
  '{ for (i = 1; i < NF; i++) if ($i == type && $(i + 1) == blob) found = 1 }
   END { exit !found }' \
  "$authorized_keys"; then
  if [[ -s "$authorized_keys" ]]; then
    last_byte="$(/usr/bin/tail -c 1 "$authorized_keys" | /usr/bin/od -An -tu1 | /usr/bin/tr -d '[:space:]')"
    if [[ "$last_byte" != 10 ]]; then
      /usr/bin/printf '\n' >> "$authorized_keys"
    fi
  fi
  /usr/bin/printf '%s %s chris@taro\n' "$key_type" "$key_blob" >> "$authorized_keys"
  echo "Added taro's public key to $authorized_keys."
else
  echo "Taro's public key is already present in $authorized_keys."
fi

echo "Testing SSH from taro back to suremac."
/usr/bin/ssh "${ssh_args[@]}" -o StrictHostKeyChecking=yes -t "$remote" \
  'host="$(/usr/bin/ssh -p 2222 -i "$HOME/.ssh/id_ed25519" \
    -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes \
    -o UseKeychain=yes -o AddKeysToAgent=yes \
    chris@suremac.local /usr/bin/hostname)"
   if [ "$host" != suremac ]; then
     echo "Reverse SSH reached $host, expected suremac." >&2
     exit 1
   fi
   printf "%s\n" "$host"'

echo "Taro and suremac can now SSH to each other on port 2222."
