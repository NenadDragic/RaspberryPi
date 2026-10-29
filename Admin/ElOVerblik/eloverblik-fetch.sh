#!/usr/bin/env bash
# Version:      1.1
# Date:         2026-10-26
# Test Run:
# Developper:   Nenad(a)dragic(.)com

# eloverblik-fetch.sh - hent elforbrug fra Eloverblik (Energinet DataHub, Customer API)
#
# Kræver: bash, curl (>= 7.55), jq
# Refresh-token (oprettet på eloverblik.dk -> profil -> Datadeling) læses fra
# ~/.eloverblik_token (chmod 600) eller fra den fil, ELO_TOKEN_FILE peger på.
# Tokens sendes til curl via stdin, så de ikke kan ses i `ps` eller shell-historik.
#
# API-begrænsninger: max 730 dage pr. tidsseriekald (scriptet deler lange
# perioder op i kalenderår), data for de seneste 5 år + indeværende år,
# 2 token-kald og 120 kald i alt pr. minut pr. IP.

set -euo pipefail

API="${ELO_API:-https://api.eloverblik.dk/customerapi/api}"
TOKEN_FILE="${ELO_TOKEN_FILE:-$HOME/.eloverblik_token}"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/eloverblik"
ACCESS_CACHE="$CACHE_DIR/access_token"
export TZ="${TZ:-Europe/Copenhagen}"

usage() {
  cat <<EOF
Brug: $(basename "$0") [-m MÅLEPUNKT] [-f FRA] [-t TIL] [-a AGGREGERING] [-r STAND@DATO] [-j] [-l]

  -m  Målepunkt-ID (18 cifre). Udelades: ELO_METERING_POINT eller første
      forbrugsmålepunkt på kontoen.
  -f  Fra-dato YYYY-MM-DD (standard: i går)
  -t  Til-dato YYYY-MM-DD, eksklusiv (standard: i dag)
  -a  Actual | Quarter | Hour | Day | Month | Year (standard: Hour)
  -r  Anslå målerens aktuelle tællerstand ud fra en kendt stand, fx aflæst
      på displayet eller fra årsopgørelsen:
        STAND@DATO           stand i kWh ved starten af DATO (kl. 00:00)
        STAND@"DATO TT:MM"   stand aflæst på et bestemt klokkeslæt
      Eksempel: -r 44107.6@"2026-10-25 07:30"
  -j  Udskriv rå JSON i stedet for tabel
  -l  Vis målepunkter på kontoen og afslut
  -h  Denne hjælp

Eksempler:
  $(basename "$0")                          # i går, pr. time
  $(basename "$0") -f 2026-10-01 -a Day     # pr. dag fra 1. oktober til i dag
  $(basename "$0") -f 2021-01-01 -a Year    # samlet forbrug pr. år siden 2021
  $(basename "$0") -r 41234.5@2026-01-01    # anslået tællerstand nu
  $(basename "$0") -r 44107.6@"2026-10-25 07:30"

Bemærk: Eloverblik er ca. et døgn bagud, så tællerstanden anslås til og med
den seneste time/dag, der er data for - ikke til lige nu.
EOF
}

die() { echo "Fejl: $*" >&2; exit 1; }

for cmd in curl jq; do
  command -v "$cmd" >/dev/null || die "'$cmd' mangler (sudo apt install $cmd)"
done

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# api METODE STI TOKEN [BODY] -> svar-body på stdout. Prøver igen ved 429/503.
api() {
  local method=$1 path=$2 token=$3 body=${4-} code attempt
  local -a data=()
  [[ -n $body ]] && data=(--data "$body")
  for attempt in 1 2 3; do
    code=$(printf 'Authorization: Bearer %s\n' "$token" |
      curl -sS -X "$method" -H @- \
        -H 'Accept: application/json' -H 'Content-Type: application/json' \
        "${data[@]}" --max-time 120 \
        -o "$WORK/resp" -w '%{http_code}' "$API$path") || code=000
    case $code in
      200) cat "$WORK/resp"; return 0 ;;
      401)
        rm -f "$ACCESS_CACHE"
        echo "HTTP 401 fra $path: token afvist (cachet access-token slettet - kør igen)" >&2
        return 1 ;;
      429|503)
        echo "HTTP $code (Eloverblik er travl) - venter 30 s, forsøg $attempt/3" >&2
        sleep 30 ;;
      *)
        echo "HTTP $code fra $path: $(head -c 500 "$WORK/resp" 2>/dev/null)" >&2
        return 1 ;;
    esac
  done
  echo "Opgav efter 3 forsøg" >&2
  return 1
}

# Kortlivet access-token (gyldigt 24 t) caches i 23 t for at skåne API'et.
access_token() {
  mkdir -p "$CACHE_DIR" && chmod 700 "$CACHE_DIR"
  if [[ -s $ACCESS_CACHE && -n $(find "$ACCESS_CACHE" -mmin -1380 2>/dev/null) ]]; then
    cat "$ACCESS_CACHE"
    return
  fi
  [[ -r $TOKEN_FILE ]] || die "kan ikke læse $TOKEN_FILE"
  local refresh token
  refresh=$(tr -d '[:space:]' <"$TOKEN_FILE")
  [[ -n $refresh ]] || die "$TOKEN_FILE er tom"
  token=$(api GET /token "$refresh" | jq -r '.result // empty') ||
    die "kunne ikke hente access-token (er refresh-tokenet udløbet eller slettet?)"
  [[ -n $token ]] || die "tomt access-token i svaret"
  (umask 077 && printf '%s' "$token" >"$ACCESS_CACHE")
  printf '%s' "$token"
}

list_points() {
  api GET "/meteringpoints/meteringpoints?includeAll=false" "$1" |
    jq -r '.result[]? | [.meteringPointId, (.typeOfMP // "?")] | @tsv'
}

table() { if command -v column >/dev/null; then column -t -s $'\t'; else cat; fi; }

# Fejl rapporteret pr. målepunkt i selve svaret
check_result() {
  if jq -e '[.result[]? | select(.success == false)] | length > 0' "$1" >/dev/null; then
    jq -r '.result[] | select(.success == false) | "Fejl fra Eloverblik: \(.errorCode // "") \(.errorText // "")"' \
      "$1" >&2
    exit 1
  fi
}

# jq udtrækker kun rådata: periodestart (UTC), forskydning i sekunder
# ((position-1) * opløsning), evt. note, kWh og kvalitet. Al tidsregning sker
# bagefter med GNU date (to_local), fordi jq 1.6 (Debian/Raspberry Pi OS
# bookworm) viser lokal tid en time forkert i sommertid.
# Opløsningskoder set i Eloverbliks svar: PT1H (time), PT1D (døgn).
# shellcheck disable=SC2016  # jq-program, skal ikke ekspanderes af bash
JQ_ROWS='
def step: {"PT15M": 900, "PT1H": 3600, "PT1D": 86400, "P1D": 86400}[.];
.result[]?.MyEnergyData_MarketDocument.TimeSeries[]?
| .Period[]?
| (.timeInterval.start | sub("\\.[0-9]+"; "") | if test("Z$") then . else . + "Z" end) as $start
| (.resolution // "") as $res
| ($res | step) as $s
| .Point[]?
| (.position | tonumber) as $p
| (if $s then [($p - 1) * $s, ""]
   elif $p == 1 then [0, ""]
   else [0, " (periodestart, pos \($p), \($res))"] end) as [$off, $note]
| [$start, $off, $note,
   (.["out_Quantity.quantity"] | tonumber),
   (.["out_Quantity.quality"] // "")]
| @tsv'

# to_local RÅFIL -> rækker "lokal tid<TAB>kWh<TAB>kvalitet" på stdout.
# Tider beregnes i UTC og omregnes til $TZ, så sommertid/vintertid (23/25-
# timers døgn) håndteres korrekt. Ved skift til vintertid optræder kl. 02:00
# derfor to gange (først sommertid, så vintertid).
to_local() {
  local raw=$1
  [[ -s $raw ]] || return 0
  cut -f1 "$raw" | date -f - +%s >"$WORK/start.s" ||
    die "kunne ikke tolke periodestart i svaret fra Eloverblik"
  paste "$WORK/start.s" <(cut -f2 "$raw") |
    awk -F'\t' '{ printf "@%.0f\n", $1 + $2 }' |
    date -f - '+%Y-%m-%d %H:%M' >"$WORK/local.ts" ||
    die "kunne ikke omregne tidspunkter til lokal tid"
  [[ $(wc -l <"$WORK/local.ts") -eq $(wc -l <"$raw") ]] ||
    die "antal tidspunkter passer ikke med antal målinger"
  paste "$WORK/local.ts" <(cut -f3- "$raw") |
    awk -F'\t' -v OFS='\t' '{ print $1 $2, $3, $4 }'
}

# fetch_rows FRA TIL AGG -> $WORK/rows.tsv. Deler perioden op i kalenderår,
# fordi API'et højst tillader 730 dage pr. kald.
fetch_rows() {
  local from=$1 to=$2 agg=$3 cur next n=0
  : >"$WORK/rows.tsv"
  cur=$from
  while [[ $cur < $to ]]; do
    next="$(( 10#${cur:0:4} + 1 ))-01-01"
    if [[ $next > $to ]]; then next=$to; fi
    n=$((n + 1))
    api POST "/meterdata/gettimeseries/$cur/$next/$agg" "$TOKEN" "$BODY" >"$WORK/ts$n.json" ||
      die "kald til gettimeseries fejlede ($cur -> $next)"
    if (( RAW )); then
      jq . "$WORK/ts$n.json"
    else
      check_result "$WORK/ts$n.json"
      jq -r "$JQ_ROWS" "$WORK/ts$n.json" >"$WORK/raw.tsv"
      to_local "$WORK/raw.tsv" >>"$WORK/rows.tsv"
    fi
    cur=$next
  done
}

MP="${ELO_METERING_POINT:-}"
FROM=$(date -d yesterday +%F)
TO=$(date +%F)
AGG=Hour
RAW=0
LIST=0
BASE=""
BASE_VAL=""

while getopts ":m:f:t:a:r:jlh" opt; do
  case $opt in
    m) MP=$OPTARG ;;
    f) FROM=$OPTARG ;;
    t) TO=$OPTARG ;;
    a) AGG=$OPTARG ;;
    r) BASE=$OPTARG ;;
    j) RAW=1 ;;
    l) LIST=1 ;;
    h) usage; exit 0 ;;
    :) die "-$OPTARG kræver en værdi" ;;
    *) usage >&2; exit 2 ;;
  esac
done

BASE_H=00
BASE_M=00
if [[ -n $BASE ]]; then
  re='^([0-9]+([.,][0-9]+)?)@([0-9]{4}-[0-9]{2}-[0-9]{2})([T ]([0-9]{2}):([0-9]{2}))?$'
  [[ $BASE =~ $re ]] ||
    die "-r skal have formen STAND@ÅÅÅÅ-MM-DD eller STAND@\"ÅÅÅÅ-MM-DD TT:MM\""
  BASE_VAL=${BASH_REMATCH[1]/,/.}
  FROM=${BASH_REMATCH[3]}
  if [[ -n ${BASH_REMATCH[4]} ]]; then
    BASE_H=${BASH_REMATCH[5]}
    BASE_M=${BASH_REMATCH[6]}
    (( 10#$BASE_H < 24 && 10#$BASE_M < 60 )) || die "ugyldigt klokkeslæt i -r: $BASE_H:$BASE_M"
    AGG=Hour   # timedata, så forbruget før aflæsningen kan trækkes fra
  else
    AGG=Day
  fi
  [[ $FROM < $TO ]] ||
    die "Eloverblik har endnu ikke data for $FROM (ca. et døgns forsinkelse) - kør igen i morgen"
fi

[[ -z $MP || $MP =~ ^[0-9]{18}$ ]] || die "målepunkt-ID skal være 18 cifre: $MP"
[[ $FROM =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || die "ugyldig fra-dato: $FROM"
[[ $TO =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || die "ugyldig til-dato: $TO"
[[ $FROM < $TO ]] || die "fra-dato ($FROM) skal ligge før til-dato ($TO)"
case $AGG in Actual|Quarter|Hour|Day|Month|Year) ;; *) die "ugyldig aggregering: $AGG" ;; esac

TOKEN=$(access_token)

if (( LIST )); then
  echo -e "målepunkt\ttype (E17=forbrug, E18=produktion)"
  list_points "$TOKEN"
  exit 0
fi

if [[ -z $MP ]]; then
  POINTS=$(list_points "$TOKEN") || die "kunne ikke hente målepunkter"
  MP=$(awk -F'\t' '$2=="E17"{print $1; exit}' <<<"$POINTS")
  [[ -n $MP ]] || MP=$(head -n1 <<<"$POINTS" | cut -f1)
  [[ -n $MP ]] || die "fandt ingen målepunkter på kontoen"
fi
[[ $MP =~ ^[0-9]{18}$ ]] || die "målepunkt-ID skal være 18 cifre: $MP"

BODY=$(jq -cn --arg mp "$MP" '{meteringPoints: {meteringPoint: [$mp]}}')

fetch_rows "$FROM" "$TO" "$AGG"
(( RAW )) && exit 0

if [[ ! -s $WORK/rows.tsv ]]; then
  echo "Ingen data for $FROM -> $TO (data kommer typisk med ca. et døgns forsinkelse)." >&2
  exit 1
fi

SUM=$(awk -F'\t' '{s += $2} END {printf "%.3f", s}' "$WORK/rows.tsv")

# --- Anslået tællerstand ------------------------------------------------------
if [[ -n $BASE ]]; then
  BASE_TS="$FROM $BASE_H:00"
  # Rækken for aflæsningstimen tælles kun med for den del af timen, der
  # ligger efter aflæsningen (fx 07:30 -> halvdelen af timen 07:00-08:00).
  IFS=$'\t' read -r USED LAST_TS < <(
    awk -F'\t' -v bts="$BASE_TS" -v frac="$(( 60 - 10#$BASE_M ))" '
      $1 > bts  { s += $2 }
      $1 == bts { s += $2 * frac / 60 }
      { last = $1 }
      END { printf "%.3f\t%s\n", s, last }' "$WORK/rows.tsv")
  EST=$(awk -v b="$BASE_VAL" -v s="$USED" 'BEGIN {printf "%.3f", b + s}')
  if [[ $AGG == Day ]]; then
    LAST_LABEL="udgangen af ${LAST_TS%% *}"
  else
    LAST_LABEL="udgangen af timen ${LAST_TS#* } den ${LAST_TS%% *}"
  fi
  echo "Målepunkt $MP"
  {
    echo -e "Kendt tællerstand $FROM $BASE_H:$BASE_M:\t$BASE_VAL kWh"
    echo -e "Forbrug derefter (data til og med $LAST_TS):\t$USED kWh"
    echo -e "Anslået tællerstand ved $LAST_LABEL:\t$EST kWh"
  } | table
  if grep -qv $'\tA04$' "$WORK/rows.tsv"; then
    echo "Bemærk: perioden indeholder ikke-målte værdier (kvalitet <> A04)." >&2
  fi
  exit 0
fi

# --- Tidsserie ------------------------------------------------------------------
echo "Målepunkt $MP  |  $FROM -> $TO  |  $AGG  |  tider i $TZ"
{
  echo -e "tidspunkt\tkWh\tkvalitet"
  cat "$WORK/rows.tsv"
} | table
echo
echo "Total: $SUM kWh  (kvalitet A04 = målt, A03 = estimeret)"
