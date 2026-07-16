#!/usr/bin/env bash
# Claude Code Statusline
# Lightweight status display: [Model] $X.XX today | 1h23m | XX% ctx      <dir>
# (<dir> = leaf of the working directory, flush-right)
#
# Reads JSON from Claude Code via stdin on each assistant message.
# Tracks daily cost across sessions using a small cache file.
#
# Performance: <50ms, <5MB RAM, single jq call
# Dependencies: bash, jq

set -euo pipefail

CACHE_FILE="${HOME}/.claude/.statusline-daily-cost.json"

# Require jq
command -v jq &>/dev/null || { printf '[!] jq required'; exit 0; }

# Read stdin from Claude Code
INPUT=$(cat 2>/dev/null) || true
[[ -z "$INPUT" ]] && exit 0

# Read existing daily cost cache
TODAY=$(date +%Y-%m-%d)
CACHE=$(cat "$CACHE_FILE" 2>/dev/null) || CACHE='null'

# Single jq call: parse input, update cache, compute total, format duration.
# Line 1: model<TAB>context_pct<TAB>daily_total<TAB>duration<TAB>dir_leaf
# Line 2: updated cache JSON
RESULT=$(jq -r -n \
    --argjson input "$INPUT" \
    --argjson cache "$CACHE" \
    --arg today "$TODAY" '
    # Extract fields from Claude Code stdin
    ($input.model.display_name // "?") as $model |
    ($input.cost.total_cost_usd // 0) as $session_cost |
    ($input.context_window.used_percentage // 0) as $ctx_pct |
    ($input.session_id // "unknown") as $sid |
    ($input.cost.total_duration_ms // 0) as $duration_ms |
    # Leaf of the working directory (basename), for the flush-right segment
    (($input.cwd // $input.workspace.current_dir // "") | rtrimstr("/") | split("/") | last // "") as $dir |
    # Format session duration
    (($duration_ms / 1000) | floor) as $secs |
    (if $secs >= 3600 then "\($secs / 3600 | floor)h\($secs % 3600 / 60 | floor)m"
     elif $secs >= 60 then "\($secs / 60 | floor)m"
     else "\($secs)s" end) as $duration |
    # Update daily cost cache
    (if ($cache | type) == "object" and $cache.date == $today
     then $cache else {date: $today, sessions: {}} end) |
    .sessions[$sid] = $session_cost |
    ([.sessions[]] | add // 0) as $total |
    # Output line 1: display values (tab-separated)
    "\($model)\t\($ctx_pct)\t\($total)\t\($duration)\t\($dir)",
    # Output line 2: updated cache JSON
    (. | tojson)
' 2>/dev/null) || RESULT=""

if [[ -n "$RESULT" ]]; then
    IFS=$'\t' read -r MODEL CONTEXT_PCT TOTAL_DAILY DURATION DIR < <(head -1 <<< "$RESULT")
    UPDATED=$(tail -n +2 <<< "$RESULT")

    # Persist cache atomically (write to temp, then rename)
    if [[ -n "$UPDATED" ]]; then
        TMP=$(mktemp "${CACHE_FILE}.XXXXXX" 2>/dev/null) && {
            printf '%s\n' "$UPDATED" > "$TMP"
            mv -f "$TMP" "$CACHE_FILE" 2>/dev/null || rm -f "$TMP" 2>/dev/null
        }
    fi
else
    MODEL="?"
    CONTEXT_PCT=0
    TOTAL_DAILY=0
    DURATION="0s"
    DIR=""
fi

# Context warning threshold
CTX_INT=${CONTEXT_PCT%.*}
if (( CTX_INT >= 90 )); then
    CTX_DISPLAY="🔴 ${CONTEXT_PCT}% ctx"
elif (( CTX_INT >= 75 )); then
    CTX_DISPLAY="⚠ ${CONTEXT_PCT}% ctx"
else
    CTX_DISPLAY="${CONTEXT_PCT}% ctx"
fi

# Assemble the left-hand status; the working-dir leaf sits flush-right.
LEFT=$(LC_NUMERIC=C printf '[%s] $%.2f today | %s | %s' \
    "$MODEL" "${TOTAL_DAILY:-0}" "$DURATION" "$CTX_DISPLAY")

if [[ -n "${DIR:-}" ]]; then
    # Claude Code doesn't pass the terminal width to the statusline command, so
    # detect it ourselves. /dev/tty reaches the real terminal even though our
    # stdout is a pipe; fall back to terminfo, then $COLUMNS.
    COLS=$( { stty size </dev/tty; } 2>/dev/null | awk '{print $2}') || COLS=""
    [[ -n "$COLS" ]] || COLS=$(tput cols 2>/dev/null) || COLS=""
    [[ -n "$COLS" ]] || COLS="${COLUMNS:-}"

    # 1-col right margin avoids wrapping if Claude renders at full width.
    gap=$(( ${COLS:-0} - ${#LEFT} - ${#DIR} - 1 ))
    if [[ -n "$COLS" ]] && (( gap >= 1 )); then
        printf '%s%*s%s' "$LEFT" "$gap" "" "$DIR"
    else
        # Width unknown or line too narrow: degrade to a simple suffix.
        printf '%s | %s' "$LEFT" "$DIR"
    fi
else
    printf '%s' "$LEFT"
fi
