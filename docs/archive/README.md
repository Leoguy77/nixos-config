# Archive

Historical notes, kept because they record *why* things look the way they do.
**Nothing here describes the current configuration** — treat every path and
command as likely stale.

| File | What it records |
|---|---|
| `IMPLEMENTATION_SUMMARY.md` | The ryan4yin-inspired restructuring: `vars/`, option-based modules, host separation |
| `IMPROVEMENTS_FROM_RYAN4YIN.md` | The analysis that preceded it — suggested changes and their rationale |
| `IMPLEMENTATION_COMPLETE.md` | The report written when that restructuring finished. Its agenix claim is obsolete: the repo moved to sops-nix (see [../SECRETS.md](../SECRETS.md)) |
| `PI_PACKAGES_FLAKE_PLAN.md` | Design for the separate `pi-packages.nix` flake. Implemented there, not here — this repo only consumes it as a flake input and cache |

Current documentation lives one directory up: [../MODULES.md](../MODULES.md),
[../SECRETS.md](../SECRETS.md), and the top-level [README.md](../../README.md).
