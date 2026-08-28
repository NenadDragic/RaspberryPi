#!/usr/bin/env bash
#
# archive-logs.sh -- lægger et lag over de raa logs, som ikke kan
# overskrives af en senere hentning.
#
# Brug:
#   ./archive-logs.sh            # arkivér nye og aendrede filer
#   ./archive-logs.sh --verify   # arkivér, og test derefter alle .gz
#   ./archive-logs.sh --status   # vis kun taellinger, roer intet
#
# Hvorfor: fetch-logs.sh koerer med "clobber on" og sammenligner paa
# tidsstempel. Bliver en fil hos udbyderen erstattet af en afkortet
# udgave med samme navn og nyere dato, skriver mirror hen over den
# komplette lokale kopi. Filen slettes ikke -- den bliver vaerdiloes,
# hvilket er lige saa slemt og svaerere at opdage.
#
# Her flyttes enhver udgave, der er ved at blive erstattet, foerst til
# attic/ under dagens dato. Der gaar aldrig bytes tabt.
#
set -euo pipefail

CONFIG="${HOME}/.config/logfetch/config"
[[ -f "$CONFIG" ]] && { set +u; source "$CONFIG"; set -u; }

RAW_DIR="${LOCAL_DIR:-$HOME/weblogs/raw}"
BASE="$(dirname "$RAW_DIR")"
ARCHIVE_DIR="${ARCHIVE_DIR:-$BASE/archive}"
ATTIC_DIR="${ATTIC_DIR:-$BASE/attic}"

VERIFY="no"
STATUS_ONLY="no"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --verify)  VERIFY="yes"; shift ;;
    --status)  STATUS_ONLY="yes"; shift ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "Ukendt flag: $1" >&2; exit 1 ;;
  esac
done

count_gz() { find "$1" -type f -name '*.gz' 2>/dev/null | wc -l; }

status() {
  printf '  %-10s %s\n' "kilde"  "$(count_gz "$RAW_DIR") .gz-filer   ($RAW_DIR)"
  printf '  %-10s %s\n' "arkiv"  "$(count_gz "$ARCHIVE_DIR") .gz-filer   ($ARCHIVE_DIR)"
  if [[ -d "$ATTIC_DIR" ]] && [[ -n "$(ls -A "$ATTIC_DIR" 2>/dev/null)" ]]; then
    printf '  %-10s %s i %s snapshot(s) -- noget er blevet overskrevet\n' \
      "attic" "$(du -sh "$ATTIC_DIR" 2>/dev/null | cut -f1)" \
      "$(find "$ATTIC_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l)"
  else
    printf '  %-10s tom -- intet er blevet overskrevet\n' "attic"
  fi
}

if [[ "$STATUS_ONLY" == "yes" ]]; then
  echo "Status"
  status
  exit 0
fi

[[ -d "$RAW_DIR" ]] || { echo "FEJL: kildemappe findes ikke: $RAW_DIR" >&2; exit 1; }
command -v rsync >/dev/null || { echo "FEJL: rsync er ikke installeret" >&2; exit 1; }

mkdir -p "$ARCHIVE_DIR"

# --backup flytter en fil, der er ved at blive erstattet, til
# --backup-dir i stedet for at lade den blive skrevet over.
# Der er BEVIDST intet --delete: forsvinder en fil i kilden, skal
# arkivets kopi blive liggende. Det er hele pointen.
rsync -a --backup --backup-dir="$ATTIC_DIR/$(date +%F)" \
      "$RAW_DIR/" "$ARCHIVE_DIR/"

echo "Arkiveret."
status

if [[ "$VERIFY" == "yes" ]]; then
  echo
  echo "Tester alle .gz i arkivet"

  # -r: koer slet ikke gzip, hvis find ingen filer fandt. Uden det
  # laeser gzip fra stdin og melder "unexpected end of file", hvilket
  # ligner en defekt fil, men blot betyder at mappen er tom.
  BAD="$(find "$ARCHIVE_DIR" -type f -name '*.gz' -print0 \
         | xargs -0 -r -n1 gzip -t 2>&1 || true)"

  if [[ -z "$BAD" ]]; then
    echo "  Alle filer har korrekt CRC."
  else
    echo "$BAD" | sed 's/^/  /' >&2
    echo >&2
    echo "  Defekte filer fundet. Kopien i attic/ kan vaere hel." >&2
    exit 1
  fi
fi
