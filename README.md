# Code Bark

A single-file Bash hook script that forwards [Claude Code](https://code.claude.com/) notification events to iOS via the [Bark](https://github.com/finb/bark) push notification API.

## Prerequisites

- **Bark app** installed on your iOS device — get your device key from the app
- **`jq`** and **`curl`** installed on your system (standard on most systems)

## Setup

### 1. Configure your device key

Choose one of the following methods.

**Option A — Environment variables** (recommended for multi-project setups):

```bash
export BARK_KEY="your-bark-device-key"
export BARK_BASE_URL="https://bark.day.app"   # default, can be omitted
```

Set them in your shell profile or export them before running Claude Code.

**Option B — Edit the script** directly:

Open `notify.sh` and replace `<your key>` with your actual Bark device key.

### 2. Install the hook

```bash
cp notify.sh ~/.claude/hooks/notify.sh
chmod +x ~/.claude/hooks/notify.sh
```

### 3. Enable it in Claude Code

Add a `Notification` hook in `.claude/settings.json`:

```json
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
```

## Usage

The script runs automatically when Claude Code emits a notification event. It reads a JSON payload from stdin, parses the relevant fields, and sends a push notification to your iOS device.

### Test it

```bash
echo '{"notification_type":"test","message":"Hello from Claude Code","title":"Claude Code","cwd":"/home/user/projects/my-project"}' | bash notify.sh
```

If setup is correct, you'll receive a push notification on your iOS device. The notification body will show `[my-project] Hello from Claude Code` — the project name is detected from the `cwd` field automatically.

## How it works

The script is a linear pipeline:

1. **Read stdin** — captures the JSON payload from Claude Code's hook system
2. **Parse fields** — extracts `title`, `notification_type`, and `message` with sensible defaults
3. **Detect project** — derives the project name from the `cwd` field and prepends it to the notification body (e.g. `[my-project] Message text`)
4. **Push notification** — POSTs to the Bark API with the notification data
5. **Exit** — exits `0` on success, `2` on failure (non-blocking: stderr is shown but Claude Code continues)

## Configuration

The script respects these environment variables:

| Variable | Default | Description |
|---|---|---|
| `BARK_KEY` | `<your key>` | Your Bark device key |
| `BARK_BASE_URL` | `https://bark.day.app` | Base URL of your Bark server (without `/push`, appended automatically) |

Set them in your environment before launching Claude Code, or hardcode them directly in `notify.sh`.

## Files

| File | Purpose |
|---|---|
| `notify.sh` | The hook script (the only source file) |
| `README.md` | This file — project overview and quickstart |
| `notify.md` | Original task specification |

## Technical notes

- Uses `set -euo pipefail` for strict error handling
- JSON is built safely with `jq -nc --arg ...` to avoid shell injection
- `curl` has a 10-second timeout to avoid hanging
- Non-blocking failures exit code `2` per Claude Code hook spec
- Project name is extracted via `basename` of the `cwd` field from the notification payload
