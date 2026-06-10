#!/bin/bash
# Claude Code Hook — forwards notifications & AskUserQuestion prompts to Bark push service
# Handles both Notification events and PreToolUse (AskUserQuestion) events.
# Docs: https://code.claude.com/docs/en/hooks#notification
#       https://code.claude.com/docs/en/hooks#pretooluse
# Reads JSON payload from stdin, parses fields, sends push notification via Bark API.

set -euo pipefail

INPUT=$(cat)

# Helper: safe jq extraction that tolerates control characters in values
_jq() {
  jq -r "$1" <<< "$INPUT" 2>/dev/null || echo ""
}

EVENT=$(_jq '.hook_event_name // "unknown"')
PROJECT=$(_jq '.cwd // empty' | xargs basename 2>/dev/null || echo "")

# Read config from env vars with fallbacks
BARK_KEY="${BARK_KEY:-<your key>}"
BARK_URL="${BARK_BASE_URL:-https://bark.day.app}/push"

# Temp file for passing context between events (keyed by session_id)
SESSION=$(_jq '.session_id // "unknown"')
CONTEXT_FILE="/tmp/claude-code-context-${SESSION}.txt"

# --- Save context from Stop events for idle_prompt to pick up ---
if [ "$EVENT" = "Stop" ]; then
  LAST_MSG=$(_jq '.last_assistant_message // ""')
  if [ -n "$LAST_MSG" ]; then
    # Save a summary (first 300 chars) of what was just completed
    SUMMARY=$(printf '%s' "$LAST_MSG" | head -c 300)
    if [ ${#LAST_MSG} -gt 300 ]; then SUMMARY="${SUMMARY}..."; fi
    printf '%s' "$SUMMARY" > "$CONTEXT_FILE"
  fi
  exit 0  # Stop events don't need a notification; idle_prompt will use the saved context
fi

# --- Build title, subtitle, and body based on event type ---

if [ "$EVENT" = "PermissionRequest" ]; then
  TOOL=$(_jq '.tool_name // "unknown"')

  # Build a human-readable summary of what the action is doing
  case "$TOOL" in
    Bash)
      CMD=$(_jq '.tool_input.command // "unknown command"')
      # Truncate long commands
      if [ ${#CMD} -gt 120 ]; then CMD="${CMD:0:117}..."; fi
      SUMMARY="Run: $CMD"
      ;;
    Write)
      FP=$(_jq '.tool_input.file_path // "unknown"')
      SUMMARY="Write file: $(basename "$FP")"
      ;;
    Edit)
      FP=$(_jq '.tool_input.file_path // "unknown"')
      SUMMARY="Edit file: $(basename "$FP")"
      ;;
    Read)
      FP=$(_jq '.tool_input.file_path // "unknown"')
      SUMMARY="Read file: $(basename "$FP")"
      ;;
    Glob)
      PAT=$(_jq '.tool_input.pattern // "*"')
      SUMMARY="Glob: $PAT"
      ;;
    Grep)
      PAT=$(_jq '.tool_input.pattern // ""')
      SUMMARY="Grep: $PAT"
      ;;
    WebFetch)
      URL=$(_jq '.tool_input.url // "unknown"')
      SUMMARY="Fetch: $URL"
      ;;
    WebSearch)
      QRY=$(_jq '.tool_input.query // "unknown"')
      if [ ${#QRY} -gt 100 ]; then QRY="${QRY:0:97}..."; fi
      SUMMARY="Search: $QRY"
      ;;
    *)
      SUMMARY="Use $TOOL"
      ;;
  esac

  TITLE="Claude Code - Needs Permission"
  SUBTITLE="$TOOL"
  BODY="$SUMMARY"

elif [ "$EVENT" = "PreToolUse" ]; then
  TOOL=$(_jq '.tool_name // "unknown"')

  if [ "$TOOL" = "AskUserQuestion" ]; then
    # Parse questions and options from the tool input
    QUESTIONS_JSON=$(_jq -c '.tool_input.questions // []')
    QUESTION_COUNT=$(jq 'length' <<< "$QUESTIONS_JSON" 2>/dev/null || echo 0)

    # Build a readable message from the questions
    MSG_PARTS=""
    for i in $(seq 0 $((QUESTION_COUNT - 1))); do
      Q=$(jq -r ".[$i].question // \"\"" <<< "$QUESTIONS_JSON" 2>/dev/null || echo "")
      OPTS=$(jq -r ".[$i].options // [] | [.[].label] | join(\", \")" <<< "$QUESTIONS_JSON" 2>/dev/null || echo "")
      MULTI=$(jq -r ".[$i].multiSelect // false" <<< "$QUESTIONS_JSON" 2>/dev/null || echo "false")
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

    # Save question context so idle_prompt can reference it
    printf 'Question: %s' "$(jq -r '.[0].question // ""' <<< "$QUESTIONS_JSON" 2>/dev/null || echo "")" > "$CONTEXT_FILE"
  else
    # Other PreToolUse events (e.g. permission checks) — generic notification
    TITLE="Claude Code - PreToolUse"
    SUBTITLE="$TOOL"
    BODY=$(_jq '.tool_input // {} | tostring')
  fi
else
  # Notification event
  NTYPE=$(_jq '.notification_type // "unknown"')

  if [ "$NTYPE" = "permission_prompt" ]; then
    # Skip — already handled by PermissionRequest hook with richer detail
    exit 0
  elif [ "$NTYPE" = "idle_prompt" ]; then
    # Enrich idle_prompt with context from the preceding Stop or AskUserQuestion event
    TITLE="Claude Code - Idle"
    SUBTITLE="idle_prompt"
    BASE_MSG=$(_jq '.message // "Waiting for your input"')
    SAVED=$(cat "$CONTEXT_FILE" 2>/dev/null || echo "")
    if [ -n "$SAVED" ]; then
      BODY="${BASE_MSG}

${SAVED}"
    else
      BODY="$BASE_MSG"
    fi
  else
    # Other notification types (auth_success, elicitation_*, etc.)
    TITLE="Claude Code - $(_jq '.title // .notification_type // "Claude Code"')"
    SUBTITLE="$NTYPE"
    BODY=$(_jq '.message // "Needs your attention"')
  fi
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
