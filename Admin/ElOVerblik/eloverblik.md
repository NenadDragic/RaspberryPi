# eloverblik

Runs [`eloverblik-fetch.sh`](eloverblik-fetch.md) `-r` from cron and appends the estimated meter reading to a CSV file. A new line is only added when Eloverblik has new or corrected data, so a log of the meter reading builds up over time without duplicates.

---

## Usage

```bash
./eloverblik.sh
```

No options; everything is set with environment variables or the `BASE` line at the top of the script. Log messages go to stdout with a timestamp and a level (`INFO`, `OK`, `ADVARSEL`, `FEJL`), so cron can append them to a log file:

```cron
# Eloverblik: estimated meter reading - every hour at xx:17
17 * * * * /bin/bash /home/<user>/RaspberryPi/Admin/ElOVerblik/eloverblik.sh >> /var/log/eloverblik/cron.log 2>&1
```

The log folder must exist and be writable by the cron user (or point the log somewhere in the home folder).

Prerequisites:

- Everything [`eloverblik-fetch.sh`](eloverblik-fetch.md) needs (`curl`, `jq`, refresh token in `~/.eloverblik_token`).
- `flock` (package `util-linux`, installed by default).
- **No sudo** apart from creating the log folder, if it is under `/var/log`.

### Configuration

| Variable | Default | Description |
| --- | --- | --- |
| `ELO_BASE` | `BASE` in the script | Known meter reading as `READING@YYYY-MM-DD HH:MM`, passed on to `eloverblik-fetch.sh -r` |
| `ELO_SCRIPT` | `eloverblik-fetch.sh` next to this script | The script to run |
| `ELO_DATA_FILE` | `~/eloverblik/taellerstand.csv` | The CSV file |
| `ELO_TOKEN_FILE` | `~/.eloverblik_token` | Only used for the token age warning |

Update `BASE` when you read the meter again (for example at the annual statement). That keeps the calls to Eloverblik small and resets any drift.

---

## What the Script Does

### Step 1 – Environment and lock

Sets `PATH`, `LC_ALL=C.UTF-8` and `TZ=Europe/Copenhagen`, because cron has a minimal environment. Creates the data folder and takes a `flock` on `.taellerstand.lock` in it; if the previous run is still going (Eloverblik hanging), this run logs it and exits.

### Step 2 – Run `eloverblik-fetch.sh -r`

Each stderr line from `eloverblik-fetch.sh` becomes its own log line. If it fails because there is no data yet, that is logged as `INFO` and the run exits `0`; any other failure is logged as `FEJL` and exits `1`.

### Step 3 – Parse and save

Reads the time of the last data hour, the consumption since the reading and the estimated meter reading from the output (works with and without `column` alignment). If `eloverblik-fetch.sh` warned about values that are not measured, the quality is `delvis estimeret`, otherwise `målt`.

The new line is compared with the last line in the CSV (ignoring the run time). Unchanged → `INFO uændret`; changed → the line is appended and logged as `OK`.

### Step 4 – Token age

If the refresh token file is 335 days old or more, an `ADVARSEL` is logged: the token expires after about a year, after which every run fails.

### CSV columns

Semicolon-separated, with a header line when the file is created:

| Column | Meaning |
| --- | --- |
| `kørt` | When the run found the new data |
| `data_til_og_med` | Start of the last hour with data (`23:00` = until 24:00) |
| `forbrug_kwh` | Consumption since the reading in `BASE` |
| `tællerstand_kwh` | `BASE` + `forbrug_kwh` |
| `kvalitet` | `målt`, or `delvis estimeret` if Eloverblik has estimated values in the period |

### Exit codes

| Code | Meaning |
| --- | --- |
| `0` | OK, unchanged, no data yet, or previous run still going |
| `1` | `eloverblik-fetch.sh` missing or failed, output could not be parsed, or the data folder/CSV could not be written |

---

## Notes

- **Eloverblik is about one day behind,** so most hourly runs just log `uændret`.
- **The CSV and log are not in the repo;** they live in `~/eloverblik/` and wherever cron writes the log.
- The parsing depends on the Danish output text of `eloverblik-fetch.sh`. If that text changes, the run fails with `FEJL` and logs the full output.
- Comments and log messages are in Danish.
