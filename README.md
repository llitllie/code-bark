# Code Bark

A single-file Bash hook script that forwards [Claude Code](https://code.claude.com/) events to iOS via the [Bark](https://github.com/finb/bark) push notification API.

- **Permission requests** — see what Claude wants to do (e.g., "Run: npm test", "Edit file: config.ts") before approving
- **Questions (AskUserQuestion)** — see every question and its options so you know what to answer
- **Notifications** — idle prompts, auth events, and other alerts

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

Add `Notification`, `PermissionRequest`, and `PreToolUse` hooks in `.claude/settings.json`:

```json
{
  "hooks": {
    "Notification": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/notify.sh"
          }
        ]
      }
    ],
    "PermissionRequest": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/notify.sh"
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "AskUserQuestion",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/notify.sh"
          }
        ]
      }
    ]
  }
}
```

## Usage

The script runs automatically when Claude Code emits a notification or asks you a question. It reads a JSON payload from stdin, detects the event type, and sends a push notification to your iOS device.

### Event types handled

| Event | What triggers it | Example notification |
|---|---|---|
| `Notification` | Idle prompts, auth success, elicitation events, generic alerts | `[my-project] Claude is waiting for your input` |
| `PermissionRequest` | Claude needs your approval to run a tool | `Run: npm test` or `Edit file: config.ts` |
| `PreToolUse` (AskUserQuestion) | Claude asks you a multiple-choice question | `Q1: Which framework? → React, Vue, Svelte` |

When Claude asks a question, the notification body includes every question and its options (e.g., `Q1: Which framework? → React, Vue, Svelte`), so you know exactly what you need to answer.

When Claude requests permission, the notification shows a human-readable summary of what it wants to do — shell commands, file writes, web fetches, searches, and more.

### Test it

**Test a notification event:**

```bash
echo '{"hook_event_name":"Notification","notification_type":"idle_prompt","message":"Claude is waiting for your input","title":"Claude Code","cwd":"/home/user/projects/my-project"}' | bash notify.sh
```

**Test a permission request:**

```bash
echo '{"hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"npm run test -- --coverage"},"cwd":"/home/user/projects/my-project"}' | bash notify.sh
```

**Test an AskUserQuestion event:**

```bash
echo '{"hook_event_name":"PreToolUse","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Which framework?","header":"Framework","options":[{"label":"React"},{"label":"Vue"},{"label":"Svelte"}],"multiSelect":false}]},"cwd":"/home/user/projects/my-project"}' | bash notify.sh
```

If setup is correct, you'll receive a push notification on your iOS device. The notification body will show `[my-project] Hello from Claude Code` — the project name is detected from the `cwd` field automatically.

## How it works

The script handles two hook event types:

### Notification events
1. Reads the JSON payload from stdin
2. Extracts `title`, `notification_type`, `message`, and `cwd`
3. Sends a push notification with the project name prepended

### PermissionRequest events
1. Detects the `PermissionRequest` event
2. Extracts `tool_name` and `tool_input`
3. Builds a human-readable summary based on the tool type:
   - **Bash** → `Run: <command>` (truncated to 120 chars)
   - **Write/Edit/Read** → `Write file: <filename>`
   - **WebFetch** → `Fetch: <url>`
   - **WebSearch** → `Search: <query>`
   - **Glob/Grep** → `Glob: <pattern>` / `Grep: <pattern>`
   - Other tools → `Use <tool_name>`

### AskUserQuestion (PreToolUse) events
1. Detects the `PreToolUse` event with `tool_name: "AskUserQuestion"`
2. Parses the `questions` array — each question's text, header, and options
3. Formats them as `Q1: question text → option1, option2, option3`
4. Includes a `(multi-select)` tag where applicable
5. Sends the question/options as the notification body

### Common pipeline
- **Detect project** — derives the project name from the `cwd` field and prepends it to the notification body (e.g. `[my-project] Q1: Which framework? → React, Vue`)
- **Push notification** — POSTs to the Bark API with the notification data
- **Exit** — exits `0` on success, `2` on failure (non-blocking: stderr is shown but Claude Code continues)

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
