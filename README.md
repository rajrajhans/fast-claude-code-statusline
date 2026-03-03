# claude-code-statusline

Lightweight, performance-focused status bar for Claude Code: `[Opus 4] $12.34 today | 1h23m | 42% ctx`. Built to avoid the CPU overhead of existing alternatives — single `jq` call, <50ms, <5MB RAM.

## Setup

Add to `~/.claude/settings.json`:
```json
{ "hooks": { "AssistantResponse": [{ "type": "command", "command": "/path/to/statusline.sh" }] } }
```

## How it works

Reads Claude Code's JSON stdin on each response. Tracks daily cost across sessions via a cache file (`~/.claude/.statusline-daily-cost.json`). Single `jq` call, <50ms, <5MB RAM.
