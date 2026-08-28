# make-pdf.sh

Converts a markdown file into a typeset PDF, used to produce [README.pdf](README.pdf) from [README.md](README.md).

---

## Usage

```console
chmod +x make-pdf.sh
./make-pdf.sh [input.md] [output.pdf]
```

Both arguments are optional: input defaults to `README.md` in the current directory, output defaults to the input's basename with a `.pdf` extension.

Prerequisites (primary engine):

```console
sudo apt install pandoc texlive-xetex texlive-fonts-recommended lmodern fonts-dejavu
```

Prerequisites (fallback engine, used only if the above isn't available):

```console
sudo apt install wkhtmltopdf python3-markdown
```

---

## What the Script Does

### Step 1 – Prepare input
Verifies the input file exists. Extracts a title from the first `# ` (H1) heading in the file, falling back to the filename if there's no H1. Computes today's date for the PDF's date field. Copies the input into a temp file with all horizontal-rule lines (`---`) stripped — the section headings already provide visual separation, so keeping both was visually redundant.

### Step 2 – Primary engine: pandoc + xelatex
Used if both `pandoc` and `xelatex` are on `PATH`. Writes a LaTeX header (`hdr.tex`) that: defines muted/rule colors matching the site's palette, sets section headings to small-caps-style letter-spaced uppercase via `fontspec` (chosen over microtype letterspacing, which doesn't work under XeTeX), configures code blocks to wrap long lines instead of overflowing the margin, and sets tighter paragraph spacing. Runs `pandoc` with `--shift-heading-level-by=-1` (so the markdown's `#` becomes the document title and `##` becomes styled sections), A4 geometry with 22mm margins, "TeX Gyre Pagella" as the main serif font (the closest offline equivalent to the site's Cormorant Garamond, which requires the internet) and "DejaVu Sans Mono" for code. On success, prints the output path and page count (via `pdfinfo`) and exits.

### Step 3 – Fallback engine: wkhtmltopdf
Only reached if pandoc/xelatex is unavailable or the pandoc run itself failed (its stderr is shown before falling back). Requires `wkhtmltopdf` and the Python `markdown` package. Converts the markdown to HTML via a small inline Python script (with `tables`, `fenced_code`, `attr_list`, `sane_lists` extensions), wraps it in an inline stylesheet approximating the same look (serif body text, uppercase letter-spaced headings, styled tables/code blocks), and renders it with `wkhtmltopdf` at A4 size. Prints the output path with a note that this engine produces no page numbers.

---

## Notes

- **Not idempotent in a meaningful sense but safe to re-run:** it always overwrites the output file; there's no partial-output risk since generation happens in a temp directory (`mktemp -d`, cleaned up via `trap ... EXIT`) before anything is written to the final path.
- **Fallback quality gap:** the wkhtmltopdf path explicitly does not produce page numbers ("ingen sidetal paa upatchet qt" — no page numbers on an unpatched Qt build) and doesn't use the same fonts, so the two engines don't produce visually identical output.
- Font choice is a deliberate compromise: the site's actual font (Cormorant Garamond, via Google Fonts) needs network access at render time, so this script substitutes "TeX Gyre Pagella"/"DejaVu Sans Mono", both shipped with `texlive-fonts-recommended`/`fonts-dejavu`, for offline rendering.
- Console output and comments in the script are in Danish; this document is in English.
