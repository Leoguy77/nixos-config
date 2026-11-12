# asuna (formerly `host1`) — netcup server, migrating Debian → NixOS

Not a buildable host yet. This directory has **no `default.nix`** on purpose: the
flake auto-discovers every `hosts/*/default.nix` as a system, and asuna has no
`hardware-configuration.nix`, so it cannot build. Rename `README.md` → `default.nix`
once that file exists.

## What already lives here

`dns.nix` — asuna's records in the `lsinfra.de` zone. Imported by
`hosts/mail/default.nix`, because `mail` is the host that publishes the zone.
Moving these records here keeps them next to the machine they belong to while
there is only one publisher.

Every value is secret-backed (`host1_ipv4`, `host1_ipv6` in
`secrets/secrets.sops.yaml`). This repository is public, and those addresses are
behind Cloudflare — they must never appear in a tracked file.

## What is still missing

- `hardware-configuration.nix` — run `nixos-generate-config` on the box
- an age key for asuna in `.sops.yaml` under `keys:`, added after the first boot
  gives us `/etc/ssh/ssh_host_ed25519_key`
- a real config: `imports` of `mylib.scanPaths ../../modules/nixos` plus whatever
  services it actually runs (currently: attic binary cache, meshview, pelican)

## Current addresses

| | |
|---|---|
| IPv4 | in sops as `host1_ipv4` |
| IPv6 | in sops as `host1_ipv6` |
| PTR | `host1.aero-gaming.de` |
| provider | netcup RS 2000 G11 SE, id `v2202505277042346043` |

Records it owns: apex `A`, `meshview`, `nix-cache` (`A` + `AAAA`), `pelican`,
`wing`. See `./dns.nix`.
