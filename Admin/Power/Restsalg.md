# Restsalg

Scrapes Power.dk's clearance campaign ("restsalg", PC, tablet and gaming) in the categories laptops, desktop PCs, business desktop PCs and RePOWER laptops. Each run appends all products to a CSV file, shows how many products there are per category, and shows which products are new since the last run.

It is the same script as [`Outlet.py`](Outlet.md), but fetches a campaign instead of outlet stores.

---

## Usage

```bash
python3 ~/RaspberryPi/Admin/Power/Restsalg.py
```

The output files are written next to the script, wherever it is run from.

Prerequisites:

- **No sudo.**
- **Python 3 with `requests`:** `sudo apt install python3-requests`. If it is missing, the script says so and exits with code `1`.
- Internet access to `www.power.dk`.

### Configuration (top of script)

| Variable | Default | Description |
| --- | --- | --- |
| `CAMPAIGN_ID` | `24026` | Power.dk campaign ID (`cmp`) |
| `FILTER_CONFIG` | `9438` | Filter configuration (`fc`) |
| `CATEGORY_FILTER` | `BasicCategories<>1341<>1342<>1489<>10186` | Category filter sent to the API |
| `CATEGORIES` | `1341` Bærbar PC, `1342` Stationær PC, `1489` Erhvervs stationær PC, `10186` RePOWER bærbar PC | Names used in the output |
| `PAGE_SIZE` | `100` | Products per API call |
| `OUTPUT_CSV` | `power_restsalg_varer.csv` in the script's folder | CSV file that every run appends to |
| `SEEN_FILE` | `power_restsalg_set.json` in the script's folder | IDs of all products seen before |

---

## What the Script Does

### Step 1 – Fetch products

Calls Power.dk's product list API (`/api/v2/productlists`) with the campaign, filter configuration and category filter, 100 products at a time, until the last page.

### Step 2 – Save

Appends all products to `OUTPUT_CSV` (`;`-separated, UTF-8 with BOM) and adds their IDs to `SEEN_FILE`.

### Step 3 – Print

Prints the total, the number of new products and the number of products per category, then a table of all products and a table of the new ones.

---

## Notes

- **The campaign ID is hardcoded.** When Power.dk ends or replaces the campaign, the script finds no products ("Ingen produkter fundet"). Find the new `cmp` and `fc` values in the browser's network tab on the campaign page.
- **`CATEGORY_FILTER` and `CATEGORIES` must be kept in step by hand.** Unlike `Outlet.py`, the filter is not built from `CATEGORIES`.
- The other notes for [`Outlet.py`](Outlet.md) apply here too: output files next to the script and not in git, the CSV grows on every run, a network error saves what was fetched, the exit code is `0` unless `requests` is missing, and the cron example is at the bottom of the file.
- Output is in Danish.
