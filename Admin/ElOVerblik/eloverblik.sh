#!/usr/bin/env bash
# eloverblik.sh - kør `eloverblik-fetch.sh -r` fra cron og gem den anslåede
# tællerstand i en CSV-fil.
#
# Logbeskeder skrives med tidsstempel til stdout; cron lægger dem i logfilen:
#
#   # Eloverblik: anslået tællerstand - hver time kl. xx:17
#   17 * * * * /bin/bash /home/admina/git/Linux-Scripts/ElOverblik/eloverblik.sh >> /var/log/eloverblik/cron.log 2>&1
#
# CSV-filen får kun en ny linje, når Eloverblik har nye eller rettede data.
# Eloverblik er ca. et døgn bagud, så de fleste kørsler logger blot "uændret".
# Er data mere end STALE_DAYS dage bagud, logges [ADVARSEL].
#
# Kolonner (semikolon-separeret):
#   kørt             hvornår kørslen fandt de nye data
#   data_til_og_med  starten af den seneste time med data (23:00 = til kl. 24:00)
#   forbrug_kwh      forbrug siden aflæsningen i BASE
#   tællerstand_kwh  BASE + forbrug_kwh
#   kvalitet         "målt", eller "delvis estimeret" hvis Eloverblik har
#                    estimerede værdier i perioden

set -uo pipefail

# Kendt tællerstand aflæst på måleren: STAND@ÅÅÅÅ-MM-DD TT:MM
# Opdatér den, når du aflæser måleren igen (fx ved årsopgørelsen). Så holdes
# kaldene til Eloverblik små, og en eventuel afvigelse nulstilles.
BASE="${ELO_BASE:-91939@2026-10-25 10:29}"

# Normalt er data for i går klar i løbet af i dag (1-2 dage bagud).
STALE_DAYS="${ELO_STALE_DAYS:-3}"

SCRIPT="${ELO_SCRIPT:-$(dirname "$(readlink -f "$0")")/eloverblik-fetch.sh}"
DATA_FILE="${ELO_DATA_FILE:-$HOME/eloverblik/taellerstand.csv}"
TOKEN_FILE="${ELO_TOKEN_FILE:-$HOME/.eloverblik_token}"
HEADER='kørt;data_til_og_med;forbrug_kwh;tællerstand_kwh;kvalitet'

# cron har et minimalt miljø - sæt det, scriptet afhænger af
export PATH=/usr/local/bin:/usr/bin:/bin
export LC_ALL=C.UTF-8
export TZ=Europe/Copenhagen

log() { printf '%s [%s] %s\n' "$(date '+%F %T')" "$1" "$2"; }

# Hver linje fra eloverblik-fetch.sh's stderr som sin egen logbesked
log_stderr() {
  local line
  while IFS= read -r line; do
    [[ -n $line ]] && log "$1" "eloverblik-fetch.sh: $line"
  done <"$ERR"
}

# days_behind ÅÅÅÅ-MM-DD -> antal hele dage fra den dato til i dag
days_behind() {
  local t_now t_day
  t_now=$(date -d "$(date +%F) 12:00" +%s) || return 1
  t_day=$(date -d "$1 12:00" +%s) || return 1
  echo $(( (t_now - t_day + 43200) / 86400 ))
}

[[ -r $SCRIPT ]] || { log FEJL "kan ikke læse $SCRIPT"; exit 1; }

BASE_DATE=${BASE#*@}
BASE_DATE=${BASE_DATE:0:10}
[[ $BASE_DATE =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] ||
  { log FEJL "BASE har ikke formen STAND@ÅÅÅÅ-MM-DD [TT:MM]: $BASE"; exit 1; }

DATA_DIR=$(dirname "$DATA_FILE")
mkdir -p "$DATA_DIR" || { log FEJL "kan ikke oprette $DATA_DIR"; exit 1; }

# Undgå to kørsler på samme tid, hvis Eloverblik hænger
exec 9>"$DATA_DIR/.taellerstand.lock"
flock -n 9 || { log INFO "forrige kørsel kører stadig - springer over"; exit 0; }

ERR=$(mktemp)
trap 'rm -f "$ERR"' EXIT

OUT=$(bash "$SCRIPT" -r "$BASE" 2>"$ERR")
RC=$?

if (( RC != 0 )); then
  MSG=$(grep -m1 -E 'endnu ikke data|Ingen data for' "$ERR")
  if [[ -n $MSG ]]; then
    # Intet data efter aflæsningen endnu: seneste hele dag er dagen før BASE
    LAG=$(days_behind "$(date -d "$BASE_DATE -1 day" +%F)")
    if (( LAG > STALE_DAYS )); then
      log ADVARSEL "ingen data i Eloverblik efter aflæsningen $BASE_DATE ($LAG dage bagud) - tjek eloverblik.dk"
    else
      log INFO "${MSG#Fejl: }"
    fi
    exit 0
  fi
  log FEJL "eloverblik-fetch.sh stoppede med exit $RC:"
  log_stderr FEJL
  exit 1
fi
log_stderr INFO

# Find tallene i outputtet (virker både med og uden `column`-justering)
re_use='\(data til og med ([0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2})\):[[:space:]]*([0-9]+(\.[0-9]+)?) kWh'
re_est='udgangen af .*:[[:space:]]*([0-9]+(\.[0-9]+)?) kWh'
TS="" USE="" EST=""
while IFS= read -r line; do
  if [[ $line =~ $re_use ]]; then
    TS=${BASH_REMATCH[1]} USE=${BASH_REMATCH[2]}
  elif [[ $line =~ $re_est ]]; then
    EST=${BASH_REMATCH[1]}
  fi
done <<<"$OUT"

if [[ -z $TS || -z $USE || -z $EST ]]; then
  log FEJL "kunne ikke læse resultatet fra eloverblik-fetch.sh (er output-formatet ændret?):"
  while IFS= read -r line; do log FEJL "  $line"; done <<<"$OUT"
  exit 1
fi

if grep -q 'A04' "$ERR"; then KVAL='delvis estimeret'; else KVAL='målt'; fi

LAG=$(days_behind "${TS:0:10}")
stale_check() {
  if (( LAG > STALE_DAYS )); then
    log ADVARSEL "Eloverblik er $LAG dage bagud (seneste data: timen $TS) - tjek eloverblik.dk"
  fi
}

ROW="$TS;$USE;$EST;$KVAL"
[[ -s $DATA_FILE ]] || printf '%s\n' "$HEADER" >"$DATA_FILE"

if [[ $(tail -n1 "$DATA_FILE" | cut -d';' -f2-) == "$ROW" ]]; then
  if (( LAG > STALE_DAYS )); then
    stale_check
  else
    log INFO "uændret: $EST kWh (data til og med timen $TS)"
  fi
  exit 0
fi

printf '%s;%s\n' "$(date '+%F %T')" "$ROW" >>"$DATA_FILE" ||
  { log FEJL "kan ikke skrive til $DATA_FILE"; exit 1; }
log OK "$EST kWh (data til og med timen $TS, $USE kWh siden aflæsningen, $KVAL)"
stale_check

# Refresh-tokenet udløber efter ca. et år; så stopper alle kørsler med fejl.
if [[ -f $TOKEN_FILE ]]; then
  AGE=$(( ($(date +%s) - $(stat -c %Y "$TOKEN_FILE")) / 86400 ))
  if (( AGE >= 335 )); then
    log ADVARSEL "refresh-tokenet i $TOKEN_FILE er $AGE dage gammelt og udløber efter ca. et år - opret et nyt på eloverblik.dk (Datadeling)"
  fi
fi
