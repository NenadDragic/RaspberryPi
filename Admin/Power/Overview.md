# Power Overview

Scrapers for Power.dk that track outlet and clearance products and show what is new since the last run. Each script has a matching `.md` file (same base name).

---

| Script | Doc | Summary |
| --- | --- | --- |
| `Outlet.py` | [Outlet.md](Outlet.md) | Outlet products in POWER Lyngby and POWER Vesterport (mobile phones, laptops, desktop PCs). Output: `power_outlet_varer.csv`, `power_outlet_set.json`. |
| `Restsalg.py` | [Restsalg.md](Restsalg.md) | Products in the clearance campaign "PC, tablet og gaming" (laptops, desktop PCs, business PCs, RePOWER laptops), with a count per category. Output: `power_restsalg_varer.csv`, `power_restsalg_set.json`. |

---

## Notes

- **Run as a normal user, no sudo.** Needs Python 3 and `requests` (`sudo apt install python3-requests` on Raspberry Pi OS).
- **Run from this folder.** The output files are written to the current folder, and they are kept out of git by `.gitignore`.
- The two scripts share most of their code (copied, not imported), so a fix in one usually belongs in the other too.
