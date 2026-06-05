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

# Send push notification via Bark API
# Exit code 2 = non-blocking error (stderr shown to user, hook does not block)
curl -s -X POST "https://bark.day.app/push" \
  -H 'Content-Type: application/json; charset=utf-8' \
  -d "$(jq -nc \
    --arg title "Claude Code - $TITLE" \
    --arg body "$MESSAGE" \
    --arg subtitle "$TYPE" \
    --arg key "<your key>" \
    '{title: $title, body: $body, subtitle: $subtitle, device_key: $key}')" \
  --max-time 10 > /dev/null 2>&1 || {
    echo "notify: failed to send push notification (type=$TYPE)" >&2
    exit 2
}
