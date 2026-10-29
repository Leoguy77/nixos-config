# Secrets Management with sops-nix

## 🔐 Overview

This configuration uses **[sops](https://github.com/getsops/sops)** + **[sops-nix](https://github.com/Mic92/sops-nix)** for encrypted secrets. Secrets are encrypted with an **age** key and decrypted at activation into runtime paths (home-level and system-level), so plaintext never lands in the Nix store or git.

Migrated from agenix in [this change]; the agenix `.age` files and modules are gone.

## 📁 Structure

```
secrets/
├── secrets.sops.yaml        # The single encrypted secrets file (safe to commit)
.sops.yaml                   # sops creation rules (age recipient) — safe to commit
modules/home/sops.nix        # home-manager sops: writes ~/.pi/agent/mcp.json
modules/nixos/sops.nix       # NixOS sops: wg0 private key -> /run/secrets/wg0_private_key
~/.config/sops/age/keys.txt  # Decryption identity — DO NOT COMMIT, BACK IT UP
```

| Secret | Consumed by | Decrypted to |
|---|---|---|
| `pi_mcp_json` | pi (`~/.pi/agent/mcp.json`) | `~/.pi/agent/mcp.json` |
| `wg0_private_key` | flipdot WireGuard (NM) | `/run/secrets/wg0_private_key` |

## 🔑 The age identity

sops encrypts to an age public key; sops-nix decrypts with the matching private key file:

```bash
age-keygen -o ~/.config/sops/age/keys.txt
age-keygen -y ~/.config/sops/age/keys.txt   # the age1… public key
```

**Back up `~/.config/sops/age/keys.txt`.** Losing it means losing every secret.
Both the home and NixOS sops modules point `age.keyFile` at this file.

> Why age, not SSH keys? age cannot use SSH **host** keys, and the age + agenix
> builds on this box have no SSH-key support at all — which is why the earlier
> ssh-to-age attempt failed. An age key is the reliable, universal path.

## ➕ Adding a secret

1. Write the plaintext key(s), then encrypt:

```bash
cd ~/Desktop/Code/nixos-config
sops secrets/secrets.sops.yaml            # opens $EDITOR on decrypted copy
```

2. (or set a single key non-interactively:)
```bash
sops --set '["mykey"] "myvalue"' secrets/secrets.sops.yaml
```

3. Declare it in the relevant sops module, e.g. for a system (root) secret:

```nix
# modules/nixos/sops.nix
sops.secrets."mykey" = { };
```

and consume it at `config.sops.secrets."mykey".path`.

## 🔎 Reading a secret

```bash
sops -d secrets/secrets.sops.yaml         # prints all decrypted values
```

## 🔁 Editing / rotating / re-encrypting

- **Change a value:** `sops secrets/secrets.sops.yaml`, edit, save.
- **Add a recipient (new machine/key):** add the age pubkey to the
  `keys` / `creation_rules` in `.sops.yaml`, then re-encrypt the file with
  `sops --rotate` (or `sops updatekeys`). Existing `data` values re-encrypt to
  the new key set.

## ⚠️ Important notes

1. **Only the encrypted `secrets.sops.yaml` should be committed** — never a
   plaintext copy, never the age private key.
2. **Backup** `~/.config/sops/age/keys.txt` and the sops file.
3. **Apply changes:** `home-manager switch --flake .#leoguy77@kirito` for
   home secrets; `sudo nixos-rebuild switch --flake .` for system secrets.
4. `sops.nix` hardcodes `/home/leoguy77/.config/sops/age/keys.txt` — fine on
   kirito; a different host needs its own key path.

## 🛠️ Commands

| Action | Command |
|---|---|
| Encrypt in place | `sops --encrypt --in-place secrets/secrets.sops.yaml` |
| Decrypt to stdout | `sops -d secrets/secrets.sops.yaml` |
| Edit (decrypt→edit→encrypt) | `sops secrets/secrets.sops.yaml` |
| Add a key | `sops --set '["k"] "v"' secrets/secrets.sops.yaml` |
| Rotate/re-encrypt | `sops --rotate secrets/secrets.sops.yaml` |

## 🔗 Resources

- [sops](https://github.com/getsops/sops)
- [sops-nix](https://github.com/Mic92/sops-nix)
- [age](https://age-encryption.org/)
