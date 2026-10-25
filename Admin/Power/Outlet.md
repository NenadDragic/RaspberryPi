# Outlet

Scrapes the outlet products from Power.dk in two stores (POWER Lyngby and POWER Vesterport) in the categories mobile phones, laptops and desktop PCs. Each run appends all products to a CSV file and shows which products are new since the last run.

[`Restsalg.py`](Restsalg.md) is the same script for Power.dk's clearance campaign.

---

## Usage

```bash
python3 ~/RaspberryPi/Admin/Power/Outlet.py
```

The output files are written next to the script, wherever it is run from.

Prerequisites:

- **No sudo.**
- **Python 3 with `requests`:** `sudo apt install python3-requests`. If it is missing, the script says so and exits with code `1`. (`pip install requests` is refused on Raspberry Pi OS / Debian 12 and newer outside a virtual environment.)
- Internet access to `www.power.dk`.

### Configuration (top of script)

| Variable | Default | Description |
| --- | --- | --- |
| `OUTLET_IDS` | `3818, 3829` | Outlet store IDs (3818 = POWER Lyngby, 3829 = POWER Vesterport) |
| `CATEGORIES` | `1100` Mobiltelefoner, `1341` Bærbar PC, `1342` Stationær PC | Power.dk category IDs and the names used in the output |
| `PAGE_SIZE` | `100` | Products per API call |
| `OUTPUT_CSV` | `power_outlet_varer.csv` in the script's folder | CSV file that every run appends to |
| `SEEN_FILE` | `power_outlet_set.json` in the script's folder | IDs of all products seen before |

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

- **The CSV grows on every run,** because all products are appended each time, not only the new ones. Use the `dato` column to filter.
- **The output files and cron logs are not in git** (see `.gitignore`); they are generated on each run.
- **A network error stops the fetch,** and whatever was fetched up to then is saved. Apart from a missing `requests`, the script always exits `0`.
- **The API is not a public one.** The parameters were found from the website's own calls and can stop working if Power.dk changes the site.
- **Daily runs:** the bottom of the file has a cron example, for example `0 8 * * * python3 /home/<user>/RaspberryPi/Admin/Power/Outlet.py >> /home/<user>/RaspberryPi/Admin/Power/outlet.log 2>&1`.
- Output is in Danish.
