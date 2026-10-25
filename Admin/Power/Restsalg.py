"""
╔══════════════════════════════════════════════════════╗
║         Power.dk Restsalg Scraper                   ║
╠══════════════════════════════════════════════════════╣
║  INSTALLATION (kun første gang):                    ║
║    pip install requests                              ║
║                                                      ║
║  Kør scriptet:                                       ║
║    python power_restsalg_scraper.py                 ║
╚══════════════════════════════════════════════════════╝

Side      : https://www.power.dk/kampagne/restsalg/pc-tablet-og-gaming/
Kategorier: Bærbar PC, Stationær PC, Erhvervs stationær PC, RePOWER bærbar PC
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

# Disse parametre er fundet direkte fra Power.dk's API-kald
CAMPAIGN_ID     = 24026   # cmp=24026
FILTER_CONFIG   = 9438    # fc=9438
CATEGORY_FILTER = "BasicCategories<>1341<>1342<>1489<>10186"

CATEGORIES = {
    1341:  "Bærbar PC",
    1342:  "Stationær PC",
    1489:  "Erhvervs stationær PC",
    10186: "RePOWER bærbar PC",
}

PAGE_SIZE  = 100
OUTPUT_CSV = "power_restsalg_varer.csv"
SEEN_FILE  = "power_restsalg_set.json"

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
    session = requests.Session()
    session.headers.update({
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/124.0.0.0 Safari/537.36",
        "Accept": "application/json",
        "Referer": "https://www.power.dk/kampagne/restsalg/pc-tablet-og-gaming/",
    })

    all_products = []
    from_index = 0

    print(f"[{datetime.now():%Y-%m-%d %H:%M}] Henter restsalgs-produkter...")
    print(f"  Kategorier:")
    for cid, navn in CATEGORIES.items():
        print(f"    {cid:>6}  {navn}")
    print()

    while True:
        try:
            resp = session.get(
                "https://www.power.dk/api/v2/productlists",
                params={
                    "cmp":  CAMPAIGN_ID,
                    "cat":  -1,
                    "fc":   FILTER_CONFIG,
                    "size": PAGE_SIZE,
                    "s":    5,
                    "from": from_index,
                    "o":    "false",
                    "cd":   "false",
                    "f":    CATEGORY_FILTER,
                },
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
    print(f"  {'Kategori':<26}{'Mærke':<14}{'Navn':<36}{'Pris':>9}{'Førpris':>9}{'Spar':>6}")
    print("  " + "-" * 102)
    for p in products:
        print(f"  {p['kategori']:<26}{p['mærke']:<14}{p['navn'][:34]:<36}{p['pris']:>9}{p['førpris']:>9}{p['besparelse_pct']:>6}")

# ═══════════════════════════════════════════════════════
#  HOVEDPROGRAM
# ═══════════════════════════════════════════════════════

def main():
    print()
    print("=" * 65)
    print("  Power.dk Restsalg Scraper – PC, tablet og gaming")
    print(f"  {datetime.now():%Y-%m-%d %H:%M:%S}")
    print("=" * 65)
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

    from collections import Counter
    tæller = Counter(p["kategori"] for p in products)

    print()
    print("=" * 65)
    print(f"  Fundet i alt : {len(products)} varer")
    print(f"  NYE varer    : {len(nye)}")
    print(f"  Gemt i       : {OUTPUT_CSV}")
    print("=" * 65)
    print()
    print("  Fordeling:")
    for kat, antal in sorted(tæller.items(), key=lambda x: -x[1]):
        print(f"    {kat:<30} {antal} varer")

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
3. Navn: Power Restsalg Scraper
4. Trigger: Daily – f.eks. 08:00
5. Action: Start a program
   Program/script : python
   Add arguments  : C:\\sti\\til\\power_restsalg_scraper.py
6. Klik Finish
"""
