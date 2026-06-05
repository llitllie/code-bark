# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A single-file Bash hook script (`notify.sh`) that forwards Claude Code notification events to an iOS device via the [Bark](https://github.com/finb/bark) push notification API. No build system, no compilation — the script is used directly.

## Architecture

`notify.sh` is a linear pipeline:

1. Reads a JSON payload from stdin (provided by Claude Code's hook system)
2. Extracts `title`, `notification_type`, and `message` via `jq` with fallback defaults
3. POSTs to `https://bark.day.app/push` with the notification data
4. Exits `0` on success, `2` on failure (non-blocking per Claude Code hook spec — stderr is shown to the user but does not block the main workflow)

Uses `set -euo pipefail`. System dependencies: `jq`, `curl`.

## Key Files

- `notify.sh` — the hook script (must be `chmod +x`)
- `notify.md` — installation, configuration, and testing instructions
- `README.md` — original task specification

## Configuration

The Bark device key placeholder `<your key>` on line 23 of `notify.sh` must be replaced with the user's actual key before use.

## Testing

```bash
echo '{"notification_type":"test","message":"Hello from Claude Code","title":"Claude Code"}' | bash notify.sh
```

## Installation

```bash
cp notify.sh ~/.claude/hooks/notify.sh
chmod +x ~/.claude/hooks/notify.sh
```

Then add a `Notification` hook in `.claude/settings.json` pointing to `~/.claude/hooks/notify.sh`.
