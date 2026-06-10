#!/bin/bash
# Claude Code Hook — forwards notifications & AskUserQuestion prompts to Bark push service
# Handles both Notification events and PreToolUse (AskUserQuestion) events.
# Docs: https://code.claude.com/docs/en/hooks#notification
#       https://code.claude.com/docs/en/hooks#pretooluse
# Reads JSON payload from stdin, parses fields, sends push notification via Bark API.

set -euo pipefail

INPUT=$(cat)
EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // "unknown"')
PROJECT=$(echo "$INPUT" | jq -r '.cwd // empty' | xargs basename 2>/dev/null || echo "")

# Read config from env vars with fallbacks
BARK_KEY="${BARK_KEY:-<your key>}"
BARK_URL="${BARK_BASE_URL:-https://bark.day.app}/push"

# --- Build title, subtitle, and body based on event type ---

if [ "$EVENT" = "PreToolUse" ]; then
  TOOL=$(echo "$INPUT" | jq -r '.tool_name // "unknown"')

  if [ "$TOOL" = "AskUserQuestion" ]; then
    # Parse questions and options from the tool input
    QUESTIONS_JSON=$(echo "$INPUT" | jq -c '.tool_input.questions // []')
    QUESTION_COUNT=$(echo "$QUESTIONS_JSON" | jq 'length')

    # Build a readable message from the questions
    MSG_PARTS=""
    for i in $(seq 0 $((QUESTION_COUNT - 1))); do
      Q=$(echo "$QUESTIONS_JSON" | jq -r ".[$i].question // \"\"")
      OPTS=$(echo "$QUESTIONS_JSON" | jq -r ".[$i].options // [] | [.[].label] | join(\", \")")
      MULTI=$(echo "$QUESTIONS_JSON" | jq -r ".[$i].multiSelect // false")
      MSG_PARTS="${MSG_PARTS}Q$((i+1)): $Q\n  → $OPTS"
      if [ "$MULTI" = "true" ]; then
        MSG_PARTS="${MSG_PARTS} (multi-select)"
      fi
      if [ $i -lt $((QUESTION_COUNT - 1)) ]; then
        MSG_PARTS="${MSG_PARTS}\n"
      fi
    done

    TITLE="Claude Code - Asks a Question"
    SUBTITLE="AskUserQuestion (${QUESTION_COUNT} question(s))"
    BODY="$MSG_PARTS"
  else
    # Other PreToolUse events (e.g. permission checks) — generic notification
    TITLE="Claude Code - PreToolUse"
    SUBTITLE="$TOOL"
    BODY=$(echo "$INPUT" | jq -r '.tool_input // {} | tostring')
  fi
else
  # Notification event (original behavior)
  TITLE="Claude Code - $(echo "$INPUT" | jq -r '.title // .notification_type // "Claude Code"')"
  SUBTITLE=$(echo "$INPUT" | jq -r '.notification_type // "unknown"')
  BODY=$(echo "$INPUT" | jq -r '.message // "Needs your attention"')
fi

# Prepend project name if available
if [ -n "$PROJECT" ]; then
  BODY="[${PROJECT}] ${BODY}"
fi

# Send push notification via Bark API
# Exit code 2 = non-blocking error (stderr shown to user, hook does not block)
curl -s -X POST "$BARK_URL" \
  -H 'Content-Type: application/json; charset=utf-8' \
  -d "$(jq -nc \
    --arg title "$TITLE" \
    --arg body "$BODY" \
    --arg subtitle "$SUBTITLE" \
    --arg key "$BARK_KEY" \
    '{title: $title, body: $body, subtitle: $subtitle, device_key: $key}')" \
  --max-time 10 > /dev/null 2>&1 || {
    echo "notify: failed to send push notification (event=$EVENT)" >&2
    exit 2
}
