# ElOVerblik Overview

Electricity consumption from Eloverblik (Energinet DataHub). Each script has a matching `.md` file (same base name).

---

| Script | Doc | Summary |
| --- | --- | --- |
| `eloverblik.sh` | [eloverblik.md](eloverblik.md) | Fetches consumption per quarter/hour/day/month/year for a metering point and prints it as a table or JSON, or estimates the meter's current reading from a known reading. |

---

## Notes

- **Run as a normal user, no sudo.** Needs `curl` and `jq`; `column` (`bsdextrautils`) is optional.
- **Secret:** the refresh token lives in `~/.eloverblik_token` (outside the repo) and the cached access token in `~/.cache/eloverblik/`. Neither belongs in git.
