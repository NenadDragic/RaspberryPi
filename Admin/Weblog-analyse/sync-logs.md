# sync-logs.sh

Orchestrates the daily workflow: always fetches logs, but only rebuilds GoAccess reports when the fetch actually brought new or changed data — with multi-year archives, rebuilding is the expensive step, and there's no reason to redo it against unchanged data.

---

## Usage

```console
chmod +x sync-logs.sh
./sync-logs.sh                 # fetch, then build only if something is new
./sync-logs.sh --force         # build regardless of whether anything changed
./sync-logs.sh --no-fetch      # skip the fetch step, build locally
./sync-logs.sh --days 90       # forwarded through to build-reports.sh
```

This is the command meant for daily/cron use — see [Automation in the guide](README.md#7-automatisering).

Prerequisites:

- [fetch-logs.sh](fetch-logs.md) and [build-reports.sh](build-reports.md) present and executable in the same directory as this script (resolved via `BASH_SOURCE`, not `PATH`).
- Same config file as `fetch-logs.sh`/`cleanup-data.sh` at `~/.config/logfetch/config` (optional here — sourced if present, falls back to defaults otherwise).

### Configuration (via `~/.config/logfetch/config`, all optional)

| Variable | Default | Meaning |
|---|---|---|
| `LOCAL_DIR` | `$HOME/weblogs/raw` | Source of raw logs (read as `RAW_DIR`) |
| `REPORTS_DIR` | `$HOME/weblogs/reports` | Where reports get built |
| `STATE_DIR` | `$HOME/weblogs/.state` | Where the change-detection manifest is kept |

### Flags

| Flag | Meaning |
|---|---|
| `--force` | Rebuild reports even if the manifest shows no changes |
| `--no-fetch` | Skip calling `fetch-logs.sh`; only build from what's already local |
| any other arg | Forwarded through unchanged as an argument to `build-reports.sh` (e.g. `--days 90`) |

---

## What the Script Does

### Step 1 – Fetch
Unless `--no-fetch`, runs `fetch-logs.sh` (resolved relative to this script's own directory) and exits with an error if it isn't found/executable.

### Step 2 – Detect changes since the last run
Builds a manifest of every file under `RAW_DIR` as `relative-path|size|mtime`. If no previous manifest exists, treats this as a first run (everything counts as "added"). Otherwise diffs the new manifest against the saved one: new filenames count as **added**, filenames present in both but with a different size/mtime line count as **modified**. This catches both brand-new files and the current month's archive, which grows with every nightly stats run at the host. Prints the added/modified counts.

### Step 3 – Decide whether to rebuild
If nothing changed and `--force` wasn't given, prints a message, discards the new manifest, and exits `0` without touching the reports.

### Step 4 – Build
Runs `build-reports.sh` (same directory-relative resolution) with `RAW_DIR`/`REPORTS_DIR` and any forwarded flags. **Only on success** does it replace the saved manifest with the new one — a failed build leaves the old manifest in place so the same changed data is picked up and retried on the next run instead of being considered "already handled". On failure, the new manifest is discarded and the script exits with `build-reports.sh`'s exit code.

---

## Notes

- **Idempotent/safe to re-run:** re-running with no new data is a fast no-op thanks to the manifest; a failed build never silently marks data as processed.
- **Change detection is size+mtime based, not a hash** — cheap, but in principle a same-size same-mtime overwrite could go undetected. In practice this only matters for the current month's growing archive files, which do change size on every append.
- The manifest is only ever written after a successful build, which is the key guarantee that keeps failures self-healing on the next run rather than silently skipped.
- Depends on `comm` and `grep -Fxf`, both GNU coreutils/grep behavior.
- Console output and comments in the script are in Danish; this document is in English.
