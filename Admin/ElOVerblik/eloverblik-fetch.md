# eloverblik-fetch

Fetches electricity consumption from Eloverblik (Energinet DataHub, Customer API) and prints it as a table, or estimates the meter's current reading from a known reading. Runs on the `Admin` Raspberry Pi, but works on any Linux machine with `bash`, `curl` and `jq`.

---

## Usage

```bash
./eloverblik-fetch.sh                          # yesterday, per hour
./eloverblik-fetch.sh -f 2026-10-01 -a Day     # per day from 1 October until today
./eloverblik-fetch.sh -f 2021-01-01 -a Year    # total per year since 2021
./eloverblik-fetch.sh -r 41234.5@2026-01-01    # estimated meter reading now
./eloverblik-fetch.sh -r 44107.6@"2026-10-25 07:30"
./eloverblik-fetch.sh -l                       # list metering points on the account
```

| Option | Meaning |
| --- | --- |
| `-m ID` | Metering point ID (18 digits). Default: `ELO_METERING_POINT`, or the first consumption point (`E17`) on the account. |
| `-f DATE` | From date `YYYY-MM-DD` (default: yesterday). |
| `-t DATE` | To date `YYYY-MM-DD`, exclusive (default: today). |
| `-a AGG` | `Actual`, `Quarter`, `Hour`, `Day`, `Month` or `Year` (default `Hour`). |
| `-r READING@DATE` | Estimate the meter reading from a known reading at the start of `DATE` (00:00), or at a given time with `READING@"DATE HH:MM"`. Sets the from date and the aggregation itself. |
| `-j` | Print raw JSON instead of a table. |
| `-l` | List metering points on the account and exit. |
| `-h` | Help. |

Prerequisites:

- **No sudo.** Everything is in the user's home folder.
- **Packages:** `curl` (7.55 or newer, for headers from stdin) and `jq`, both checked at startup with an `apt install` hint. `column` (package `bsdextrautils`) is optional and only lines up the table.
- A **refresh token** from eloverblik.dk → profile → Datadeling, saved in `~/.eloverblik_token` with `chmod 600`.

### Configuration (environment variables)

| Variable | Default | Description |
| --- | --- | --- |
| `ELO_TOKEN_FILE` | `~/.eloverblik_token` | File with the refresh token |
| `ELO_METERING_POINT` | empty | Default metering point |
| `ELO_API` | `https://api.eloverblik.dk/customerapi/api` | API base URL |
| `TZ` | `Europe/Copenhagen` | Time zone for the printed times |
| `XDG_CACHE_HOME` | `~/.cache` | The access token is cached in `$XDG_CACHE_HOME/eloverblik/` |

---

## What the Script Does

### Step 1 – Access token

The refresh token is exchanged for a short-lived access token (valid 24 hours), which is cached for 23 hours in `~/.cache/eloverblik/access_token` (folder `700`, file `600`) to save API calls. Tokens are passed to `curl` on stdin, so they never show up in `ps` or the shell history. A `401` deletes the cached token, so the next run gets a new one.

### Step 2 – Metering point

Uses `-m` or `ELO_METERING_POINT`; otherwise it fetches the account's metering points and picks the first consumption point (`E17`), or the first point at all.

### Step 3 – Time series

Calls `gettimeseries` once per calendar year in the period (the API allows at most 730 days per call). `429`/`503` answers are retried up to three times with 30 seconds between. Errors reported per metering point inside the answer stop the script.

Timestamps are calculated from the period start in UTC plus position × resolution, so 23- and 25-hour days at daylight saving changes come out right (02:00 appears twice when going to winter time).

### Step 4 – Output

- **Table:** time, kWh and quality per row, followed by the total. Quality `A04` = measured, `A03` = estimated.
- **Meter reading (`-r`):** known reading + consumption since then. The hour of the reading only counts for the part after the reading (07:30 → half of 07:00–08:00). Warns if the period contains values that are not measured (`A04`).

### Exit codes

| Code | Meaning |
| --- | --- |
| `0` | OK |
| `1` | Missing tool or token, API error, invalid date/metering point, or no data for the period |
| `2` | Unknown option |

---

## Notes

- **Eloverblik is about one day behind.** Data for today is not available yet, and `-r` with today's date stops with a message to try again tomorrow. The estimated reading is up to the last hour/day with data, not up to now.
- **API limits:** data for the last 5 years plus the current year, 2 token calls and 120 calls in total per minute per IP.
- The script does not check the permissions on the token file; keep it at `chmod 600`.
- Comments and output are in Danish.
