create a notify.sh for claude code Notification: https://code.claude.com/docs/en/hooks#notification .
parse title and message from claude code notification event payload, e.g
```bash
#!/bin/bash
INPUT=$(cat)
TITLE=$(echo "$INPUT" | jq -r '.title')
TYPE=$(echo "$INPUT" | jq -r '.notification_type')
MESSAGE=$(jq -r '.message // "Needs your attention"' <<<"$input")


```
then send title and message as notification with curl like:
```bash
curl -X "POST" "https://bark.day.app/push" \
     -H 'Content-Type: application/json; charset=utf-8' \
     -d '{
  "body": "$MESSAGE",
  "title": "Claude Code - $TITLE",
  "subtitle": "$TYPE",
  "device_key": "<your key>"
}'
```