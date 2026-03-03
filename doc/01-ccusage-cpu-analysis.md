# Why ccusage Consumes So Much CPU

## TL;DR

ccusage's statusline mode has **5 compounding architectural flaws** that turn it into a CPU monster, especially with multiple Claude Code instances. The core issue: it spawns a full Node.js process (~150-600MB RAM each) every ~1 second, but each invocation takes ~10 seconds to complete, creating a **process accumulation cascade** of 30+ zombie processes eating 300%+ CPU.

---

## The 5 Root Causes (Ordered by Impact)

### 1. Process Accumulation Cascade (The Primary Killer)

**How Claude Code's statusline hook works:**
- Invokes your statusline command after each assistant message (debounced at 300ms)
- If a new update triggers while the script is still running, the in-flight execution is cancelled
- Each invocation spawns a **new process** (no persistent daemon)

**The fatal timing mismatch** (measured by users in [Issue #459](https://github.com/ryoppippi/ccusage/issues/459)):
- ccusage statusline takes **~10 seconds** to execute
- Claude Code fires the statusline hook approximately **every ~1 second** during active conversations
- New processes accumulate faster than old ones finish

**Observed impact:**
- 34+ simultaneous `node ccusage statusline` processes
- Each consuming 8-15% CPU
- **Total CPU: 300%+**
- **Memory: 3+ GB** (each process: 150-600MB)
- System load average: 21.73 (normal < 2.0)

The semaphore mechanism added in v15.9.8 uses a filesystem-based JSON lock file in `/tmp/ccusage-semaphore/{sessionId}.lock`, but it has race conditions and doesn't prevent the process from spawning -- only limits computation after spawn.

### 2. Every Invocation Re-Parses ALL JSONL Files From Scratch

The statusline command performs **3 separate heavy data loading operations** on every single invocation:

1. `loadSessionUsageById()` -- finds and parses the current session's JSONL
2. `loadDailyUsageData()` -- loads ALL usage data for today
3. `loadSessionBlockData()` -- loads ALL data to identify 5-hour billing blocks

Each call goes through this pipeline:
```
globUsageFiles()           --> glob('**/*.jsonl') across ALL Claude paths
    |
sortFilesByTimestamp()     --> opens EVERY file to extract first timestamp
    |
processJSONLFileByLine()   --> streams and JSON.parse() each line of EVERY file
    |
v.safeParse(schema)        --> Valibot schema validation per entry
    |
calculateCostForEntry()    --> pricing lookup per entry
```

**The critical bottleneck:** `sortFilesByTimestamp()` calls `getEarliestTimestamp()` on EVERY file via `Promise.all()`, which opens all files simultaneously to extract timestamps.

**Real-world measurements:**
- 750 files / 4GB data: commands timeout
- 8,642 files / 863MB: **28.2 seconds** per invocation
- 216MB data: **18 seconds** per invocation
- One user's session file: **2.4 GB** (crashes Node.js with `ERR_FS_FILE_TOO_LARGE`)

### 3. No Date Pre-Filtering

Even though the statusline only needs **today's** data, `loadDailyUsageData()` first globs and sorts ALL files, parses ALL of them, and only filters by date AFTER all processing:

```typescript
// Pseudocode from data-loader.ts
const allFiles = await globUsageFiles(claudePaths);       // ALL files
const sortedFiles = await sortFilesByTimestamp(allFiles);  // Sort ALL
for (const file of sortedFiles) {
    await processJSONLFileByLine(file, ...);               // Parse EVERY line
}
// Date filtering happens HERE, AFTER all processing
const dateFiltered = filterByDateRange(results, since, until);
```

An unmerged [PR #623](https://github.com/ryoppippi/ccusage/pull/623) proposes file modification time pre-filtering, achieving **18s to 0.6s** (30x speedup). It hasn't been merged.

### 4. `calculateContextTokens()` Reads Entire Transcript Files Into Memory

```typescript
// From data-loader.ts
content = await readFile(transcriptPath, 'utf-8');  // ENTIRE file into memory
const lines = content.split('\n').reverse();         // Creates ANOTHER copy, reversed
// Only needs the LAST few lines, but reads everything
```

For large sessions (hundreds of MB or even GB), this triples memory usage. The statusline does have a fallback using Claude Code's stdin data, but falls back to the full file read when unavailable.

### 5. V8/Node.js Startup Overhead (Per Process)

Each ccusage invocation bootstraps:
1. Full Node.js V8 instance
2. Loads and parses bundled JavaScript
3. Initializes Valibot schema validation
4. Loads prefetched pricing data
5. Performs the full glob/parse/aggregate pipeline

**Per-process memory: 150-600MB**

---

## Multiple Instance Amplification

With multiple Claude Code instances running simultaneously:

1. **Each instance independently spawns its own cascade** of ccusage processes
2. **All instances share `~/.claude/projects/`**, so every ccusage process globs/parses the same files
3. **The semaphore is per-session-ID**, so different sessions don't prevent each other from spawning
4. **File I/O contention**: Multiple processes reading thousands of JSONL files simultaneously creates disk contention, making each process slower, which makes accumulation worse (**vicious feedback loop**)

If you have 3 Claude Code instances, you could see **3x the process accumulation** = 90+ processes, 900%+ CPU.

---

## Attempted Fixes and Their Limitations

| Fix | Version | What it does | Why it's insufficient |
|-----|---------|-------------|----------------------|
| Offline mode default | v15.x | Skips LiteLLM API fetch for pricing | Only eliminates network latency |
| Semaphore lock file | v15.9.8 | JSON file in `/tmp` to prevent concurrent processing | Race conditions; doesn't prevent process spawning |
| Cache with refresh interval | Current | `DEFAULT_REFRESH_INTERVAL_SECONDS = 1` | Cache expires before it can be populated (10s processing > 1s TTL) |

## Unmerged PRs That Would Help

- **[PR #766](https://github.com/ryoppippi/ccusage/pull/766)**: Persistent timestamp cache, reads only first 4KB per file. **28.2s to 8.4s** (3.4x faster). Not merged.
- **[PR #623](https://github.com/ryoppippi/ccusage/pull/623)**: Per-file result caching + file mtime pre-filtering. **18s to 0.6s** (30x faster). Not merged.

---

## The Fundamental Problem

ccusage was designed as a **batch reporting tool** (analyze all usage, generate reports). The statusline mode bolts real-time display onto this batch architecture. Every statusline update runs the full batch pipeline. This is architecturally wrong -- you don't need to re-parse 8,000+ JSONL files to display today's cost.

A Rust-based alternative called [toktrack](https://github.com/mag123c/toktrack) processes 3GB / 2,000+ files in ~0.04 seconds (500x faster), confirming the bottleneck is fundamentally architectural.

---

## References

- [Issue #459: Infinite process spawning loop](https://github.com/ryoppippi/ccusage/issues/459)
- [Issue #804: 300%+ CPU on startup](https://github.com/ryoppippi/ccusage/issues/804)
- [Issue #821: Timeout with large data](https://github.com/ryoppippi/ccusage/issues/821)
- [Issue #455: OOM bug](https://github.com/ryoppippi/ccusage/issues/455)
- [PR #766: Timestamp cache optimization](https://github.com/ryoppippi/ccusage/pull/766)
- [PR #623: File caching + time filtering](https://github.com/ryoppippi/ccusage/pull/623)
