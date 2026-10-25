"""
╔══════════════════════════════════════════════════════╗
║         Power.dk Outlet Scraper                     ║
╠══════════════════════════════════════════════════════╣
║  INSTALLATION (kun første gang):                    ║
║    pip install requests                              ║
║                                                      ║
║  Kør scriptet:                                       ║
║    python power_outlet_scraper.py                   ║
╚══════════════════════════════════════════════════════╝

Butikker  : POWER Lyngby + POWER Vesterport
Kategorier: Mobiltelefoner, Bærbar PC, Stationær PC
"""

import json, csv, os
from datetime import datetime

try:
    import requests
except ImportError:
    print("FEJL: Kør:  pip install requests")
    exit(1)

# ═══════════════════════════════════════════════════════
#  KONFIGURATION
# ═══════════════════════════════════════════════════════

OUTLET_IDS = [3818, 3829]
# 3818 = POWER Lyngby
# 3829 = POWER Vesterport

CATEGORIES = {
    1100: "Mobiltelefoner",
    1341: "Bærbar PC",
    1342: "Stationær PC",
}

PAGE_SIZE  = 100
OUTPUT_CSV = "power_outlet_varer.csv"
SEEN_FILE  = "power_outlet_set.json"

# ═══════════════════════════════════════════════════════
#  HJÆLPEFUNKTIONER
# ═══════════════════════════════════════════════════════

def load_seen_ids():
    if os.path.exists(SEEN_FILE):
        with open(SEEN_FILE, "r", encoding="utf-8") as f:
            return set(str(x) for x in json.load(f))
    return set()

def save_seen_ids(ids):
    with open(SEEN_FILE, "w", encoding="utf-8") as f:
        json.dump(list(ids), f)

def save_to_csv(products):
    fieldnames = ["dato","id","navn","mærke","kategori","pris","førpris","besparelse_kr","besparelse_pct","på_lager","url"]
    file_exists = os.path.exists(OUTPUT_CSV)
    with open(OUTPUT_CSV, "a", newline="", encoding="utf-8-sig") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames, delimiter=";")
        if not file_exists:
            writer.writeheader()
        writer.writerows(products)

def beregn_besparelse(pris, foerpris):
    try:
        if foerpris and float(foerpris) > float(pris) > 0:
            kr  = float(foerpris) - float(pris)
            pct = round((kr / float(foerpris)) * 100)
            return int(kr), pct
    except (TypeError, ValueError):
        pass
    return 0, 0

def map_produkt(p):
    dato     = datetime.now().strftime("%Y-%m-%d")
    pris     = p.get("price") or 0
    foerpris = p.get("previousPrice") or p.get("originalPrice") or p.get("recommendedPrice") or 0
    spar_kr, spar_pct = beregn_besparelse(pris, foerpris)
    url_key  = p.get("linkUrl") or p.get("urlKey") or ""
    if url_key and not url_key.startswith("http"):
        url_key = "https://www.power.dk" + url_key
    return {
        "dato":           dato,
        "id":             str(p.get("productId", "")),
        "navn":           p.get("title") or p.get("productName") or "",
        "mærke":          p.get("manufacturerName", ""),
        "kategori":       CATEGORIES.get(p.get("categoryId")) or p.get("categoryName", ""),
        "pris":           f"{pris} kr" if pris else "",
        "førpris":        f"{foerpris} kr" if foerpris else "",
        "besparelse_kr":  f"{spar_kr} kr" if spar_kr else "",
        "besparelse_pct": f"{spar_pct}%" if spar_pct else "",
        "på_lager":       str(p.get("stockCount") or 0),
        "url":            url_key,
    }

# ═══════════════════════════════════════════════════════
#  HENT PRODUKTER
# ═══════════════════════════════════════════════════════

def fetch_all_products():
    filter_str = (
        "OutletStoreId" + "".join(f"<>{oid}" for oid in OUTLET_IDS)
        + "||BasicCategories" + "".join(f"<>{cid}" for cid in CATEGORIES.keys())
    )
    session = requests.Session()
    session.headers.update({
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/124.0.0.0 Safari/537.36",
        "Accept": "application/json",
        "Referer": "https://www.power.dk/outlet-hovedstaden/",
    })

    all_products = []
    from_index = 0

    print(f"[{datetime.now():%Y-%m-%d %H:%M}] Henter outlet-produkter...")
    print(f"  Butikker  : POWER Lyngby + POWER Vesterport")
    print(f"  Kategorier: {', '.join(CATEGORIES.values())}")
    print()

    while True:
        try:
            resp = session.get(
                "https://www.power.dk/api/v2/productlists",
                params={"size": PAGE_SIZE, "s": 5, "from": from_index,
                        "o": "true", "cd": "false", "f": filter_str},
                timeout=20
            )
            resp.raise_for_status()
            data = resp.json()
        except requests.exceptions.ConnectionError:
            print("  FEJL: Ingen internetforbindelse."); break
        except Exception as e:
            print(f"  FEJL: {e}"); break

        products = data.get("products", [])
        total    = data.get("totalProductCount", 0)
        is_last  = data.get("isLastPage", True)
        print(f"  Hentet {len(all_products) + len(products)} / {total} produkter...")

        all_products.extend([map_produkt(p) for p in products])

        if is_last or not products:
            break
        from_index += PAGE_SIZE

    return all_products

# ═══════════════════════════════════════════════════════
#  UDSKRIV TABEL
# ═══════════════════════════════════════════════════════

def print_tabel(products, titel):
    print(f"\n  {titel} ({len(products)} stk):")
    print(f"  {'Kat.':<14}{'Mærke':<14}{'Navn':<38}{'Pris':>9}{'Førpris':>9}{'Spar':>6}")
    print("  " + "-" * 92)
    for p in products:
        print(f"  {p['kategori']:<14}{p['mærke']:<14}{p['navn'][:36]:<38}{p['pris']:>9}{p['førpris']:>9}{p['besparelse_pct']:>6}")

# ═══════════════════════════════════════════════════════
#  HOVEDPROGRAM
# ═══════════════════════════════════════════════════════

def main():
    print()
    print("=" * 60)
    print("  Power.dk Outlet Scraper")
    print(f"  {datetime.now():%Y-%m-%d %H:%M:%S}")
    print("=" * 60)
    print()

    seen_ids = load_seen_ids()
    products = fetch_all_products()

    if not products:
        print("\n  Ingen produkter fundet.")
        return

    nye = [p for p in products if p["id"] and p["id"] not in seen_ids]
    alle_ids = {p["id"] for p in products if p["id"]}

    save_to_csv(products)
    save_seen_ids(seen_ids | alle_ids)

    print()
    print("=" * 60)
    print(f"  Fundet i alt : {len(products)} varer")
    print(f"  NYE varer    : {len(nye)}")
    print(f"  Gemt i       : {OUTPUT_CSV}")
    print("=" * 60)

    print_tabel(products, "Alle varer")

    if nye:
        print_tabel(nye, "NYE varer siden sidst")
    else:
        print("\n  Ingen nye varer siden sidst.")


if __name__ == "__main__":
    main()

# ═══════════════════════════════════════════════════════
#  AUTOMATISK DAGLIG KØRSEL – WINDOWS Task Scheduler
# ═══════════════════════════════════════════════════════
"""
1. Åbn "Task Scheduler" (søg i Start-menuen)
2. Klik "Create Basic Task"
3. Navn: Power Outlet Scraper
4. Trigger: Daily – f.eks. 08:00
5. Action: Start a program
   Program/script : python
   Add arguments  : C:\\sti\\til\\power_outlet_scraper.py
6. Klik Finish
"""
