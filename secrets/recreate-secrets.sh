#!/usr/bin/env bash
# Edit agenix secrets with fzf selection and pre-populated content
#
# Usage:
#   ./recreate-secrets.sh           # Interactive fzf selection
#   ./recreate-secrets.sh --all     # Edit all secrets sequentially
#   ./recreate-secrets.sh <secret>  # Edit a specific secret

set -euo pipefail

cd "$(dirname "$0")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# All known secrets (add new ones here)
SECRETS=(
  "openrouter-api-key.age"
  "fastmail_password.age"
  "fastmail_primary_address.age"
  "trainwreck/telegram-bot-token.age"
  "trainwreck/telegram-bot-token-staging.age"
  "trainwreck/telegram-user-ids.age"
  "trainwreck/openrouter-api-key.age"
  "trainwreck/kagi-api-token.age"
  "trainwreck/gateway-auth-token.age"
  "trainwreck/imgflip-username.age"
  "trainwreck/imgflip-password.age"
  "trainwreck/grem-AGENTS.md.age"
  "trainwreck/grem-SOUL.md.age"
  "trainwreck/grem-TOOLS.md.age"
)

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Try to decrypt a secret, return empty string if it fails
try_decrypt() {
    local secret="$1"
    if [[ -f "$secret" ]]; then
        agenix -d "$secret" 2>/dev/null || true
    fi
}

# Edit a single secret with pre-populated content
edit_secret() {
    local secret="$1"
    local tmpfile
    tmpfile=$(mktemp)
    
    echo -e "${BLUE}Editing:${NC} $secret"
    
    # Try to decrypt existing content into temp file
    if [[ -f "$secret" ]]; then
        if try_decrypt "$secret" > "$tmpfile" 2>/dev/null && [[ -s "$tmpfile" ]]; then
            log_info "Pre-populated with existing decrypted content"
        else
            : > "$tmpfile"  # Ensure empty file
            log_warn "Could not decrypt (no matching key?) - starting with empty buffer"
        fi
    else
        log_info "New secret - starting with empty buffer"
    fi
    
    # Get original checksum
    local original_sum
    original_sum=$(md5sum "$tmpfile" 2>/dev/null | cut -d' ' -f1 || echo "")
    
    # Open editor
    ${EDITOR:-vim} "$tmpfile"
    
    # Check if content changed or is non-empty for new files
    local new_sum
    new_sum=$(md5sum "$tmpfile" 2>/dev/null | cut -d' ' -f1 || echo "")
    
    if [[ ! -s "$tmpfile" ]]; then
        log_warn "Empty content - skipping $secret"
        rm -f "$tmpfile"
        return 1
    fi
    
    if [[ "$original_sum" == "$new_sum" ]] && [[ -f "$secret" ]]; then
        log_info "No changes made - skipping re-encryption"
        rm -f "$tmpfile"
        return 0
    fi
    
    # Encrypt the new content
    # We need to use a custom EDITOR that copies our temp file
    EDITOR="cp '$tmpfile'" agenix -e "$secret"
    rm -f "$tmpfile"
    
    echo -e "${GREEN}✓${NC} Saved $secret"
    return 0
}

# Main logic
main() {
    local selected_secrets=()
    
    if [[ $# -eq 1 ]] && [[ "$1" != "--all" ]]; then
        # Single secret specified
        selected_secrets=("$1")
    elif [[ "${1:-}" == "--all" ]]; then
        # All secrets
        selected_secrets=("${SECRETS[@]}")
    else
        # Interactive fzf selection
        if ! command -v fzf &> /dev/null; then
            log_error "fzf is required for interactive selection. Install it or specify a secret."
            exit 1
        fi
        
        # Build preview showing if file exists and if decryptable
        local preview_cmd='
            secret={}
            if [[ -f "$secret" ]]; then
                echo "Status: EXISTS"
                echo ""
                if content=$(agenix -d "$secret" 2>/dev/null); then
                    echo "--- Decrypted content (first 20 lines) ---"
                    echo "$content" | head -20
                else
                    echo "--- Cannot decrypt (no matching key) ---"
                fi
            else
                echo "Status: NEW (does not exist yet)"
            fi
        '
        
        log_info "Select secrets to edit (TAB to select, ENTER to confirm):"
        echo ""
        
        local selected
        selected=$(printf '%s\n' "${SECRETS[@]}" | fzf --multi \
            --header="Select secrets to edit (TAB=select, CTRL-A=all, ENTER=confirm)" \
            --preview="$preview_cmd" \
            --preview-window=right:50%:wrap \
            --bind="ctrl-a:select-all" \
            --bind="ctrl-d:deselect-all" \
            --height=80% \
            --border \
            --prompt="Secrets> " || true)
        
        if [[ -z "$selected" ]]; then
            log_info "No secrets selected. Exiting."
            exit 0
        fi
        
        while IFS= read -r secret; do
            [[ -n "$secret" ]] && selected_secrets+=("$secret")
        done <<< "$selected"
    fi
    
    echo ""
    log_info "Editing ${#selected_secrets[@]} secret(s)..."
    echo ""
    
    local success=0
    local failed=0
    
    for secret in "${selected_secrets[@]}"; do
        echo "----------------------------------------"
        edit_secret "$secret" && success=$((success + 1)) || failed=$((failed + 1))
        echo ""
    done
    
    echo "----------------------------------------"
    log_info "Done! Edited: $success, Skipped: $failed"
}

main "$@"
