#!/usr/bin/env bash
#
# goaccess-build.sh -- installerer eller opdaterer GoAccess fra kildekode.
#
# Brug:
#   ./goaccess-build.sh              # byg nyeste udgave hvis der er en nyere
#   ./goaccess-build.sh --check      # vis kun versioner, byg ikke
#   ./goaccess-build.sh --version 1.11
#   ./goaccess-build.sh --force      # byg igen selv om versionen er den samme
#   ./goaccess-build.sh --skip-deps  # spring apt-installationen over
#
# Bygger til /usr/local. Kraever sudo til apt og "make install".
#
set -euo pipefail

FALLBACK_VERSION="1.11"     # bruges hvis versionsopslaget fejler
SRC_ROOT="${SRC_ROOT:-$HOME/src}"
PREFIX="${PREFIX:-/usr/local}"

WANT_VERSION=""
CHECK_ONLY="no"
FORCE="no"
SKIP_DEPS="no"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)  WANT_VERSION="${2:?--version kraever et versionsnummer}"; shift 2 ;;
    --version=*) WANT_VERSION="${1#*=}"; shift ;;
    --check)    CHECK_ONLY="yes"; shift ;;
    --force)    FORCE="yes"; shift ;;
    --skip-deps) SKIP_DEPS="yes"; shift ;;
    -h|--help)  sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "Ukendt flag: $1" >&2; exit 1 ;;
  esac
done

say() { printf '\n\033[1m== %s\033[0m\n' "$*"; }

# ------------------------------------------------------- nuvaerende version

installed_version() {
  command -v goaccess >/dev/null || return 1
  goaccess --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1
}

CURRENT="$(installed_version || true)"
CURRENT_PATH="$(command -v goaccess 2>/dev/null || echo '(ikke installeret)')"

# ------------------------------------------------------- nyeste version

latest_version() {
  local json v
  # GitHubs API er uautentificeret rate-limited. Slaar det fejl,
  # falder vi tilbage paa den indbyggede version frem for at stoppe.
  json="$(curl -fsSL --max-time 15 \
    https://api.github.com/repos/allinurl/goaccess/tags 2>/dev/null || true)"
  v="$(printf '%s' "$json" \
       | grep -oE '"name"[[:space:]]*:[[:space:]]*"v?[0-9]+\.[0-9]+(\.[0-9]+)?"' \
       | head -1 \
       | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' || true)"
  [[ -n "$v" ]] && { echo "$v"; return 0; }
  return 1
}

if [[ -n "$WANT_VERSION" ]]; then
  TARGET="$WANT_VERSION"
  SOURCE_OF_TRUTH="angivet manuelt"
elif TARGET="$(latest_version)"; then
  SOURCE_OF_TRUTH="GitHub"
else
  TARGET="$FALLBACK_VERSION"
  SOURCE_OF_TRUTH="fallback (versionsopslag fejlede)"
fi

say "Versioner"
echo "  Installeret : ${CURRENT:-ingen}  ($CURRENT_PATH)"
echo "  Maal        : $TARGET  [$SOURCE_OF_TRUTH]"

if [[ "$CHECK_ONLY" == "yes" ]]; then
  exit 0
fi

if [[ "$CURRENT" == "$TARGET" && "$FORCE" != "yes" ]]; then
  echo
  echo "Allerede paa $TARGET. Brug --force for at bygge igen."
  exit 0
fi

# ------------------------------------------------------- afhaengigheder

if [[ "$SKIP_DEPS" != "yes" ]]; then
  say "Installerer byggeafhaengigheder"

  # libncursesw5-dev er slaaet sammen til libncurses-dev i nyere Debian.
  NCURSES="libncurses-dev"
  apt-cache show libncurses-dev >/dev/null 2>&1 || NCURSES="libncursesw5-dev"

  sudo apt-get update -qq
  sudo apt-get install -y --no-install-recommends \
    build-essential pkg-config gettext ca-certificates curl wget \
    "$NCURSES" \
    libmaxminddb-dev \
    libssl-dev \
    zlib1g-dev \
    libbz2-dev
fi

# ------------------------------------------------------- hent og pak ud

TARBALL="goaccess-${TARGET}.tar.gz"
URL="https://tar.goaccess.io/${TARBALL}"
SRC_DIR="${SRC_ROOT}/goaccess-${TARGET}"

mkdir -p "$SRC_ROOT"
cd "$SRC_ROOT"

if [[ ! -f "$TARBALL" ]]; then
  say "Henter $URL"
  curl -fSL --retry 3 -o "${TARBALL}.part" "$URL"
  mv "${TARBALL}.part" "$TARBALL"
else
  echo "  Arkiv findes allerede: $TARBALL"
fi

# Integritetstjek foer udpakning -- en halvt hentet tarball giver
# ellers en forvirrende fejl langt inde i byggeprocessen.
if ! gzip -t "$TARBALL" 2>/dev/null; then
  echo "FEJL: $TARBALL er defekt. Slet den og proev igen." >&2
  exit 1
fi

say "Pakker ud"
rm -rf "$SRC_DIR"
tar -xzf "$TARBALL"
[[ -d "$SRC_DIR" ]] || { echo "FEJL: forventede mappen $SRC_DIR" >&2; exit 1; }

# ------------------------------------------------------- byg

say "Konfigurerer"
cd "$SRC_DIR"

# --enable-geoip=mmdb kraever libmaxminddb og giver GeoIP2-understoettelse.
# --with-openssl er noedvendig for TLS paa realtidsrapporter.
# zlib findes automatisk og lader GoAccess laese .gz-logs direkte.
./configure \
  --prefix="$PREFIX" \
  --enable-utf8 \
  --enable-geoip=mmdb \
  --with-openssl

say "Bygger"
make -j"$(nproc)"

say "Installerer til $PREFIX"
sudo make install
sudo ldconfig || true

# ------------------------------------------------------- verifikation

hash -r 2>/dev/null || true

NEW="$(installed_version || true)"
NEW_PATH="$(command -v goaccess 2>/dev/null || echo '?')"

say "Resultat"
echo "  goaccess $NEW  ($NEW_PATH)"

if [[ "$NEW" != "$TARGET" ]]; then
  echo
  echo "ADVARSEL: der koeres stadig $NEW, ikke $TARGET." >&2
  echo "En version fra apt i /usr/bin kan skygge for den nybyggede." >&2
  echo "Tjek med:  type -a goaccess" >&2
  echo "Loesning:  sudo apt remove goaccess   (og aabn en ny shell)" >&2
  exit 1
fi

echo
echo "Bygget med:"
goaccess --version | sed -n '2,6p' | sed 's/^/  /'
