# Recommendation: Build Our Own

## Verdict: Build a lightweight custom statusline script

After thorough research, the recommendation is clear: **build our own**. Here's why.

---

## Why Not Use an Existing Alternative?

### The existing tools fall into two camps:

**Camp A: Feature-complete but heavy (inherit ccusage's problems)**
- ccusage, claude-powerline, ersinkoc/claude-statusline
- They all parse JSONL files on every invocation to get daily costs
- Node.js/Python process startup overhead
- Complexity far exceeding what you need

**Camp B: Lightweight but incomplete (missing daily cost)**
- cc-statusline (bash, 45-80ms) -- only shows session cost
- CCometixLine (Rust) -- only shows session cost
- They avoid the CPU issue but don't aggregate daily spend

**No tool hits the sweet spot of: lightweight + daily cost aggregation + minimal CPU.**

---

## The Build Plan

### Architecture: Hybrid Approach

Use **two components** that are dead simple:

#### Component 1: Statusline Script (bash, runs on every update)
- Reads Claude Code's stdin JSON (model, session cost, context %)
- Reads a **single small cache file** for today's aggregate cost
- Prints formatted output
- **Execution time: <50ms, ~2MB RAM, negligible CPU**

#### Component 2: Cost Aggregation Hook (runs on SessionEnd only)
- A `SessionEnd` hook that appends the session's final cost to a daily totals file
- Runs once per session end, not on every message
- **OR**: The statusline script itself does a lightweight scan of today's JSONL files on first invocation, caches the result, and reuses it (refreshing every N minutes)

### Why This Is Better

| Aspect | ccusage statusline | Our custom solution |
|--------|-------------------|-------------------|
| Process model | New Node.js process every ~1s | Bash script, no runtime overhead |
| Data source for model/context | Parses JSONL files | Reads stdin JSON (already provided) |
| Data source for daily cost | Parses ALL JSONL files from scratch | Cache file + lightweight incremental scan |
| Memory per invocation | 150-600MB | <5MB |
| Execution time | ~10 seconds | <50ms |
| CPU with 3 instances | 300%+ | <1% |
| Dependencies | Node.js, npm, TypeScript bundle | bash, jq (already installed on macOS) |

### What the statusline shows

```
[Opus] $1.23 today ($0.45 session) | 42% ctx
```

- `[Opus]` -- current model from `model.display_name`
- `$1.23 today` -- aggregated daily cost from cache file
- `($0.45 session)` -- current session cost from `cost.total_cost_usd`
- `42% ctx` -- context window usage from `context_window.used_percentage`

### Data Available from Claude Code's stdin JSON

Claude Code pipes this to your statusline script on every assistant message:

```json
{
  "model": {
    "id": "claude-opus-4-6",
    "display_name": "Opus"
  },
  "cost": {
    "total_cost_usd": 0.4523,
    "total_duration_ms": 45000,
    "total_api_duration_ms": 2300
  },
  "context_window": {
    "total_input_tokens": 15234,
    "total_output_tokens": 4521,
    "context_window_size": 200000,
    "used_percentage": 42,
    "remaining_percentage": 58
  },
  "session_id": "abc123...",
  "transcript_path": "/path/to/transcript.jsonl"
}
```

**2 of 3 requirements are trivially available.** Only daily aggregate cost needs extra work.

### Daily Cost Aggregation Strategy

**Option A (Simplest): Scan today's JSONL files, cache aggressively**
- On first statusline invocation of the day, scan `~/.claude/projects/` for files modified today
- Sum up token costs from those files using known pricing
- Write result to `~/.claude/.statusline-cache.json` with timestamp
- Subsequent invocations within N minutes read from cache
- Add current session's cost (from stdin) on top
- Refresh cache every 5-10 minutes in the background

**Option B (Lightest): SessionEnd hook accumulator**
- Configure a `SessionEnd` hook that reads the session's final cost
- Appends it to `~/.claude/.daily-cost.json`
- Statusline reads this file + current session cost from stdin
- File gets reset at midnight (or when date changes)
- Zero JSONL parsing during normal operation

**Option C (Hybrid): Combine both**
- Use Option B for ongoing tracking
- Use Option A as a one-time bootstrap (first run of the day)
- Best of both worlds

### Recommended: Option C (Hybrid)

```
First invocation today:
  1. Scan today's JSONL files -> get historical cost
  2. Write to cache file
  3. Display: historical cost + current session cost

Subsequent invocations:
  1. Read cache file (instant)
  2. Add current session cost from stdin
  3. Display total

On session end (hook):
  1. Add session's final cost to cache file
  2. Next session's statusline picks it up automatically
```

---

## Implementation Complexity

**Total effort: ~100 lines of bash + ~20 lines of jq**

Files to create:
1. `statusline.sh` -- main statusline script (~60 lines)
2. `session-end-hook.sh` -- SessionEnd hook for cost accumulation (~30 lines)
3. Installation instructions for `~/.claude/settings.json`

No build step. No dependencies beyond bash + jq. No npm. No Node.js. No compilation.

---

## Risk Assessment

| Risk | Mitigation |
|------|-----------|
| jq not installed | macOS: `brew install jq`. Usually pre-installed. |
| JSONL parsing for daily cost bootstrap | Only runs once per day, only reads today's files (filtered by mtime) |
| Pricing data outdated | Embed current pricing, update manually when models change. Or fetch from LiteLLM once per day. |
| Cache file corruption | Simple JSON with date check. Worst case: re-scan on next invocation. |
| Multiple instances writing cache simultaneously | Use atomic writes (write to temp, rename). Or use flock. |

---

## Comparison with Top Alternatives

If you don't want to build:
- **cc-statusline** is the best off-the-shelf option (45-80ms, pure bash) but only has session cost
- **claude-powerline** has daily budget tracking but is Node.js (~240ms)
- **CCometixLine** is Rust (fastest) but lacks daily cost aggregation

**Building our own gives us exactly what we need with zero bloat.**
