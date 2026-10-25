# Outlet

Scrapes the outlet products from Power.dk in two stores (POWER Lyngby and POWER Vesterport) in the categories mobile phones, laptops and desktop PCs. Each run appends all products to a CSV file and shows which products are new since the last run.

[`Restsalg.py`](Restsalg.md) is the same script for Power.dk's clearance campaign.

---

## Usage

```bash
cd ~/RaspberryPi/Admin/Power    # the output files are written to the current folder
python3 Outlet.py
```

Prerequisites:

- **No sudo.**
- **Python 3 with `requests`.** On Raspberry Pi OS / Debian 12 and newer, install it with `sudo apt install python3-requests`. The script's own hint, `pip install requests`, is refused there ("externally-managed-environment") unless you use a virtual environment.
- Internet access to `www.power.dk`.

### Configuration (top of script)

| Variable | Default | Description |
| --- | --- | --- |
| `OUTLET_IDS` | `3818, 3829` | Outlet store IDs (3818 = POWER Lyngby, 3829 = POWER Vesterport) |
| `CATEGORIES` | `1100` Mobiltelefoner, `1341` Bærbar PC, `1342` Stationær PC | Power.dk category IDs and the names used in the output |
| `PAGE_SIZE` | `100` | Products per API call |
| `OUTPUT_CSV` | `power_outlet_varer.csv` | CSV file that every run appends to |
| `SEEN_FILE` | `power_outlet_set.json` | IDs of all products seen before |

---

## What the Script Does

### Step 1 – Fetch products

Calls Power.dk's product list API (`/api/v2/productlists`) with a filter for the outlet stores and categories, 100 products at a time, until the last page. Each product is mapped to: date, ID, name, brand, category, price, previous price, saving in kr and %, stock and URL.

### Step 2 – Save

Appends all products to `OUTPUT_CSV` (`;`-separated, UTF-8 with BOM so Excel shows æøå correctly; header only when the file is new) and adds their IDs to `SEEN_FILE`.

### Step 3 – Print

Prints the total and the number of new products, then a table of all products and a table of the products that were not in `SEEN_FILE` before this run.

---

## Notes

- **The output files are written to the current folder,** not the script's folder. Run it from the `Power` folder, or the files end up somewhere else (for example `$HOME` when run from cron).
- **The CSV grows on every run,** because all products are appended each time, not only the new ones. Use the `dato` column to filter.
- **The output files are not in git** (see `.gitignore`); they are generated on each run.
- **A network error stops the fetch,** and whatever was fetched up to then is saved. There is no exit code for errors; the script always exits `0`.
- **The API is not a public one.** The parameters were found from the website's own calls and can stop working if Power.dk changes the site.
- The docstring calls the file `power_outlet_scraper.py` and the bottom of the file describes daily runs with Windows Task Scheduler. On the Pi, use cron instead, for example `0 8 * * * cd ~/RaspberryPi/Admin/Power && python3 Outlet.py >> outlet.log 2>&1`.
- Output is in Danish.
