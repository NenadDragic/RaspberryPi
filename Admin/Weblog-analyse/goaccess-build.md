# goaccess-build.sh

Installs or updates GoAccess by building it from source, since Debian's packaged version typically lags several releases behind and the gap isn't cosmetic (newer releases add zlib support for reading `.gz` logs directly and cut memory/parse time significantly).

---

## Usage

```console
chmod +x goaccess-build.sh
./goaccess-build.sh              # build the newest release if it's newer than what's installed
./goaccess-build.sh --check      # only print installed vs. latest version, build nothing
./goaccess-build.sh --version 1.11
./goaccess-build.sh --force      # rebuild even if the target version is already installed
./goaccess-build.sh --skip-deps  # skip the apt dependency install step
```

Builds to `/usr/local` and requires `sudo` for `apt-get` and `make install`.

Prerequisites:

- `curl`, `wget`, `tar`, `gzip`, `make` — the apt dependency step (unless `--skip-deps`) installs `build-essential`, `pkg-config`, `gettext`, `ca-certificates`, `curl`, `wget`, an ncurses dev package, `libmaxminddb-dev`, `libssl-dev`, `zlib1g-dev`, `libbz2-dev`.
- Passwordless or interactive `sudo` access, for the apt install and `make install` steps.
- Network access to `api.github.com` (version lookup) and `tar.goaccess.io` (source tarball).

### Configuration (top of script)

| Variable | Default | Meaning |
|---|---|---|
| `FALLBACK_VERSION` | `1.11` | Version built if the GitHub version lookup fails |
| `SRC_ROOT` | `$HOME/src` (env override) | Where source tarballs are downloaded and extracted |
| `PREFIX` | `/usr/local` (env override) | `./configure --prefix` target |

---

## What the Script Does

### Step 1 – Parse arguments
Supports `--version <ver>`/`--version=<ver>`, `--check`, `--force`, `--skip-deps`, `-h`/`--help` (prints the header comment block via `sed`).

### Step 2 – Determine installed and target versions
Reads the installed version via `goaccess --version` (if present). Determines the target version: an explicit `--version` wins; otherwise it queries GitHub's tags API (`api.github.com/repos/allinurl/goaccess/tags`) for the newest tag; if that call fails or returns nothing parseable, it falls back to `FALLBACK_VERSION`. Prints installed vs. target version and the source of the target (manual/GitHub/fallback).

### Step 3 – Early exit paths
With `--check`, exits after printing the version comparison — nothing is built. Otherwise, if the installed version already equals the target and `--force` wasn't given, it prints a message and exits without building.

### Step 4 – Install build dependencies
Unless `--skip-deps`, runs `apt-get update` and installs the toolchain and library packages listed above. Detects whether `libncurses-dev` exists as a package name and falls back to `libncursesw5-dev` on older Debian releases where they weren't merged.

### Step 5 – Download and verify the source tarball
Downloads `https://tar.goaccess.io/goaccess-<version>.tar.gz` into `SRC_ROOT` (skips the download if the tarball is already present), downloading to a `.part` file first and renaming it on success. Runs `gzip -t` on the tarball before extracting — an incomplete download otherwise produces a confusing failure deep inside the build instead of a clear error here.

### Step 6 – Extract
Removes any pre-existing `SRC_ROOT/goaccess-<version>` directory, extracts the tarball, and verifies the expected directory now exists.

### Step 7 – Configure, build, install
Runs `./configure --prefix=<PREFIX> --enable-utf8 --enable-geoip=mmdb --with-openssl`, then `make -j$(nproc)`, then `sudo make install` and `sudo ldconfig`.

### Step 8 – Verify the installed binary
Clears bash's command hash cache (`hash -r`) and re-checks `goaccess --version`. If the reported version doesn't match the target, prints a warning that an apt-installed binary in `/usr/bin` may be shadowing the freshly built one in `/usr/local/bin`, with the `type -a goaccess` / `sudo apt remove goaccess` fix, and exits `1`. Otherwise prints the build's version banner.

---

## Notes

- **Idempotent-ish:** re-running with the same target version is a no-op unless `--force` is passed; downloaded tarballs are cached in `SRC_ROOT` and reused across runs.
- **Network dependency with a safety net:** the GitHub API call is unauthenticated and therefore rate-limited; a failed lookup doesn't stop the script, it silently falls back to `FALLBACK_VERSION`, which can go stale over time and needs occasional manual bumping in the script.
- **Common trap documented in the script itself:** after installation, `goaccess --version` may still report the old version because an apt-installed binary on `PATH` before `/usr/local/bin` shadows the new build. The script detects and explains this rather than silently succeeding.
- Requires `sudo`; not designed to run fully unattended without passwordless sudo configured for `apt-get` and `make install`.
- All console output and comments in the script are in Danish; this document is in English.
