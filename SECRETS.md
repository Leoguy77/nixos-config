# Secrets Management with sops-nix

## 🔐 Overview

This configuration uses **[sops](https://github.com/getsops/sops)** + **[sops-nix](https://github.com/Mic92/sops-nix)** for encrypted secrets. It decrypts from **your real keys** — the machine's SSH host key (for system secrets) and your personal ssh-RSA key `~/.ssh/GPG` (for user/home secrets) — no throwaway age keys.

Migrated from agenix.

## 📁 Structure

```
secrets/
└── secrets.sops.yaml        # encrypted secrets (committed)
.sops.yaml                   # creation rules: host-age recipient + your PGP fingerprint
modules/nixos/sops.nix       # system secrets  -> host ssh key
modules/home/sops.nix        # home secrets    -> ~/.ssh/GPG (ssh-to-pgp)
```

| Secret | Consumed by | Identity | Decrypted to |
|---|---|---|---|
| `wg0_private_key` | flipdot WireGuard (NM) | host ssh key | `/run/secrets/wg0_private_key` |
| `pi_mcp_json` | pi (`~/.pi/agent/mcp.json`) | `~/.ssh/GPG` | `~/.pi/agent/mcp.json` |
| `tailscale_oauth_client_id` / `_secret` | `scripts/deploy.sh` (host-side only) | `~/.ssh/GPG` | never — read by deploy.sh |
| `cloudflare_dns_token` | `modules/nixos/dns.nix` (`dns-sync.service`) | host ssh key | `/run/secrets/cloudflare_dns_token` |

The Cloudflare token needs `Zone.DNS:Edit` on `lsinfra.de` only — not `Zone:Read`,
not a global API key. Rspamd-style scoping: if it leaks it can rewrite one zone.
Until a real token is in place the key holds `""` so the build manifest validates;
`dns-sync` then fails at runtime with Cloudflare's auth error, which is visible in
`journalctl -u dns-sync` but breaks nothing else.

The tailscale pair is not a NixOS secret: no host module consumes it. It exists
so `deploy.sh` can mint a short-lived initrd auth key instead of keeping a
90-day one per host. See `hosts/mail/README.md` → *No auth key to create*.

An OAuth client secret can mint auth keys for the whole tailnet. It is scoped
to `Devices → Keys → Auth Keys` write only, and should be revoked at
<https://login.tailscale.com/admin/settings/oauth> if it ever leaks.

## 🔑 Identities (your real keys)

- **System (root):** host SSH key `/etc/ssh/ssh_host_ed25519_key` via
  `sops.age.sshKeyPaths`. sops-nix converts it to an age identity internally.
- **User (home):** your ssh-RSA key `~/.ssh/GPG` via `sops.gnupg.sshKeyPaths`.
  sops-nix converts it to a **PGP** key with `ssh-to-pgp` (RSA-only) and
  decrypts with GPG. (`~/.ssh/GPG` is your 1Password "GPG" key exported to a file.)

sops cannot read keys from the SSH agent — it needs the private key as a file.

### The recipients

`.sops.yaml` has one PGP recipient (yours) plus one age recipient per machine:

| Recipient | Read by | Covers |
|---|---|---|
| `age1pr3…` (kirito) | kirito's ssh key, converted by sops-nix | boot, `nixos-rebuild`, autoUpgrade |
| `age1m0d…` (mail) | mail's ssh key, converted by sops-nix | the same, on that box |
| PGP `5C0B…` | `~/.ssh/GPG` | home-manager secrets, and the CLI |

A machine's age recipient is derived from its SSH host key
(`/etc/ssh/ssh_host_ed25519_key`, the age identity sops-nix uses at boot), so
only the derived public `age1…` is stored here — never the private half.

`scripts/deploy.sh` mints that keypair on the control machine, derives the
recipient, rewrites the host's anchor in `.sops.yaml`, runs `sops updatekeys`,
and seeds the private key into the install via `nixos-anywhere --extra-files`.
Its only copies are then a `mktemp` dir during the run (removed by the EXIT
trap) and the machine itself. So a new host needs no manual enrolment step, and
a reinstall re-enrols automatically. If the install fails, `deploy.sh` restores
both sops files from backups on the way out.

The one step that is manual: commit the two rotated files afterwards, so CI and
other machines see ciphertext the box can actually read.

Keep host recipients in `age1…` form. sops also accepts an `ssh-ed25519
AAAA…` recipient, but that is a *different* scheme: `sops-install-secrets` fails
to decrypt ssh-form recipients on both `age.sshKeyPaths` and `age.sshKeyFile`,
so it would break activation at boot.

### Decrypting from the CLI

Neither identity lives in a form `sops` can read on its own, so materialize one:

```bash
# the PGP key derived from ~/.ssh/GPG, one-time (ssh-to-pgp is RSA-only)
nix develop .# --command ssh-to-pgp -private-key -i ~/.ssh/GPG | gpg --batch --import
sops secrets/secrets.sops.yaml
```

`~/.ssh/GPG` is your 1Password "GPG" key exported to a file. Note this derives a
*PGP* keyring — a plain `age` CLI key (the old `~/.config/sops/age/keys.txt`
approach) does **not** open this file any more, because both recipients are
age/PGP-native. Also note the `gnupg` build must be the full one (`pkgs.gnupg`,
which ships `gpg-agent`); a stub build fails with `can't connect to the gpg-agent`.

## 🔑 The PGP side of your key

`sops.gnupg.sshKeyPaths` converts `~/.ssh/GPG` to a PGP key whose fingerprint is:

```
5C0B8600A5177230B45A66EBF7169CB8EBBAF028
```

It's a `pgp:` recipient in `.sops.yaml` alongside the host-age recipient, so the
file unlocks with either identity.

## ➕ Add / edit a secret (needs gpg + your PGP key)

Because the file is encrypted to a PGP recipient, editing with `sops` needs
your PGP public key in a gpg keyring. One-time setup:

```bash
# regenerate & import the PGP key derived from your ssh-RSA key
nix develop .# --command ssh-to-pgp -private-key -i ~/.ssh/GPG | gpg --batch --import
```

Then edit as usual:

```bash
cd ~/Desktop/Code/nixos-config
sops secrets/secrets.sops.yaml       # opens $EDITOR on the decrypted file
```

sops re-encrypts to the same recipients (host-age + your PGP fingerprint).

## 🔎 Reading / verifying

```bash
sops -d secrets/secrets.sops.yaml    # via the PGP keyring above
```

## ⚠️ Important notes

1. **Only the encrypted `secrets.sops.yaml` is committed** — never a plaintext
   copy, never `~/.ssh/GPG` or its private key.
2. **Back up `~/.ssh/GPG` / `~/.ssh/GPG.pub`** (from 1Password) — losing them
   loses home-secret decryption.
3. **Apply:** `home-manager switch --flake .#leoguy77@kirito` (home),
   `sudo nixos-rebuild switch --flake .` (system).
4. `sops.nix` hardcodes `/home/leoguy77/.ssh/GPG` — a different host needs its
   own user key path.

## 🔗 Resources

- [sops](https://github.com/getsops/sops)
- [sops-nix](https://github.com/Mic92/sops-nix)
- [age](https://age-encryption.org/)
- [ssh-to-pgp](https://github.com/Mic92/ssh-to-pgp)
