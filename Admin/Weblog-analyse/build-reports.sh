#!/usr/bin/env bash
#
# build-reports.sh -- bygger GoAccess-rapporter ud fra raa cPanel-logs.
#
# Brug:
#   ./build-reports.sh [--days N] [--no-days] [kildemappe] [outputmappe]
#
#   --days N    Antal dage bagud der faar deres egen dagsrapport.
#               Standard 60. Brug 0 for alle dage nogensinde.
#   --no-days   Spring dagsrapporter over; byg kun maaned og all-time.
#   --live      Accepter ogsaa logfiler uden -Mmm-AAAA i navnet
#               (til ~/access-logs/). Uden flaget ignoreres de, saa
#               scriptet kan koeres i en mappe med andet indhold.
#
# Uanset flag bygges altid:
#   - en all-time rapport pr. domaene (hele historikken)
#   - en rapport pr. kalendermaaned pr. domaene
#   - en samlet all-time rapport med vhost-panel
#
set -euo pipefail

DAYS_WINDOW=60
ACCEPT_UNDATED="no"
POSITIONAL=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --days)    DAYS_WINDOW="${2:?--days kraever et tal}"; shift 2 ;;
    --days=*)  DAYS_WINDOW="${1#*=}"; shift ;;
    --no-days) DAYS_WINDOW="-1"; shift ;;
    --live)    ACCEPT_UNDATED="yes"; shift ;;
    -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
    *)         POSITIONAL+=("$1"); shift ;;
  esac
done

SRC_DIR="${POSITIONAL[0]:-$HOME/weblogs/raw}"
OUT_DIR="${POSITIONAL[1]:-$HOME/weblogs/reports}"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

command -v goaccess >/dev/null || { echo "FEJL: goaccess findes ikke i PATH" >&2; exit 1; }
[[ -d "$SRC_DIR" ]] || { echo "FEJL: kildemappe findes ikke: $SRC_DIR" >&2; exit 1; }

mkdir -p "$OUT_DIR" "$WORK_DIR/days" "$WORK_DIR/months"

# Skaeringsdato for dagsrapporter.
if [[ "$DAYS_WINDOW" == "-1" ]]; then
  DAY_CUTOFF=""
elif [[ "$DAYS_WINDOW" == "0" ]]; then
  DAY_CUTOFF="0000-00-00"
else
  DAY_CUTOFF="$(date -d "$DAYS_WINDOW days ago" +%F)"
fi

# ------------------------------------------------------------------ filtre

NOISE=(
  '/\.well-known/acme-challenge/'   # Let's Encrypt-validering
  'Cpanel-HTTP-Client'              # udbyderens egne kald
  'forestengine\.net'               # scraper der udgiver sig for Chrome
)
NOISE_RE="$(IFS='|'; echo "${NOISE[*]}")"

# --------------------------------------------------- domaenenavne
#
# cPanel saetter kontoens hoveddomaene bag hvert vhost-navn:
#   dragic.com.dragic-playground.info-Aug-2026.gz
# Suffikset fjernes her, saa labels bliver laesbare.

STRIP_SUFFIXES=(
  ".dragic-playground.info"
)

# ALIAS lægger flere vhosts sammen til ét domaene. Punycode og
# ASCII-varianten af samme site logges hver for sig af cPanel; her
# slaas de sammen. Fjern linjen hvis du hellere vil se dem adskilt.
declare -A ALIAS=(
  ["xn--tnkeboksen-d6a.dk"]="taenkeboksen.dk"
)

# PRETTY er kun visning -- filnavne bruger ASCII-noeglen ovenfor.
declare -A PRETTY=(
  ["taenkeboksen.dk"]="tænkeboksen.dk"
)

pretty_name() {
  local raw="$1"
  if [[ -n "${PRETTY[$raw]:-}" ]]; then echo "${PRETTY[$raw]}"; else echo "$raw"; fi
}

# --------------------------------------------------- goaccess-opsaetning

GA_OPTS=(--ignore-crawlers --real-os --agent-list)

if goaccess --help 2>&1 | grep -q -- '--anonymize-ip'; then
  GA_OPTS+=(--anonymize-ip)
  echo "IP-anonymisering: slaaet til"
else
  echo "IP-anonymisering: ikke understoettet af denne goaccess-version"
fi

read_log() {
  case "$1" in
    *.gz) zcat -- "$1" ;;
    *)    cat -- "$1"  ;;
  esac
}

domain_of() {
  local b suf
  b="$(basename "$1")"
  b="${b%.gz}"
  b="$(echo "$b" | sed -E 's/-[A-Za-z]{3}-[0-9]{4}$//')"
  b="${b%-ssl_log}"

  # Fjern kontoens hoveddomaene, men kun som suffiks -- ellers ville
  # selve hoveddomaenets egen log blive reduceret til tom streng.
  for suf in "${STRIP_SUFFIXES[@]}"; do
    if [[ "$b" == *"$suf" && "$b" != "$suf" ]]; then
      b="${b%$suf}"
      break
    fi
  done

  # Slaa alias op, saa fx punycode og ASCII havner i samme gruppe.
  [[ -n "${ALIAS[$b]:-}" ]] && b="${ALIAS[$b]}"

  echo "$b"
}

# ------------------------------------------------------- gruppering

declare -A LOGGROUPS
FILE_COUNT=0
SKIPPED_DUPES=0

SKIPPED_OTHER=0

while IFS= read -r -d '' f; do
  base="$(basename "$f")"

  # WSL efterlader NTFS-datastroemme som "fil.gz:Zone.Identifier".
  # De er 25 bytes metadata og maa ikke behandles som logs.
  case "$base" in
    *:Zone.Identifier|.*) continue ;;
  esac

  # cPanel lægger andre logtyper i samme mappe. ftp_log har et helt
  # andet format og hoerer ikke til i en webstatistik.
  case "$base" in
    *-ftp_log-*|*-imap_log-*|*-pop3_log-*|*-smtp_log-*)
      SKIPPED_OTHER=$((SKIPPED_OTHER + 1)); continue ;;
  esac

  # Whitelist: kun arkivfiler paa formen navn-Mmm-AAAA[.gz].
  # Uden dette opsamles alt andet i mappen -- kildekode, Makefiles,
  # README'er -- som var det logs.
  if [[ "$ACCEPT_UNDATED" != "yes" ]]; then
    if ! [[ "${base%.gz}" =~ -[A-Za-z]{3}-[0-9]{4}$ ]]; then
      continue
    fi
  fi

  # Ligger baade "X" og "X.gz" i mappen, er det den samme log to gange.
  # Vi bruger den komprimerede og springer den ukomprimerede over,
  # ellers taelles al trafikken dobbelt.
  if [[ "$base" != *.gz && -f "${f}.gz" ]]; then
    SKIPPED_DUPES=$((SKIPPED_DUPES + 1))
    continue
  fi

  dom="$(domain_of "$f")"
  [[ -z "$dom" ]] && continue
  LOGGROUPS["$dom"]+="$f"$'\n'
  FILE_COUNT=$((FILE_COUNT + 1))
done < <(find "$SRC_DIR" -type f -print0)

if [[ ${#LOGGROUPS[@]} -eq 0 ]]; then
  echo "Ingen logfiler fundet i $SRC_DIR" >&2
  exit 1
fi

echo "Fandt $FILE_COUNT fil(er) fordelt paa ${#LOGGROUPS[@]} domaene(r)."
[[ $SKIPPED_DUPES -gt 0 ]] && echo "Sprang $SKIPPED_DUPES dublet(ter) over (ukomprimeret + .gz)."
[[ $SKIPPED_OTHER -gt 0 ]] && echo "Sprang $SKIPPED_OTHER ikke-web-log(s) over (ftp/mail)."
if [[ -n "$DAY_CUTOFF" ]]; then
  if [[ "$DAY_CUTOFF" == "0000-00-00" ]]; then
    echo "Dagsrapporter: alle dage"
  else
    echo "Dagsrapporter: fra og med $DAY_CUTOFF"
  fi
else
  echo "Dagsrapporter: slaaet fra"
fi
echo

# --------------------------------------------- pr. domaene

COMBINED="$WORK_DIR/combined.log"
: > "$COMBINED"

declare -A LINECOUNT

for dom in "${!LOGGROUPS[@]}"; do
  label="$(pretty_name "$dom")"
  clean="$WORK_DIR/${dom}.log"
  : > "$clean"

  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    read_log "$f" | grep -E -v "$NOISE_RE" >> "$clean" || true
  done <<< "${LOGGROUPS[$dom]}"

  n="$(wc -l < "$clean")"
  LINECOUNT["$dom"]="$n"

  if [[ "$n" -eq 0 ]]; then
    echo "  $label -- 0 linjer tilbage efter filtrering, springer over"
    continue
  fi

  echo "  $label -- $n linjer (all-time)"

  goaccess "$clean" \
    --log-format=COMBINED \
    "${GA_OPTS[@]}" \
    --html-report-title="$label — all time" \
    -o "$OUT_DIR/${dom}.html"

  awk -v d="$label" '{print d, $0}' "$clean" >> "$COMBINED"

  # ------------------- opdeling pr. maaned og pr. dag i een gennemgang
  #
  # close() kaldes naar datoen skifter, saa vi ikke rammer awk's
  # graense for samtidigt aabne filer ved flere aars historik.
  awk -v dom="$dom" \
      -v daydir="$WORK_DIR/days" \
      -v mondir="$WORK_DIR/months" '
    BEGIN {
      split("Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec", m, " ")
      for (i = 1; i <= 12; i++) mn[m[i]] = sprintf("%02d", i)
      prevd = ""; prevm = ""
    }
    {
      if (match($0, /\[[0-9][0-9]\/[A-Za-z][A-Za-z][A-Za-z]\/[0-9][0-9][0-9][0-9]:/)) {
        tok = substr($0, RSTART + 1, RLENGTH - 2)
        split(tok, p, "/")
        if (p[2] in mn) {
          ym  = p[3] "-" mn[p[2]]
          iso = ym "-" p[1]

          df = daydir "/" dom "__" iso ".log"
          mf = mondir "/" dom "__" ym ".log"

          if (df != prevd) { if (prevd != "") close(prevd); prevd = df }
          if (mf != prevm) { if (prevm != "") close(prevm); prevm = mf }

          print >> df
          print >> mf
        }
      }
    }
  ' "$clean"

  # ---- maanedsrapporter (altid, det er selve historikken)
  months=0
  for mfile in "$WORK_DIR/months/${dom}__"*.log; do
    [[ -e "$mfile" ]] || continue
    ym="$(basename "$mfile" .log)"; ym="${ym##*__}"
    mnum="$(wc -l < "$mfile")"

    goaccess "$mfile" \
      --log-format=COMBINED \
      "${GA_OPTS[@]}" \
      --html-report-title="$label — $ym" \
      -o "$OUT_DIR/${dom}__${ym}.html"

    echo "$ym|$dom|$label|$mnum" >> "$WORK_DIR/monthindex.txt"
    months=$((months + 1))
  done
  echo "      $months maaned(er)"

  # ---- dagsrapporter (begraenset til vinduet)
  if [[ -n "$DAY_CUTOFF" ]]; then
    days=0
    for dayfile in "$WORK_DIR/days/${dom}__"*.log; do
      [[ -e "$dayfile" ]] || continue
      iso="$(basename "$dayfile" .log)"; iso="${iso##*__}"

      # Strengsammenligning virker her, fordi datoerne er ISO-formatteret.
      [[ "$iso" < "$DAY_CUTOFF" ]] && continue

      dnum="$(wc -l < "$dayfile")"

      goaccess "$dayfile" \
        --log-format=COMBINED \
        "${GA_OPTS[@]}" \
        --html-report-title="$label — $iso" \
        -o "$OUT_DIR/${dom}__${iso}.html"

      echo "$iso|$dom|$label|$dnum" >> "$WORK_DIR/dayindex.txt"
      days=$((days + 1))
    done
    echo "      $days dag(e) i vinduet"
  fi
done

# ------------------------------------------------- samlet all-time

if [[ -s "$COMBINED" ]]; then
  echo
  echo "Bygger samlet all-time rapport med vhost-panel..."
  goaccess "$COMBINED" \
    --log-format='%v %h %^[%d:%t %^] "%r" %s %b "%R" "%u"' \
    --date-format=%d/%b/%Y \
    --time-format=%H:%M:%S \
    "${GA_OPTS[@]}" \
    --html-report-title="Alle domæner — all time" \
    -o "$OUT_DIR/_alle.html"
fi

# ------------------------------------------------- oversigtsside

GENERATED="$(date '+%d.%m.%Y %H:%M')"

# Periodens udstraekning, til undertitlen.
RANGE=""
if [[ -s "$WORK_DIR/monthindex.txt" ]]; then
  first="$(cut -d'|' -f1 "$WORK_DIR/monthindex.txt" | sort | head -1)"
  last="$(cut -d'|' -f1 "$WORK_DIR/monthindex.txt" | sort | tail -1)"
  if [[ "$first" == "$last" ]]; then RANGE="$first"; else RANGE="$first – $last"; fi
fi

{
cat <<'HEAD'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <meta name="robots" content="noindex, nofollow">
  <title>Access Logs — Dragic.com</title>
  <link href="https://fonts.googleapis.com/css2?family=Cormorant+Garamond:ital,wght@0,300;0,400;1,300&display=swap" rel="stylesheet">
  <style>
    *, *::before, *::after { margin:0; padding:0; box-sizing:border-box; }
    body {
      background-color:#f7f5f1;
      font-family:'Cormorant Garamond', Georgia, serif;
      color:#1a1a1a; min-height:100vh;
      display:flex; flex-direction:column; align-items:center;
      padding:4rem 2rem 6rem;
    }
    main { max-width:680px; width:100%; animation:fadein 1.4s ease both; }
    @keyframes fadein { from{opacity:0;transform:translateY(14px);} to{opacity:1;transform:translateY(0);} }
    .site-name {
      display:block; font-size:0.75rem; font-weight:300; letter-spacing:0.3em;
      text-transform:uppercase; color:#999; margin-bottom:3.5rem;
      text-align:center; text-decoration:none; transition:color 0.2s;
    }
    .site-name:hover { color:#666; }
    h1 { font-size:2.6rem; font-weight:300; letter-spacing:0.03em; margin-bottom:0.4rem; line-height:1.2; }
    h2 {
      font-size:0.7rem; font-weight:300; letter-spacing:0.25em;
      text-transform:uppercase; color:#999; margin:3.5rem 0 1.2rem;
    }
    .tagline { font-size:1.05rem; font-style:italic; font-weight:300; color:#777; margin-bottom:2.8rem; }
    .divider { width:40px; height:1px; background:#ccc; margin:0 0 2.8rem 0; }
    table { width:100%; border-collapse:collapse; }
    thead tr { border-bottom:1px solid #ccc; }
    thead th {
      font-size:0.7rem; font-weight:300; letter-spacing:0.25em;
      text-transform:uppercase; color:#999; padding:0 0 0.9rem; text-align:left;
    }
    thead th:last-child { text-align:right; }
    tbody tr { border-bottom:1px solid #e8e4de; transition:background 0.15s; }
    tbody tr:hover { background:#f0ede8; }
    tbody td {
      font-size:1.05rem; font-weight:300; line-height:1.5;
      padding:1rem 0; color:#333; vertical-align:top;
    }
    td.num {
      font-size:0.72rem; letter-spacing:0.18em; text-transform:uppercase;
      color:#999; width:110px; padding-top:1.1rem; text-align:right;
    }
    td.period {
      font-size:0.72rem; letter-spacing:0.18em; text-transform:uppercase;
      color:#999; width:120px; padding-top:1.1rem;
    }
    tbody td:last-child { text-align:right; width:60px; padding-top:1.05rem; }
    tbody td a {
      font-size:0.72rem; font-weight:300; letter-spacing:0.18em;
      text-transform:uppercase; color:#1a1a1a; text-decoration:none;
      border-bottom:1px solid #bbb; padding-bottom:1px;
      transition:color 0.2s, border-color 0.2s;
    }
    tbody td a:hover { color:#555; border-color:#555; }
    .note {
      font-size:0.85rem; font-style:italic; font-weight:300;
      color:#999; line-height:1.6; margin-top:1.2rem;
    }
    footer {
      margin-top:5rem; font-size:0.7rem; font-weight:300;
      letter-spacing:0.18em; color:#bbb; text-align:center;
    }
  </style>
</head>
<body>
  <main>
    <a href="https://www.dragic.com" class="site-name">Dragic.com</a>

    <h1>Access Logs</h1>
HEAD

if [[ -n "$RANGE" ]]; then
  printf '    <p class="tagline">Visitor reports &middot; %s</p>\n' "$RANGE"
else
  printf '    <p class="tagline">Visitor reports</p>\n'
fi

cat <<'T1HEAD'

    <div class="divider"></div>

    <h2>All time</h2>

    <table>
      <thead>
        <tr>
          <th>Domain</th>
          <th>Entries</th>
          <th>Report</th>
        </tr>
      </thead>
      <tbody>
T1HEAD

if [[ -s "$COMBINED" ]]; then
  total="$(wc -l < "$COMBINED")"
  printf '        <tr>\n          <td>All domains</td>\n          <td class="num">%s</td>\n          <td><a href="_alle.html">View</a></td>\n        </tr>\n' "$total"
fi

for dom in $(printf '%s\n' "${!LOGGROUPS[@]}" | sort); do
  n="${LINECOUNT[$dom]:-0}"
  [[ "$n" -eq 0 ]] && continue
  printf '        <tr>\n          <td>%s</td>\n          <td class="num">%s</td>\n          <td><a href="%s.html">View</a></td>\n        </tr>\n' \
    "$(pretty_name "$dom")" "$n" "$dom"
done

echo '      </tbody>'
echo '    </table>'

# ---- historik pr. maaned
if [[ -s "$WORK_DIR/monthindex.txt" ]]; then
  cat <<'T2HEAD'

    <h2>By month</h2>

    <table>
      <thead>
        <tr>
          <th>Month</th>
          <th>Domain</th>
          <th>Entries</th>
          <th>Report</th>
        </tr>
      </thead>
      <tbody>
T2HEAD

  sort -r -t'|' -k1,1 -k3,3 "$WORK_DIR/monthindex.txt" | while IFS='|' read -r ym dom label num; do
    printf '        <tr>\n          <td class="period">%s</td>\n          <td>%s</td>\n          <td class="num">%s</td>\n          <td><a href="%s__%s.html">View</a></td>\n        </tr>\n' \
      "$ym" "$label" "$num" "$dom" "$ym"
  done

  echo '      </tbody>'
  echo '    </table>'
fi

# ---- dagsvindue
if [[ -s "$WORK_DIR/dayindex.txt" ]]; then
  cat <<'T3HEAD'

    <h2>By day</h2>

    <table>
      <thead>
        <tr>
          <th>Date</th>
          <th>Domain</th>
          <th>Entries</th>
          <th>Report</th>
        </tr>
      </thead>
      <tbody>
T3HEAD

  sort -r -t'|' -k1,1 -k3,3 "$WORK_DIR/dayindex.txt" | while IFS='|' read -r iso dom label num; do
    printf '        <tr>\n          <td class="period">%s</td>\n          <td>%s</td>\n          <td class="num">%s</td>\n          <td><a href="%s__%s.html">View</a></td>\n        </tr>\n' \
      "$iso" "$label" "$num" "$dom" "$iso"
  done

  echo '      </tbody>'
  echo '    </table>'

  if [[ "$DAY_CUTOFF" != "0000-00-00" ]]; then
    printf '    <p class="note">Daily reports cover the last %s days. Older days remain available through the monthly reports above.</p>\n' "$DAYS_WINDOW"
  fi
fi

cat <<FOOT
  </main>

  <footer>Generated $GENERATED &middot; &copy; 2026 Nenad Ahlstr&oslash;m Dragic</footer>
</body>
</html>
FOOT
} > "$OUT_DIR/index.html"

echo
echo "Faerdig. Rapporter ligger i: $OUT_DIR"
echo "Aabn oversigten:  xdg-open $OUT_DIR/index.html"
