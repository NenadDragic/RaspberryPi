# archive-logs.sh

Lays an unoverwritable archive layer over the raw logs, so that a corrupted or truncated remote replacement of a log file can never silently overwrite the local copy — the previous version is preserved instead.

---

## Usage

```console
chmod +x archive-logs.sh
./archive-logs.sh            # archive new and changed files
./archive-logs.sh --verify   # archive, then test every .gz in the archive
./archive-logs.sh --status   # show counts only, touch nothing
```

Prerequisites:

- `rsync` installed.
- Same config file as the other scripts at `~/.config/logfetch/config` (optional — sourced if present).

### Configuration (via `~/.config/logfetch/config`, all optional)

| Variable | Default | Meaning |
|---|---|---|
| `LOCAL_DIR` | `$HOME/weblogs/raw` | Source of raw logs (read as `RAW_DIR`) |
| `ARCHIVE_DIR` | `<parent of RAW_DIR>/archive` | The unoverwritable archive copy |
| `ATTIC_DIR` | `<parent of RAW_DIR>/attic` | Where files being overwritten get moved, under a per-day subfolder |

### Flags

| Flag | Meaning |
|---|---|
| `--verify` | After archiving, `gzip -t` every `.gz` file in the archive to check for CRC errors |
| `--status` | Only print counts for source/archive/attic; performs no archiving |

---

## What the Script Does

### Why (from the script's own header)
`fetch-logs.sh` runs `lftp mirror` with clobber enabled and compares on timestamp, not content. If the hosting provider ever replaces a log file with a truncated or empty one under the same name and a newer timestamp, `mirror` will overwrite the complete local copy with the worthless one — the file isn't deleted, it just silently becomes useless, which is harder to notice than a deletion.

### Step 1 – `--status` short-circuit
Prints `.gz` file counts for `RAW_DIR` and `ARCHIVE_DIR`, and whether `ATTIC_DIR` contains anything (non-empty attic means something has already been overwritten at some point), then exits without touching anything.

### Step 2 – Archive
Verifies `RAW_DIR` exists and `rsync` is installed, creates `ARCHIVE_DIR` if needed, then runs `rsync -a --backup --backup-dir="$ATTIC_DIR/<today's date>" "$RAW_DIR/" "$ARCHIVE_DIR/"`. `--backup` means any file in the archive that's about to be overwritten by a newer/changed source file is moved to today's dated folder under `ATTIC_DIR` first, rather than being overwritten in place. There is deliberately no `--delete`: if a file disappears from the source, the archive's copy stays — that's the entire point of the archive. Prints the resulting status.

### Step 3 – Optional verification
With `--verify`, runs `gzip -t` over every `.gz` file in `ARCHIVE_DIR` (via `find ... -print0 | xargs -0 -r -n1`, where `-r` matters: without it, `xargs` still runs `gzip -t` once with no argument when `find` matched nothing, and the resulting "unexpected end of file" from reading stdin looks like a corrupt file when the directory was actually just empty). Reports any corrupt files and exits `1` if any are found — noting that the corresponding file in `attic/` may still be intact.

---

## Notes

- **Non-destructive by design:** the whole point of this script is that nothing already in `ARCHIVE_DIR`/`ATTIC_DIR` is ever deleted or silently overwritten — `attic/` only ever accumulates.
- **`attic/` should never be auto-cleaned** (per the guide's own advice) — an empty `attic/` is a positive signal that nothing has been overwritten; a non-empty one is something to actually go look at, and the full prior version is sitting right there.
- **Idempotent/safe to re-run:** running it again with no changes since the last run does nothing (rsync only transfers deltas).
- Depends on GNU `find`/`xargs` (`-print0`/`-0`, `-r`).
- Console output and comments in the script are in Danish; this document is in English.
