# build-reports.sh

Builds GoAccess HTML reports from raw cPanel access logs: an all-time report per domain, a report per calendar month per domain, an optional report per calendar day per domain (within a configurable window), a combined all-time report across all domains with a vhost panel, and a static `index.html` landing page linking all of it.

---

## Usage

```console
chmod +x build-reports.sh
./build-reports.sh [--days N] [--no-days] [--live] [kildemappe] [outputmappe]
```

Run it anywhere; source and output directories default to `$HOME/weblogs/raw` and `$HOME/weblogs/reports` but can be overridden by the two positional arguments.

Prerequisites:

- `goaccess` on `PATH` (see [goaccess-build.md](goaccess-build.md)).
- GNU `awk`, `find`, `sort`, `mktemp`, `date` (script uses GNU `date -d`).
- Raw log files present in the source directory, named `<domain>-<Mmm>-<YYYY>[.gz]` (cPanel's archive naming) unless `--live` is used.
- Dependency check: the script starts by sourcing the shared `lib/require_tools.sh` (found by walking up from the script's own folder) and stops with an `apt install` hint if any of these are missing: `goaccess`

### Flags

| Flag | Meaning |
|---|---|
| `--days N` | How many days back get their own daily report. Default `60`. `0` means all days ever. |
| `--no-days` | Skip daily reports entirely; build only monthly and all-time. |
| `--live` | Also accept log files without a `-Mmm-YYYY` date suffix in the name (for `~/access-logs/`-style live logs). Without it, undated files are silently ignored so the script can safely run in a folder containing other files. |

### Configuration (top of script)

| Variable | Default | Meaning |
|---|---|---|
| `NOISE` | array of 3 regexes | Log lines filtered out before reporting: ACME `.well-known` challenges, cPanel's own `Cpanel-HTTP-Client` requests, a scraper (`forestengine.net`) impersonating Chrome |
| `STRIP_SUFFIXES` | `(".dragic-playground.info")` | Account-level domain suffix stripped from vhost log filenames to derive a clean domain name |
| `ALIAS` | `(["xn--tnkeboksen-d6a.dk"]="taenkeboksen.dk")` | Merges multiple vhost names (e.g. punycode + ASCII variants) into one domain group |
| `PRETTY` | `(["taenkeboksen.dk"]="tænkeboksen.dk")` | Display-only label override; filenames still use the ASCII key |
| `GA_OPTS` | `(--ignore-crawlers --real-os --agent-list)` | Base GoAccess flags for every report; `--anonymize-ip` is appended automatically if the installed GoAccess version supports it |

---

## What the Script Does

### Step 1 – Parse arguments and set up
Parses `--days`/`--days=`/`--no-days`/`--live`/`-h`/`--help`, then takes the first two remaining positional args as source and output directories. Creates a temp working directory (auto-cleaned on exit) with `days/` and `months/` subfolders. Verifies `goaccess` is on `PATH` and the source directory exists. Computes `DAY_CUTOFF` from `--days` (empty if `--no-days`, `0000-00-00` sentinel meaning "all days" if `--days 0`, otherwise an actual date via `date -d`).

### Step 2 – Detect IP anonymization support
Checks `goaccess --help` for `--anonymize-ip` and appends it to `GA_OPTS` if present, printing which mode is active.

### Step 3 – Discover and group log files by domain
Walks `SRC_DIR` recursively. Skips WSL `Zone.Identifier` NTFS-stream artifacts and dotfiles, skips non-web cPanel logs (`ftp_log`, `imap_log`, `pop3_log`, `smtp_log`), and — unless `--live` — skips any file whose name doesn't end in `-Mmm-YYYY[.gz]`. When both an uncompressed file and its `.gz` counterpart exist, only the `.gz` is kept (counted as a skipped duplicate) so traffic isn't double-counted. Each remaining file's domain is derived via `domain_of()`: strip the date suffix and a trailing `-ssl_log`, strip any configured account suffix, then apply `ALIAS`. Files are grouped into `LOGGROUPS[domain]`.

### Step 4 – Per-domain report build
For each domain: concatenates its log files (decompressing `.gz` via `zcat`), filters out lines matching the `NOISE` regex, and writes a clean combined log. Builds the all-time GoAccess HTML report for that domain. Appends the domain's clean lines (prefixed with the domain label) into a global `COMBINED` log for the later "all domains" report. Splits the clean log into per-month and per-day temp log files in a single `awk` pass over the Combined Log Format date field (closing file handles as the date changes to stay under awk's open-file limit across years of history). Builds a monthly GoAccess report for every month present. If `DAY_CUTOFF` is set, builds a daily GoAccess report for every day on/after the cutoff (string comparison works because dates are ISO-formatted `YYYY-MM-DD`).

### Step 5 – Combined all-time report
If any data was collected, builds `_alle.html`: a single GoAccess report over all domains' combined log, using a custom log format (`%v %h ...`) that includes the vhost so GoAccess renders a per-vhost panel.

### Step 6 – Generate `index.html`
Writes a static HTML landing page (dark-cream, serif styling, Cormorant Garamond via Google Fonts) with three tables: **All time** (one row per domain plus "All domains", each linking to its report and showing entry counts), **By month** (every domain/month combination, newest first), and **By day** (every domain/day combination within the window, newest first, with a note about the window size unless `--days 0` was used). Titled for "Dragic.com" and marked `noindex, nofollow`.

---

## Notes

- **Idempotent/safe to re-run:** the script only reads from `SRC_DIR` and writes into `OUT_DIR`/a temp dir; it never modifies or deletes source logs. Re-running fully regenerates all reports each time.
- **Whitelist-based file matching is deliberate:** without `--live`, any file not matching the dated cPanel naming convention is silently ignored, which is what lets the script run safely against a source directory that also contains scripts, a `README`, etc.
- **Hardcoded to this deployment:** `STRIP_SUFFIXES`, `ALIAS`, `PRETTY`, the `NOISE` filter list, and the `index.html` branding/footer (title "Dragic.com", copyright "Nenad Ahlström Dragic") are all specific to this site and need editing for reuse elsewhere.
- **Performance:** rebuilding from scratch over multi-year raw logs is the expensive part of the whole pipeline — see [sync-logs.sh](sync-logs.md), which only invokes this script when new/changed data is actually detected.
- Depends on GNU-specific `date -d` and `find`/`awk` behavior; not portable to BSD/macOS without changes.
- Console output and comments in the script are in Danish; this document is in English. The generated `index.html` itself is in English.
