#!/usr/bin/env bash
set -e

cd "$(dirname "$0")"

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
)

echo "This script will recreate all secrets."
echo "For each secret, you'll be prompted to confirm, then your editor will open."
echo "Paste the secret value, save, and close the editor."
echo ""

for secret in "${SECRETS[@]}"; do
  echo "----------------------------------------"
  echo "Secret: $secret"
  
  if [[ -f "$secret" ]]; then
    echo "  (file exists, will be overwritten)"
  fi
  
  read -p "Create this secret? [y/n/q] " -n 1 -r
  echo ""
  
  if [[ $REPLY =~ ^[Qq]$ ]]; then
    echo "Quitting."
    exit 0
  elif [[ $REPLY =~ ^[Yy]$ ]]; then
    # Remove existing file if present
    rm -f "$secret"
    # Create/edit the secret
    agenix -e "$secret"
    echo "  ✓ Created $secret"
  else
    echo "  Skipped."
  fi
done

echo ""
echo "Done! All selected secrets have been recreated."
