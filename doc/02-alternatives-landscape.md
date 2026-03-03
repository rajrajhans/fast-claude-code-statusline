# Alternatives to ccusage for Claude Code Statusline

## Key Insight: Claude Code Already Provides Everything You Need

Before diving into tools, the critical finding: **Claude Code natively pipes a complete JSON payload to your statusline script via stdin** on every assistant message. This JSON includes:

```json
{
  "model": { "id": "claude-opus-4-6", "display_name": "Opus" },
  "cost": { "total_cost_usd": 0.01234 },
  "context_window": { "used_percentage": 8, "remaining_percentage": 92, "context_window_size": 200000 }
}
```

**2 of 3 requirements (model + context) are trivially available from stdin. Cost is available per-session.** The only non-trivial requirement is aggregating cost across all sessions for "today's total spend."

---

## Statusline Tools Comparison

### Tier 1: Best Candidates for Your Use Case

| Tool | Language | Perf | Model | Daily USD | Context | Notes |
|------|----------|------|-------|-----------|---------|-------|
| **cc-statusline** | Bash/jq | 45-80ms, <5MB RAM | Yes | Session + burn rate | Yes (progress bar) | Generates optimized bash script via wizard |
| **CCometixLine** | Rust | Very fast | Yes | Transcript-based | Yes | Rust binary, TOML config, ~1.3k stars |
| **claude-powerline** | Node.js | ~240ms | Yes | Yes (daily budget) | Yes (75/90% warnings) | Segment-based, 678 stars |
| **claude-statusline-powerline** | Node.js | SQLite-backed | Yes | Yes (persistent SQLite) | Yes | Uses local SQLite for cross-session tracking |

### Tier 2: Decent but Tradeoffs

| Tool | Language | Model | Daily USD | Context | Notes |
|------|----------|-------|-----------|---------|-------|
| **ccstatusline** | Node.js | Yes | Session only | Yes | Powerline-style, 2.7k stars, no daily aggregation |
| **ersinkoc/claude-statusline** | Python | Yes | Yes (daily reports) | Yes | Full analytics suite, daemon mode, 100+ themes |
| **levz0r/claude-code-statusline** | Bash | Yes | Session only | Yes | Simple bash script, parses transcripts |

### Tier 3: Other Options

| Tool | Language | Notes |
|------|----------|-------|
| **rz1989s/claude-code-statusline** | Node.js | "Atomic precision" layouts, MCP monitoring |
| **gabriel-dehan/claude_monitor_statusline** | Ruby | Plan-limit based tracking |
| **Wzh0718/CCstatusline** | Python | Wraps ccusage (inherits CPU issues) |
| **@illumin8ca/claude-statusline** | TypeScript | npm package, custom themes |

---

## Detailed Breakdown of Top Candidates

### 1. cc-statusline (Best Lightweight Option)
- **URL**: https://github.com/chongdashu/cc-statusline (~457 stars)
- **Setup**: `npx @chongdashu/cc-statusline@latest init` (interactive wizard)
- **Architecture**: Generates a pure bash script using `jq`. No runtime dependencies beyond bash + jq.
- **Performance**: Target <100ms, typical 45-80ms. Memory <5MB (typical ~2MB). Negligible CPU.
- **Features**: Model, context bars, cost, burn rate, session timer, git info
- **Limitation**: Session-level cost only (not cross-session daily total)

### 2. CCometixLine (Best Performance)
- **URL**: https://github.com/Haleclipse/CCometixLine (~1.3k stars)
- **Architecture**: Rust binary with TOML configuration. Cross-platform npm install with native binaries.
- **Performance**: Rust gives near-zero latency. Includes transcript analysis for token percentages.
- **Features**: Model, directory, git branch, context/token usage
- **Limitation**: Daily cost tracking may require additional configuration

### 3. claude-powerline (Most Feature-Complete)
- **URL**: https://github.com/Owloops/claude-powerline (~678 stars)
- **Architecture**: Node.js. Segment-based with configurable widgets.
- **Performance**: ~240ms full-featured. Individual segments 40-250ms.
- **Features**: Model, tokens, cost, context monitoring with warnings at 75%/90%, daily budget tracking, session/block costs
- **Limitation**: Node.js startup overhead (though much lighter than ccusage)

### 4. claude-statusline-powerline (Best for Persistent Tracking)
- **URL**: https://github.com/spences10/claude-statusline-powerline
- **Architecture**: Maintains `~/.claude/statusline-usage.db` (SQLite) for persistent cross-session tracking
- **Features**: Model, session tokens, cost, context at 75%/90%, cache hit rates
- **Key advantage**: SQLite persistence means daily totals survive across sessions
- **Limitation**: SQLite adds complexity

---

## Non-Statusline Alternatives (CLI Analyzers)

These don't integrate with the statusline but can track daily costs:

| Tool | Language | Speed | Notes |
|------|----------|-------|-------|
| **ccost** | Go (single binary) | Fast | SQLite + WAL, enhanced deduplication, multi-currency |
| **tokscale** | Rust core | Very fast | Multi-platform (Claude, Codex, Gemini, Cursor) |
| **ccusage-py** | Python | Moderate | Python reimplementation of ccusage |
| **claude-code-usage** | Node.js | Moderate | Lightweight single `ccu` command |

---

## macOS Menu Bar Apps

If you want usage tracking outside the terminal:

| App | Notes |
|-----|-------|
| **ccseva** (~748 stars) | Swift/SwiftUI, usage ring, 30s auto-refresh, 7-day charts |
| **ClaudeUsageTracker** | LiteLLM pricing, currency conversion |
| **claude-analyst** | Dashboard, analytics charts, uses ccusage CLI |
| **SessionWatcher** | Real-time monitoring, macOS 15+ |

---

## Observability / Dashboard Solutions

For heavier-duty monitoring:

| Tool | Stack | Notes |
|------|-------|-------|
| **claude-code-otel** | OTel + Prometheus + Grafana | Uses Claude Code's native OTLP support. <90s setup via Docker. |
| **claude-code-monitor** | OTLP receiver + web dashboard | Self-hosted, Prometheus export |
| **claude_telemetry** | Python wrapper | Logs to Logfire/Sentry/Honeycomb/Datadog, <10ms overhead |

---

## Summary: What Satisfies All 3 Requirements?

| Requirement | Available from stdin? | Needs JSONL parsing? |
|---|---|---|
| **Current model** | Yes (`model.display_name`) | No |
| **USD consumed today** (all sessions) | Partially (`cost.total_cost_usd` = session only) | Yes, for cross-session total |
| **Context usage** | Yes (`context_window.used_percentage`) | No |

**Tools that fully satisfy all 3 as a statusline:**
1. ccusage statusline (CPU hog)
2. claude-powerline (daily budget tracking)
3. ersinkoc/claude-statusline (Python, daily reports)
4. claude-statusline-powerline (SQLite persistence)

**Tools that satisfy 2/3 (missing cross-session daily cost):**
1. cc-statusline (fastest, session cost only)
2. CCometixLine (Rust, session cost only)
3. ccstatusline (session cost only)
