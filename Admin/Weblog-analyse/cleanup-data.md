# cleanup-data.sh

Cleans up generated reports, the GoAccess persistence database, old live-log copies, stale GoAccess source build trees, and — only when explicitly opted in — old raw logs. Defaults to a dry run; nothing is deleted without `--yes`.

---

## Usage

```console
chmod +x cleanup-data.sh
./cleanup-data.sh              # dry run: shows what would happen
./cleanup-data.sh --yes        # perform the cleanup
./cleanup-data.sh --all --yes  # also include raw logs (see warning below)
```

Prerequisites:

- `bc` (for the human-readable size formatting).
- Same config file as the other scripts at `~/.config/logfetch/config` (optional — sourced if present).
- Dependency check: the script starts by sourcing the shared `lib/require_tools.sh` (found by walking up from the script's own folder) and stops with an `apt install` hint if any of these are missing: `bc`

### Configuration (via `~/.config/logfetch/config`, all optional)

| Variable | Default | Meaning |
|---|---|---|
| `LOCAL_DIR` | `$HOME/weblogs/raw` | Raw logs directory (read as `RAW_DIR`) |
| `LIVE_LOCAL_DIR` | `$HOME/weblogs/live` | Live-log directory |
| `REPORTS_DIR` | `$HOME/weblogs/reports` | Generated reports directory |
| `GOACCESS_DB_DIR` | `$HOME/weblogs/db` | GoAccess persist-database directory |
| `SRC_ROOT` | `$HOME/src` | Where GoAccess source build trees live |
| `REPORTS_RETENTION_DAYS` | `0` | `0` = delete all reports every run (they're rebuilt from raw logs); `>0` = only delete reports older than N days |
| `LIVE_RETENTION_DAYS` | `7` | Live-log files older than N days are deleted; `0` = delete all |
| `RAW_RETENTION_MONTHS` | `0` | `0` = never delete raw logs (default, deliberate); `>0` = delete raw logs older than N months, but only when `--all` is also passed |
| `KEEP_SOURCE_BUILDS` | `1` | Number of newest `goaccess-*` source trees under `SRC_ROOT` to keep |

### Flags

| Flag | Meaning |
|---|---|
| `--yes` / `-y` | Actually delete; without it, nothing is removed |
| `--all` | Additionally consider raw logs for deletion (still gated by `RAW_RETENTION_MONTHS > 0`) |

---

## What the Script Does

### Step 1 – Reports
Deletes report files older than `REPORTS_RETENTION_DAYS` days, or all of them if the retention is `0` — reports are always rebuildable from raw logs, so deleting them loses nothing.

### Step 2 – GoAccess persist-database
Deletes everything under `GOACCESS_DB_DIR` unconditionally.

### Step 3 – Live logs
Deletes live-log files older than `LIVE_RETENTION_DAYS` days (or all, if `0`) — cPanel rotates these anyway, so they're not usable as history.

### Step 4 – Old GoAccess source trees
Lists `goaccess-*` directories under `SRC_ROOT`, sorted newest-version-first, and deletes all but the newest `KEEP_SOURCE_BUILDS`.

### Step 5 – Raw logs (gated)
Skipped entirely unless `--all` is passed. Even with `--all`, skipped unless `RAW_RETENTION_MONTHS` is greater than `0` — printing a reminder that the default is to keep everything. If both conditions are met, prints an explicit warning that the local copy is the only copy once the host deletes its own logs, then deletes raw log files older than `RAW_RETENTION_MONTHS * 31` days.

### Step 6 – Summary
Prints total files and human-readable total size that were deleted (with `--yes`) or would be deleted (dry run), and reminds the user to add `--yes` if this was a dry run.

---

## Notes

- **Destructive behavior gated behind two independent flags for raw logs specifically:** `--all` on the command line **and** `RAW_RETENTION_MONTHS > 0` in the config. Either one alone changes nothing, which is deliberate — raw logs are the only copy of the history once the hosting provider's own logs are gone.
- **Safe by default:** without `--yes`, the script only prints what it would do; nothing is touched.
- **Reports and the GoAccess database are always safe to delete** since both are fully rebuilt from raw logs by [build-reports.sh](build-reports.md)/[sync-logs.sh](sync-logs.md).
- The `human()` byte-formatting helper uses `bc -l` for the division, so `bc` must be installed.
- Console output and comments in the script are in Danish; this document is in English.
