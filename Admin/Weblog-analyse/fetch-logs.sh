#!/usr/bin/env bash
#
# fetch-logs.sh -- henter raa cPanel-weblogs hjem via FTP(S),
# verificerer integriteten og sletter dem valgfrit paa serveren.
#
# Brug:  ./fetch-logs.sh [--dry-run]
#
set -euo pipefail

CONFIG="${HOME}/.config/logfetch/config"
DRY_RUN="no"
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN="yes"

# ---------------------------------------------------------------- opsaetning

if [[ ! -f "$CONFIG" ]]; then
  echo "FEJL: mangler konfigurationsfil: $CONFIG" >&2
  echo "Kopier logfetch.conf.example dertil og udfyld den." >&2
  exit 1
fi

# Advar hvis adgangskoden ligger laesbart for andre brugere.
PERMS="$(stat -c '%a' "$CONFIG")"
if [[ "$PERMS" != "600" ]]; then
  echo "ADVARSEL: $CONFIG har rettigheder $PERMS -- boer vaere 600." >&2
  echo "          Koer:  chmod 600 $CONFIG" >&2
fi

# shellcheck source=/dev/null
source "$CONFIG"

: "${FTP_HOST:?mangler i config}"
: "${FTP_USER:?mangler i config}"
: "${FTP_PASS:?mangler i config}"
REMOTE_DIR="${REMOTE_DIR:-logs}"
LOCAL_DIR="${LOCAL_DIR:-$HOME/weblogs/raw}"
DELETE_REMOTE="${DELETE_REMOTE:-no}"
USE_FTPS="${USE_FTPS:-yes}"
FETCH_LIVE="${FETCH_LIVE:-no}"
LIVE_REMOTE_DIR="${LIVE_REMOTE_DIR:-access-logs}"
LIVE_LOCAL_DIR="${LIVE_LOCAL_DIR:-$HOME/weblogs/live}"

# Kun arkiverede logs hentes. Uden filteret traekker mirror hele
# FTP-kontoens rod ned, hvis kontoen ikke er chrootet til logmappen.
REMOTE_GLOB="${REMOTE_GLOB:-*.gz}"

# Adgangskoden sendes til lftp via miljoeet, ikke som kommandolinje-
# argument: ellers staar den laesbart i 'ps' for enhver anden bruger
# paa maskinen, saa laenge overfoerslen koerer.
export LFTP_PASSWORD="$FTP_PASS"

# --- Dependency check ---
_d="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
while [ "$_d" != "/" ] && [ ! -f "$_d/lib/require_tools.sh" ]; do _d="$(dirname "$_d")"; done
if [ ! -f "$_d/lib/require_tools.sh" ]; then
    echo "FEJL: Kunne ikke finde lib/require_tools.sh (delt dependency-checker)." >&2
    exit 1
fi
# shellcheck source=/dev/null
source "$_d/lib/require_tools.sh"
unset _d
require_tools lftp

mkdir -p "$LOCAL_DIR"

# Indevaerende maaned i C-locale, saa vi faar "Aug" og ikke dansk "aug".
CURRENT_MONTH="-$(LC_ALL=C date +%b)-$(date +%Y)"

echo "== Henter fra ${FTP_HOST}:${REMOTE_DIR} -> ${LOCAL_DIR}"
echo "   Indevaerende maaned (fredes): *${CURRENT_MONTH}*"
echo

# ---------------------------------------------------------------- download

LFTP_SETTINGS="
set ftp:ssl-force $( [[ "$USE_FTPS" == "yes" ]] && echo true || echo false );
set ftp:ssl-protect-data true;
set ssl:verify-certificate no;
set ftp:passive-mode true;
set net:max-retries 3;
set net:timeout 20;
set xfer:clobber on;
"

lftp -u "$FTP_USER" --env-password "$FTP_HOST" <<EOF
$LFTP_SETTINGS
mirror --only-newer --no-perms --verbose=1 --include-glob "$REMOTE_GLOB" "$REMOTE_DIR" "$LOCAL_DIR"
bye
EOF

if [[ "$FETCH_LIVE" == "yes" ]]; then
  echo
  echo "== Henter levende logs fra ${LIVE_REMOTE_DIR} -> ${LIVE_LOCAL_DIR}"
  echo "   (indevaerende dags trafik; roteres ved natlig statistikkoersel)"
  mkdir -p "$LIVE_LOCAL_DIR"

  # Bemaerk: --only-newer bruges IKKE her. Live-logs vokser i loebet af
  # dagen, saa filen skal hentes i sin helhed hver gang.
  lftp -u "$FTP_USER" --env-password "$FTP_HOST" <<EOF || \
    echo "   (kunne ikke hente live-logs -- findes mappen '$LIVE_REMOTE_DIR'?)" >&2
$LFTP_SETTINGS
mirror --no-perms --verbose=1 "$LIVE_REMOTE_DIR" "$LIVE_LOCAL_DIR"
bye
EOF
fi

echo
echo "== Verificerer hentede filer"

# ---------------------------------------------------------------- verifikation

VERIFIED=()
FAILED=0

while IFS= read -r -d '' f; do
  base="$(basename "$f")"

  # Tomme filer er mislykkede overfoersler.
  if [[ ! -s "$f" ]]; then
    echo "  SPRING OVER (tom): $base"
    FAILED=$((FAILED + 1))
    continue
  fi

  # Gzip-filer testes for korrekt CRC.
  if [[ "$base" == *.gz ]]; then
    if ! gzip -t "$f" 2>/dev/null; then
      echo "  FEJL (defekt gzip): $base"
      FAILED=$((FAILED + 1))
      continue
    fi
  fi

  echo "  OK: $base"
  VERIFIED+=("$base")
done < <(find "$LOCAL_DIR" -maxdepth 1 -type f -print0)

echo
echo "Verificeret: ${#VERIFIED[@]} fil(er). Fejlet: $FAILED."

# ---------------------------------------------------------------- oprydning

if [[ "$DELETE_REMOTE" != "yes" ]]; then
  echo
  echo "DELETE_REMOTE=no -- der slettes intet paa serveren."
  exit 0
fi

if [[ $FAILED -gt 0 ]]; then
  echo
  echo "Der var fejl under verifikationen. Sletter intet paa serveren." >&2
  exit 1
fi

# Byg sletteliste: kun verificerede filer, aldrig indevaerende maaned.
DELETE_LIST=()
for base in "${VERIFIED[@]}"; do
  if [[ "$base" == *"$CURRENT_MONTH"* ]]; then
    echo "  Fredes (indevaerende maaned): $base"
    continue
  fi
  DELETE_LIST+=("$base")
done

if [[ ${#DELETE_LIST[@]} -eq 0 ]]; then
  echo
  echo "Ingen filer at slette."
  exit 0
fi

echo
echo "Foelgende ${#DELETE_LIST[@]} fil(er) slettes paa serveren:"
printf '  %s\n' "${DELETE_LIST[@]}"
echo
echo "BEMAERK: efter sletning er $LOCAL_DIR den eneste kopi af"
echo "         disse logs. Sikkerhedskopier mappen."

if [[ "$DRY_RUN" == "yes" ]]; then
  echo
  echo "--dry-run: sletter ikke noget."
  exit 0
fi

echo
read -r -p "Fortsaet? (skriv JA): " CONFIRM
if [[ "$CONFIRM" != "JA" ]]; then
  echo "Afbrudt."
  exit 0
fi

{
  echo "$LFTP_SETTINGS"
  echo "cd \"$REMOTE_DIR\";"
  for base in "${DELETE_LIST[@]}"; do
    echo "rm -f \"$base\";"
  done
  echo "bye"
} | lftp -u "$FTP_USER" --env-password "$FTP_HOST"

echo "Slettet paa serveren."
