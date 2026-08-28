#!/usr/bin/env bash
#
# make-pdf.sh -- konverterer en markdown-fil til en typografisk sat PDF.
#
# Brug:  ./make-pdf.sh [input.md] [output.pdf]
#
# Motorer, i prioriteret raekkefoelge:
#   1. pandoc + xelatex  -- aegte sidetal, orddeling, indlejrede fonte
#   2. wkhtmltopdf       -- reserve; ingen sidetal paa upatchet qt
#
# Installation (Ubuntu/Debian):
#   sudo apt install pandoc texlive-xetex texlive-fonts-recommended \
#                    lmodern fonts-dejavu
#   # reserve:
#   sudo apt install wkhtmltopdf python3-markdown
#
set -euo pipefail

IN="${1:-README.md}"
OUT="${2:-${IN%.md}.pdf}"

[[ -f "$IN" ]] || { echo "FEJL: findes ikke: $IN" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Titel tages fra foerste H1; ellers filnavnet.
TITLE="$(grep -m1 '^# ' "$IN" | sed 's/^# //')"
[[ -z "$TITLE" ]] && TITLE="$(basename "${IN%.md}")"
DATED="$(date '+%-d. %B %Y')"

# Vandrette streger (---) fjernes: sektionslinjerne goer allerede
# arbejdet, og to slags streger konkurrerer visuelt.
sed -E '/^---[[:space:]]*$/d' "$IN" > "$TMP/clean.md"

# Sitets Cormorant Garamond kraever nettet. TeX Gyre Pagella er den
# naermeste old-style serif der foelger med texlive.
SERIF="TeX Gyre Pagella"
MONO="DejaVu Sans Mono"

# ------------------------------------------------------------ pandoc

if command -v pandoc >/dev/null && command -v xelatex >/dev/null; then

  cat > "$TMP/hdr.tex" <<'EOF'
\usepackage{titlesec}
\usepackage{xcolor}
\usepackage{fvextra}
\usepackage{fontspec}

\definecolor{muted}{HTML}{8A8A8A}
\definecolor{rulecol}{HTML}{DDD8D1}
\definecolor{coderule}{HTML}{CFC9C0}

% Sperret versal som paa sitet. Bemaerk: microtypes letterspacing
% virker ikke under xetex, saa det goeres via fontspec i stedet.
\newfontfamily\secfont{TeX Gyre Pagella}[LetterSpace=18.0]
\newcommand{\secfmt}[1]{{\secfont\MakeUppercase{#1}}}

\titleformat{\section}{\normalfont\footnotesize\color{muted}}{}{0pt}{\secfmt}[{\color{rulecol}\titlerule}]
\titlespacing*{\section}{0pt}{2.6em}{1.1em}
\titleformat{\subsection}{\normalfont\large\itshape}{}{0pt}{}
\titlespacing*{\subsection}{0pt}{1.8em}{0.6em}

% Ombryd lange kommandolinjer i stedet for at lade dem loebe ud i margen.
\DefineVerbatimEnvironment{Highlighting}{Verbatim}{breaklines,breaknonspaceingroup,breakanywhere,commandchars=\\\{\}}
\fvset{frame=leftline,framerule=0.9pt,rulecolor=\color{coderule},framesep=9pt,xleftmargin=11pt}

\setlength{\parskip}{0.55em}
\setlength{\parindent}{0pt}
EOF

  # --shift-heading-level-by=-1 loefter H1 op til dokumenttitel,
  # saa "##" bliver sektioner og faar sitets versaltypografi.
  if pandoc "$TMP/clean.md" -o "$OUT" \
      --pdf-engine=xelatex \
      --shift-heading-level-by=-1 \
      -V "mainfont=$SERIF" \
      -V "monofont=$MONO" \
      -V geometry:a4paper \
      -V geometry:margin=22mm \
      -V "title=$TITLE" \
      -V "date=$DATED" \
      -V colorlinks=true -V linkcolor=black -V urlcolor=black \
      -H "$TMP/hdr.tex" 2>"$TMP/err"; then
    echo "Skrevet: $OUT  ($(pdfinfo "$OUT" 2>/dev/null | awk '/^Pages/{print $2}') sider, via pandoc+xelatex)"
    exit 0
  fi

  echo "pandoc/xelatex fejlede -- falder tilbage paa wkhtmltopdf." >&2
  head -5 "$TMP/err" >&2
fi

# ------------------------------------------------------- wkhtmltopdf

command -v wkhtmltopdf >/dev/null || {
  echo "FEJL: hverken pandoc+xelatex eller wkhtmltopdf er tilgaengelig." >&2
  exit 1
}
python3 -c 'import markdown' 2>/dev/null || {
  echo "FEJL: python3-markdown mangler (noedvendig for reservemotoren)." >&2
  exit 1
}

python3 - "$TMP/clean.md" "$TMP/body.html" <<'PY'
import sys, markdown
src, dst = sys.argv[1], sys.argv[2]
html = markdown.markdown(
    open(src, encoding='utf-8').read(),
    extensions=['tables', 'fenced_code', 'attr_list', 'sane_lists'],
)
open(dst, 'w', encoding='utf-8').write(html)
PY

{
cat <<CSS
<!DOCTYPE html>
<html lang="da"><head><meta charset="UTF-8"><title>$TITLE</title>
<style>
  body { font-family: '$SERIF', Georgia, serif; font-size: 10.5pt;
         line-height: 1.62; color: #1a1a1a; background: #fff; }
  h1 { font-size: 24pt; font-weight: normal; margin: 0 0 1.5em; text-align: center; }
  h2 { font-size: 8.5pt; font-weight: normal; letter-spacing: 0.24em;
       text-transform: uppercase; color: #8a8a8a; margin: 2.4em 0 0.9em;
       padding-bottom: 0.55em; border-bottom: 1px solid #ddd8d1;
       page-break-after: avoid; }
  h3 { font-size: 12pt; font-weight: normal; font-style: italic;
       margin: 1.8em 0 0.5em; page-break-after: avoid; }
  p { margin: 0 0 0.85em; }
  ul, ol { margin: 0 0 0.95em; padding-left: 1.5em; }
  li { margin-bottom: 0.3em; }
  code { font-family: '$MONO', monospace; font-size: 8.8pt; color: #333; }
  pre { border-left: 2px solid #cfc9c0; padding: 0.6em 0 0.6em 1em;
        margin: 0 0 1.1em; page-break-inside: avoid; }
  pre code { font-size: 8.4pt; line-height: 1.5;
             white-space: pre-wrap; word-wrap: break-word; }
  table { width: 100%; border-collapse: collapse; margin: 0 0 1.2em;
          font-size: 9.5pt; page-break-inside: avoid; }
  th { font-size: 7.5pt; font-weight: normal; letter-spacing: 0.18em;
       text-transform: uppercase; color: #8a8a8a; text-align: left;
       padding: 0 0.8em 0.6em 0; border-bottom: 1px solid #ccc; }
  td { padding: 0.55em 0.8em 0.55em 0; border-bottom: 1px solid #eae6e0;
       vertical-align: top; }
  a { color: #1a1a1a; text-decoration: none; border-bottom: 1px solid #ccc; }
</style></head><body>
CSS
cat "$TMP/body.html"
echo '</body></html>'
} > "$TMP/full.html"

wkhtmltopdf --quiet --enable-local-file-access --page-size A4 \
  --margin-top 22mm --margin-bottom 20mm \
  --margin-left 20mm --margin-right 20mm \
  "$TMP/full.html" "$OUT"

echo "Skrevet: $OUT  (via wkhtmltopdf -- bemaerk: ingen sidetal)"
