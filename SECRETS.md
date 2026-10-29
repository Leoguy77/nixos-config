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

## 🔑 Identities (your real keys)

- **System (root):** host SSH key `/etc/ssh/ssh_host_ed25519_key` via
  `sops.age.sshKeyPaths`. sops-nix converts it to an age identity internally.
- **User (home):** your ssh-RSA key `~/.ssh/GPG` via `sops.gnupg.sshKeyPaths`.
  sops-nix converts it to a **PGP** key with `ssh-to-pgp` (RSA-only) and
  decrypts with GPG. (`~/.ssh/GPG` is your 1Password "GPG" key exported to a file.)

sops cannot read keys from the SSH agent — it needs the private key as a file.

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
sops -d secrets/secrets.sops.yaml    # needs gpg + your PGP key (see above)
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
