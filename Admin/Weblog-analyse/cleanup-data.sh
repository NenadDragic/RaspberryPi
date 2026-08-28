#!/usr/bin/env bash
#
# cleanup-data.sh -- rydder op i genererede data og hentede filer.
#
# Brug:
#   ./cleanup-data.sh              # toerloeb: viser hvad der ville ske
#   ./cleanup-data.sh --yes        # udfoer oprydningen
#   ./cleanup-data.sh --all --yes  # medtag ogsaa raa logs (se advarsel)
#
# Uden --yes slettes intet. Det er med vilje: scriptet roerer ved
# mapper, hvor et fejltryk koster historik der ikke kan hentes igen.
#
set -euo pipefail

CONFIG="${HOME}/.config/logfetch/config"
[[ -f "$CONFIG" ]] && { set +u; source "$CONFIG"; set -u; }

# ---------------------------------------------------------------- stier

RAW_DIR="${LOCAL_DIR:-$HOME/weblogs/raw}"
LIVE_DIR="${LIVE_LOCAL_DIR:-$HOME/weblogs/live}"
REPORTS_DIR="${REPORTS_DIR:-$HOME/weblogs/reports}"
DB_DIR="${GOACCESS_DB_DIR:-$HOME/weblogs/db}"
SRC_ROOT="${SRC_ROOT:-$HOME/src}"

# ---------------------------------------------------------------- politik
#
# 0 betyder "behold alt". Raa logs staar bevidst paa 0, fordi de er
# den eneste kopi af historikken naar de er slettet hos udbyderen.

REPORTS_RETENTION_DAYS="${REPORTS_RETENTION_DAYS:-0}"
LIVE_RETENTION_DAYS="${LIVE_RETENTION_DAYS:-7}"
RAW_RETENTION_MONTHS="${RAW_RETENTION_MONTHS:-0}"
KEEP_SOURCE_BUILDS="${KEEP_SOURCE_BUILDS:-1}"

DO_IT="no"
INCLUDE_RAW="no"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes|-y) DO_IT="yes"; shift ;;
    --all)    INCLUDE_RAW="yes"; shift ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "Ukendt flag: $1" >&2; exit 1 ;;
  esac
done

TOTAL_FILES=0
TOTAL_BYTES=0

human() {
  local b="$1"
  if   [[ "$b" -gt 1073741824 ]]; then printf '%.1f GB' "$(echo "$b/1073741824" | bc -l)"
  elif [[ "$b" -gt 1048576 ]];    then printf '%.1f MB' "$(echo "$b/1048576" | bc -l)"
  elif [[ "$b" -gt 1024 ]];       then printf '%.1f KB' "$(echo "$b/1024" | bc -l)"
  else printf '%s B' "$b"; fi
}

# Faelles rutine: find filer efter kriterium, vis dem, slet ved --yes.
purge() {
  local label="$1" dir="$2"; shift 2
  local files n bytes

  [[ -d "$dir" ]] || { printf '  %-28s %s\n' "$label" "(mappen findes ikke)"; return 0; }

  files="$(find "$dir" "$@" -type f -print0 2>/dev/null | tr '\0' '\n' | sed '/^$/d')"

  if [[ -z "$files" ]]; then
    printf '  %-28s intet at rydde\n' "$label"
    return 0
  fi

  n="$(printf '%s\n' "$files" | wc -l)"
  bytes="$(printf '%s\n' "$files" | tr '\n' '\0' | xargs -0 stat -c '%s' 2>/dev/null | paste -sd+ | bc)"
  bytes="${bytes:-0}"

  TOTAL_FILES=$((TOTAL_FILES + n))
  TOTAL_BYTES=$((TOTAL_BYTES + bytes))

  printf '  %-28s %s fil(er), %s\n' "$label" "$n" "$(human "$bytes")"

  if [[ "$DO_IT" == "yes" ]]; then
    printf '%s\n' "$files" | tr '\n' '\0' | xargs -0 rm -f
  fi
}

echo "Oprydning $( [[ "$DO_IT" == "yes" ]] && echo '(udfoerer)' || echo '(toerloeb)' )"
echo

# ---------------------------------------------------------------- rapporter
#
# Rapporter genopbygges fra raa logs ved hver koersel, saa de kan
# altid slettes uden tab.

echo "Genererede rapporter"
if [[ "$REPORTS_RETENTION_DAYS" -gt 0 ]]; then
  purge "aeldre end ${REPORTS_RETENTION_DAYS}d" "$REPORTS_DIR" -mtime "+${REPORTS_RETENTION_DAYS}"
else
  purge "alle (genopbygges)" "$REPORTS_DIR"
fi

# ---------------------------------------------------------------- database

echo
echo "GoAccess persist-database"
purge "alle" "$DB_DIR"

# ---------------------------------------------------------------- live-logs
#
# Live-logs roteres af cPanel og duer ikke som historik.

echo
echo "Live-logs"
if [[ "$LIVE_RETENTION_DAYS" -gt 0 ]]; then
  purge "aeldre end ${LIVE_RETENTION_DAYS}d" "$LIVE_DIR" -mtime "+${LIVE_RETENTION_DAYS}"
else
  purge "alle" "$LIVE_DIR"
fi

# ---------------------------------------------------------------- kildekode

echo
echo "GoAccess-kildetraeer i $SRC_ROOT"
if [[ -d "$SRC_ROOT" ]]; then
  mapfile -t BUILDS < <(find "$SRC_ROOT" -maxdepth 1 -type d -name 'goaccess-*' | sort -V -r)
  if [[ ${#BUILDS[@]} -le "$KEEP_SOURCE_BUILDS" ]]; then
    printf '  %-28s intet at rydde (%s beholdes)\n' "gamle builds" "$KEEP_SOURCE_BUILDS"
  else
    for d in "${BUILDS[@]:$KEEP_SOURCE_BUILDS}"; do
      sz="$(du -sb "$d" 2>/dev/null | cut -f1)"
      TOTAL_BYTES=$((TOTAL_BYTES + ${sz:-0}))
      printf '  %-28s %s\n' "$(basename "$d")" "$(human "${sz:-0}")"
      [[ "$DO_IT" == "yes" ]] && rm -rf "$d"
    done
  fi
else
  printf '  %-28s (mappen findes ikke)\n' "gamle builds"
fi

# ---------------------------------------------------------------- raa logs

echo
echo "Raa logs (historikken)"
if [[ "$INCLUDE_RAW" != "yes" ]]; then
  echo "  Roeres ikke. Brug --all hvis du bevidst vil slette historik."
elif [[ "$RAW_RETENTION_MONTHS" -le 0 ]]; then
  echo "  RAW_RETENTION_MONTHS=0 -- beholder alt. Saet den i konfigurationen"
  echo "  hvis du faktisk vil have en udloebsgraense."
else
  CUTOFF_DAYS=$((RAW_RETENTION_MONTHS * 31))
  echo "  ADVARSEL: naar logs er slettet hos udbyderen, er $RAW_DIR"
  echo "            den eneste kopi. Sletning her er permanent."
  purge "aeldre end ${RAW_RETENTION_MONTHS} mdr" "$RAW_DIR" -mtime "+${CUTOFF_DAYS}"
fi

# ---------------------------------------------------------------- opsummering

echo
if [[ "$DO_IT" == "yes" ]]; then
  echo "Slettet: $TOTAL_FILES fil(er), $(human "$TOTAL_BYTES") frigjort."
else
  echo "Ville slette: $TOTAL_FILES fil(er), $(human "$TOTAL_BYTES")."
  echo "Koer med --yes for at udfoere det."
fi
