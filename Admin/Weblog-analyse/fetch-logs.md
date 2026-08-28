# fetch-logs.sh

Downloads raw cPanel weblogs from the hosting server via FTP(S), verifies the integrity of what was downloaded, and optionally deletes the verified files on the server afterwards (never the current month's archive).

---

## Usage

```console
chmod +x fetch-logs.sh
./fetch-logs.sh [--dry-run]
```

Run it from anywhere — all paths come from the config file, not the working directory.

Prerequisites:

- `lftp` installed (`sudo apt install lftp`).
- A config file at `~/.config/logfetch/config`, copied from `logfetch.conf.example` and filled in (see that file's doc/comments — it must define `FTP_HOST`, `FTP_USER`, `FTP_PASS` at minimum). The script exits with an error if the file is missing, and warns (but doesn't stop) if its permissions aren't `600`.

### Configuration (via `~/.config/logfetch/config`)

| Variable | Default | Meaning |
|---|---|---|
| `FTP_HOST`, `FTP_USER`, `FTP_PASS` | *(required, no default)* | FTP(S) login; script exits if any is unset |
| `REMOTE_DIR` | `logs` | Remote directory holding the archived logs |
| `LOCAL_DIR` | `$HOME/weblogs/raw` | Local destination for downloaded logs |
| `DELETE_REMOTE` | `no` | Whether to delete verified files on the server after download |
| `USE_FTPS` | `yes` | Whether to force FTP over TLS |
| `FETCH_LIVE` | `no` | Whether to also fetch today's in-progress live logs |
| `LIVE_REMOTE_DIR` | `access-logs` | Remote directory for live (undated) logs |
| `LIVE_LOCAL_DIR` | `$HOME/weblogs/live` | Local destination for live logs |
| `REMOTE_GLOB` | `*.gz` | Filename filter applied to the archived-log download |

---

## What the Script Does

### Step 1 – Load and validate configuration
Fails if `~/.config/logfetch/config` doesn't exist, warns if it's not mode `600`, sources it, and requires `FTP_HOST`/`FTP_USER`/`FTP_PASS` to be set. Exports `FTP_PASS` as `LFTP_PASSWORD` (an environment variable, not a CLI argument) so the password never appears in `ps` output for other users on the machine. Checks `lftp` is installed.

### Step 2 – Download archived logs
Computes the current month's filename suffix (in the `C` locale, so `-Aug-2026` rather than a Danish month name) — files matching it are never deleted later. Runs `lftp mirror --only-newer --no-perms --include-glob "$REMOTE_GLOB"` from `REMOTE_DIR` into `LOCAL_DIR`, over FTPS unless `USE_FTPS=no`.

### Step 3 – Optionally download live logs
If `FETCH_LIVE=yes`, mirrors `LIVE_REMOTE_DIR` into `LIVE_LOCAL_DIR` without `--only-newer` (live logs grow throughout the day, so they must be re-fetched in full each run). A failure here is caught and only prints a warning — it doesn't abort the script.

### Step 4 – Verify downloaded files
Iterates every file directly under `LOCAL_DIR`: empty files are treated as failed transfers and skipped; `.gz` files are tested with `gzip -t` for CRC correctness. Builds a list of verified filenames and a count of failures, printed at the end.

### Step 5 – Optional remote deletion
Skipped entirely (prints a message and exits 0) unless `DELETE_REMOTE=yes`. If any file failed verification, deletion is aborted for the whole run. Otherwise builds a delete list of verified files, excluding any matching the current month's suffix, and prints it. With `--dry-run`, stops here without deleting. Otherwise prompts interactively for confirmation (must type exactly `JA`) before sending `rm -f` commands for each file over the same `lftp` session.

---

## Notes

- **Destructive behavior:** with `DELETE_REMOTE=yes` and no `--dry-run`, this script deletes files on the remote server after an interactive confirmation prompt — never files from the current month, and never anything that failed verification.
- **Idempotent for downloads:** `--only-newer` means re-running without deleting anything is safe and just skips already-downloaded files.
- **Interactive confirmation blocks cron:** the `read -r -p "Fortsæt? (skriv JA): "` prompt will hang a non-interactive/cron run if `DELETE_REMOTE=yes`. Keep `DELETE_REMOTE=no` for scheduled runs.
- The password is deliberately passed via the `LFTP_PASSWORD` environment variable rather than a command-line flag to avoid exposure via `ps`.
- All console output and comments in the script are in Danish; this document is in English.
