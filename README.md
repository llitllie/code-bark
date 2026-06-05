Created notify.sh. The script:

  1. Reads JSON from stdin (Claude Code hook payload:https://code.claude.com/docs/en/hooks#notification)
  2. Extracts title, notification_type, and message with jq (with defaults)
  3. POSTs to the Bark push API(https://github.com/finb/bark) with the notification data
  4. Exits 0 on success, exit code 2 on failure (non-blocking per hook spec)

First, install bark and get your bark key, then update it in notifiy.sh.

To test it:
```bash
chmod +x notify.sh
echo '{"notification_type":"test","message":"Hello from Claude Code review agent","title":"Claude Code"}' | notify.sh
```

If you're able to receive notification, move it to claude hooks folder:
```bash
cp notify.sh ~/.claude/hooks/
```

To enable it, configure in .claude/settings.json:
```json
{
  "hooks": {
    "Notification": [
      {
        "hooks": {
          "Notification": [
            {
              "matcher": "*",
              "command": "~/.claude/hooks/notify.sh"
            }
          ]
        }
      }
    ]
  }
}
```
