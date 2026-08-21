# RaspberryPi

My small projects running on Raspberry Pi's.

---

## Structure

Organized **by device**, not by project or language. Each Raspberry Pi gets its own top-level folder (named after the Pi's hostname), containing everything that runs on that device — bash/python scripts, config files, systemd units, whatever it needs. This mirrors how each Pi is actually deployed and maintained: clone/pull one folder onto one device, rather than assembling its setup from scripts scattered across the language-specific repos (`Bash`, `Python`, etc.).

Current devices:

| Folder | Device |
|---|---|
| [Admin](Admin/) | `Admin` |
| [Flight](Flight/) | `Flight` |
| [GPS](GPS/) | `GPS` |
| [TFA](TFA/) | `TFA` |

If a script is reused across more than one device, it belongs in a shared `shared/` folder at the repo root (not yet created) instead of being duplicated per device — reference or symlink it from the device folders that use it.

### Per-device folder

Each device folder should get its own `README.md` describing what actually runs on it (services, purpose, hardware notes). Scripts follow the same documentation convention as the other script repos (see `Linux-Scripts/Templates/Shell/Template.md`): one `.md` file per script, same base name, describing usage, configuration, and step-by-step behavior — read from the actual code, not the intended behavior.
