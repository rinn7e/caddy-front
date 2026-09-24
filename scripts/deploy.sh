#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Script: deploy.sh
# Purpose: Deploy the shared proxy to the droplet (run from your Mac): copies
#          docker-compose.yml, pulls the image and starts/updates the proxy.
#          The server's ~/droplet-proxy/.env must contain DEFAULT_SNI.
# Usage:
#   ./scripts/deploy.sh [USER@HOST] [REMOTE_DIR]
#   (USER@HOST defaults to VPS_TARGET in .env)
# ==============================================================================

PROJECT_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
# Only the VPS_TARGET line is read
REMOTE_TARGET="${1:-$(sed -n 's/^VPS_TARGET=//p' "$PROJECT_ROOT/.env" 2>/dev/null || true)}"
REMOTE_DIR="${2:-droplet-proxy}"

if [ -z "$REMOTE_TARGET" ]; then
  echo "❌ Error: Missing remote VPS SSH target (argument or VPS_TARGET in .env)."
  echo ""
  echo "Usage:"
  echo "  ./scripts/deploy.sh [USER@HOST] [REMOTE_DIR]"
  exit 1
fi

if ! ssh "$REMOTE_TARGET" "grep -q '^DEFAULT_SNI=' $(printf '%q' "$REMOTE_DIR/.env") 2>/dev/null"; then
  echo "❌ $REMOTE_TARGET:$REMOTE_DIR/.env has no DEFAULT_SNI. Create it first:"
  echo "   ssh $REMOTE_TARGET \"mkdir -p $REMOTE_DIR && echo DEFAULT_SNI=<server-ip> > $REMOTE_DIR/.env\""
  exit 1
fi

echo "📦 Copying docker-compose.yml to $REMOTE_TARGET:$REMOTE_DIR..."
scp "$PROJECT_ROOT/docker-compose.yml" "$REMOTE_TARGET:$REMOTE_DIR/docker-compose.yml"

# Pulls from registries occasionally stall forever: 5 min limit per attempt, 3 attempts
echo "🚀 Pulling the image and starting the proxy..."
ssh "$REMOTE_TARGET" "cd $(printf '%q' "$REMOTE_DIR") \
  && for i in 1 2 3; do timeout 300 docker compose pull --quiet && break; \
       [ \$i = 3 ] && exit 1; echo \"Image pull failed or stalled (attempt \$i/3), retrying...\"; done \
  && docker compose up -d --wait && docker compose ps"

echo "✨ Proxy deployed to $REMOTE_TARGET! 🎉"
