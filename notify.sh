#!/bin/bash
# Claude Code Notification Hook — forwards notifications to Bark push service
# Docs: https://code.claude.com/docs/en/hooks#notification
# Reads JSON payload from stdin, sends push notification via Bark API.

set -euo pipefail

INPUT=$(cat)

# Extract fields with sensible defaults
TITLE=$(echo "$INPUT" | jq -r '.title // .notification_type // "Claude Code"')
TYPE=$(echo "$INPUT" | jq -r '.notification_type // "unknown"')
MESSAGE=$(echo "$INPUT" | jq -r '.message // "Needs your attention"')
PROJECT=$(echo "$INPUT" | jq -r '.cwd // empty' | xargs basename 2>/dev/null || echo "")

# Read config from env vars with fallbacks
BARK_KEY="${BARK_KEY:-<your key>}"
BARK_URL="${BARK_BASE_URL:-https://bark.day.app}/push"

# Send push notification via Bark API
# Exit code 2 = non-blocking error (stderr shown to user, hook does not block)
curl -s -X POST "$BARK_URL" \
  -H 'Content-Type: application/json; charset=utf-8' \
  -d "$(jq -nc \
    --arg title "Claude Code - $TITLE" \
    --arg body "$MESSAGE" \
    --arg project "$PROJECT" \
    --arg subtitle "$TYPE" \
    --arg key "$BARK_KEY" \
    '{title: $title, body: (if $project != "" then "[\($project)] \($body)" else $body end), subtitle: $subtitle, device_key: $key}')" \
  --max-time 10 > /dev/null 2>&1 || {
    echo "notify: failed to send push notification (type=$TYPE)" >&2
    exit 2
}
