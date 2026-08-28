#!/usr/bin/env bash
#
# sync-logs.sh -- henter logs hjem og behandler kun nye data.
#
# Brug:
#   ./sync-logs.sh                 # hent + byg hvis noget er nyt
#   ./sync-logs.sh --force         # byg uanset om der er nyt
#   ./sync-logs.sh --no-fetch      # spring hentningen over, byg lokalt
#   ./sync-logs.sh --days 90       # videresendes til build-reports.sh
#
# Ideen: hentningen koerer altid, men GoAccess-koerslen springes over,
# hvis intet er aendret. Med flere aars arkiv er genopbygningen den dyre
# del, og der er ingen grund til at lave den om paa uaendrede data.
#
set -euo pipefail

BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${HOME}/.config/logfetch/config"
[[ -f "$CONFIG" ]] && { set +u; source "$CONFIG"; set -u; }

RAW_DIR="${LOCAL_DIR:-$HOME/weblogs/raw}"
REPORTS_DIR="${REPORTS_DIR:-$HOME/weblogs/reports}"
STATE_DIR="${STATE_DIR:-$HOME/weblogs/.state}"
MANIFEST="$STATE_DIR/manifest.txt"

DO_FETCH="yes"
FORCE="no"
BUILD_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)    FORCE="yes"; shift ;;
    --no-fetch) DO_FETCH="no"; shift ;;
    -h|--help)  sed -n '2,14p' "$0"; exit 0 ;;
    *)          BUILD_ARGS+=("$1"); shift ;;
  esac
done

mkdir -p "$STATE_DIR" "$RAW_DIR"

stamp() { date '+%Y-%m-%d %H:%M:%S'; }
say()   { printf '[%s] %s\n' "$(stamp)" "$*"; }

# ---------------------------------------------------------------- hentning

if [[ "$DO_FETCH" == "yes" ]]; then
  if [[ -x "$BIN_DIR/fetch-logs.sh" ]]; then
    say "Henter logs"
    "$BIN_DIR/fetch-logs.sh"
  else
    echo "FEJL: $BIN_DIR/fetch-logs.sh findes ikke eller er ikke koerbar." >&2
    exit 1
  fi
else
  say "Springer hentning over (--no-fetch)"
fi

# ---------------------------------------------------------------- aendringer
#
# Manifestet er navn + stoerrelse + aendringstid. Det fanger baade nye
# filer og indevaerende maaneds arkiv, der vokser for hver natlige
# statistikkoersel hos udbyderen.

NEW_MANIFEST="$STATE_DIR/manifest.new"
find "$RAW_DIR" -type f -printf '%P|%s|%T@\n' 2>/dev/null | sort > "$NEW_MANIFEST"

if [[ ! -f "$MANIFEST" ]]; then
  say "Intet tidligere manifest -- foerste koersel."
  CHANGED="yes"
  ADDED="$(wc -l < "$NEW_MANIFEST")"
  MODIFIED=0
else
  # Nye filer: findes i det nye manifest, men navnet var der ikke foer.
  ADDED="$(comm -13 <(cut -d'|' -f1 "$MANIFEST" | sort) \
                    <(cut -d'|' -f1 "$NEW_MANIFEST" | sort) | wc -l)"
  # Aendrede: samme navn, men anden stoerrelse eller tidsstempel.
  MODIFIED="$(comm -13 <(sort "$MANIFEST") <(sort "$NEW_MANIFEST") \
              | cut -d'|' -f1 \
              | grep -Fxf <(cut -d'|' -f1 "$MANIFEST") 2>/dev/null | wc -l || true)"

  if [[ "$ADDED" -gt 0 || "$MODIFIED" -gt 0 ]]; then
    CHANGED="yes"
  else
    CHANGED="no"
  fi
fi

say "Nye filer: $ADDED   Aendrede: $MODIFIED"

if [[ "$CHANGED" != "yes" && "$FORCE" != "yes" ]]; then
  say "Ingen aendringer -- springer genopbygning over. Brug --force for at tvinge."
  rm -f "$NEW_MANIFEST"
  exit 0
fi

# ---------------------------------------------------------------- byg

if [[ ! -x "$BIN_DIR/build-reports.sh" ]]; then
  echo "FEJL: $BIN_DIR/build-reports.sh findes ikke eller er ikke koerbar." >&2
  exit 1
fi

say "Bygger rapporter"

# Manifestet opdateres foerst naar byggeriet er lykkedes. Fejler det,
# forsoeges de samme data igen ved naeste koersel.
if "$BIN_DIR/build-reports.sh" "${BUILD_ARGS[@]+"${BUILD_ARGS[@]}"}" "$RAW_DIR" "$REPORTS_DIR"; then
  mv "$NEW_MANIFEST" "$MANIFEST"
  say "Faerdig. Oversigt: $REPORTS_DIR/index.html"
else
  rc=$?
  rm -f "$NEW_MANIFEST"
  say "Byggeriet fejlede (kode $rc) -- manifestet er ikke opdateret."
  exit "$rc"
fi
