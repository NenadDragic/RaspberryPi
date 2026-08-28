# Weblog-analyse Overview

An index of the scripts in this folder and their documentation. Each script has a matching `.md` file (same base name) describing usage, configuration, step-by-step behavior, and notable gotchas.

---

## Weblog Pipeline

| Script | Doc | Summary |
|---|---|---|
| `goaccess-build.sh` | [goaccess-build.md](goaccess-build.md) | Installs or updates GoAccess by building it from source into `/usr/local`, since Debian's packaged version lags behind upstream; checks the newest release via the GitHub API with a fallback version if that fails. |
| `fetch-logs.sh` | [fetch-logs.md](fetch-logs.md) | Downloads raw cPanel logs home via FTPS with `lftp`, verifies each file (non-empty, valid gzip), and optionally deletes verified files on the server afterwards — never the current month's archive, and only after an interactive confirmation. |
| `build-reports.sh` | [build-reports.md](build-reports.md) | Builds GoAccess HTML reports per domain (all-time, per-month, per-day within a window) plus a combined all-time report and a static `index.html` landing page, from the raw logs. |
| `sync-logs.sh` | [sync-logs.md](sync-logs.md) | Runs `fetch-logs.sh` then `build-reports.sh`, but skips the (expensive) rebuild step entirely when a size/mtime manifest shows no new or changed raw log data since the last successful run. |
| `cleanup-data.sh` | [cleanup-data.md](cleanup-data.md) | Dry-run-by-default cleanup of generated reports, the GoAccess database, old live-log copies, and stale source build trees; raw logs are only ever touched with both `--all` and a configured retention period. |
| `archive-logs.sh` | [archive-logs.md](archive-logs.md) | Lays an rsync `--backup` archive layer over the raw logs so that a corrupted remote overwrite (same filename, newer timestamp, truncated content) can never silently destroy the local copy — the prior version is preserved in a dated `attic/` folder instead. |
| `make-pdf.sh` | [make-pdf.md](make-pdf.md) | Converts this folder's `README.md` guide to `README.pdf`, via pandoc+xelatex (matching the site's typography as closely as possible offline) or wkhtmltopdf as a fallback. |

---

## Notes

- **`README.md`** in this folder is a separate, comprehensive setup-and-operations guide (in Danish) covering the full deployment from a fresh Debian machine through cron automation, NAS backup, and troubleshooting — it is not the doc for any single script here, but background/tutorial material that ties the scripts above together. It is complementary to this Overview, the same way `Backup_NAS_Guide.md` relates to `Overview.md` in `Linux-Scripts/Backup/`. `README.pdf` is its generated PDF, produced by `make-pdf.sh`.
- **`logfetch.conf.example`** is the template for `~/.config/logfetch/config`, which `fetch-logs.sh`, `sync-logs.sh`, `cleanup-data.sh`, and `archive-logs.sh` all read from; it is not itself a script and has no matching `.md`.
- **Danish-language scripts:** all console output and inline comments in every script in this folder are in Danish; every `.md` doc here is written in English, per this repo's documentation convention.
- **Destructive operations:** `fetch-logs.sh` (optional, gated, confirmed remote deletion), `cleanup-data.sh` (gated behind `--yes`, and raw logs specifically behind `--all` + a non-zero retention setting) both touch data that isn't trivially recoverable. `build-reports.sh` and `archive-logs.sh` are non-destructive; `archive-logs.sh` exists specifically to protect against a failure mode in `fetch-logs.sh` (a corrupted remote file silently overwriting a good local copy).
- **Raw logs are treated as irreplaceable throughout this pipeline:** `fetch-logs.sh` never deletes remotely without confirmation, `cleanup-data.sh` defaults to never touching them, and `archive-logs.sh`'s entire purpose is protecting them from silent overwrite.
