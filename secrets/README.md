# Secrets

[sops](https://github.com/getsops/sops) + [sops-nix](https://github.com/Mic92/sops-nix).
One encrypted file, `secrets.sops.yaml`, committed because the repository is
public and encryption is the only thing standing between it and the internet.

## The two identities

| Who | Key | Opens |
|---|---|---|
| A machine | `/persist/etc/ssh/ssh_host_ed25519_key` (kirito) or `/etc/ssh/ssh_host_ed25519_key` (mail) | that host's secrets, at boot and on every rebuild |
| You | the Token2 card (`23CDB62B…`, tap + PIN) | everything, from any machine |

`sops.age.sshKeyPaths` in `modules/nixos/sops.nix` is what makes the first work:
sops-nix converts the SSH host key into an age identity at activation time. Only
the derived **public** `age1…` is in `.sops.yaml`; the private half never leaves
the machine.

The second is an ordinary PGP recipient — the same OpenPGP key that signs your
commits. Its subkeys live on the card and the card will do the decryption, so
`sops -d secrets/secrets.sops.yaml` works anywhere the token is plugged in,
after a tap and a PIN. What the card will **not** do is hand out a copy of the
key: `gpg --export-secret-keys` produces a stub that imports with an empty
`private-keys-v1.d/`. That is the point of a smartcard, and it is why a new host
cannot enrol itself — see below.

`keys/leon.asc` is that key's public half, committed on purpose. A machine with
a fresh keyring needs it: the card carries only the three **subkey** fingerprints
and not the master `23CDB62B…` that `.sops.yaml` names, so without the public
key gpg has nothing to anchor the hierarchy against and fails with
`public key decryption failed: No secret key` — which looks like a wrong token
but is a missing parent key.

## What is where

```
secrets/secrets.sops.yaml   # the ciphertext (committed)
.sops.yaml                  # recipients + creation rules
keys/leon.asc               # your public key, for a fresh keyring
modules/nixos/sops.nix      # declares the per-host secrets, gates them on consumers
```

Everything else under `secrets/` is gitignored (`.gitignore:7-11`) — bootstrap
keys minted during a deploy land there and must never be committed.

## The secrets

Declared per host rather than globally: sops-nix starts a boot service whenever
the secret set is non-empty, so an unused secret makes every host try to decrypt
something it may not be a recipient of, and activation fails — the machine does
not come up. That is why `modules/nixos/sops.nix` wraps each entry in
`lib.mkIf <consumer>.enable`.

| Secret | Consumed by | Host | Lands at |
|---|---|---|---|
| `leoguy77_password_hash` | `modules/nixos/login.nix` | kirito | `/run/secrets-for-users/leoguy77_password_hash` |
| `pi_mcp_json` | `hosts/kirito/default.nix:56` | kirito | `~/.pi/agent/mcp.json` |
| `wg0_private_key` | `modules/nixos/wireguard.nix` | kirito | `/run/secrets/wg0_private_key` |
| `restic_password` | `modules/nixos/backup.nix` | kirito, mail | `/run/secrets/restic_password` |
| `restic_ssh_key` | `modules/nixos/backup.nix` (sftp only) | kirito, mail | `/run/secrets/restic_ssh_key` |
| `dkim_mail_private_key` | `modules/nixos/mail.nix:662` | mail | `/run/secrets/dkim_mail_private_key` |
| `leon_password_hash` | `hosts/mail/default.nix:113` (dovecot) | mail | `/run/secrets/leon_password_hash` |
| `cloudflare_dns_token` | `modules/nixos/dns.nix:227` | mail | `/run/secrets/cloudflare_dns_token` |
| `host1_ipv4` / `host1_ipv6` | `hosts/mail/default.nix:143` | mail | never written — passed to dnscontrol with `-v` |
| `tailscale_oauth_client_id` / `_secret` | `scripts/deploy.sh` only | — | never written — read at deploy time |

The `tailscale` pair has no `.nix` consumer at all: it exists so `deploy.sh` can
mint a short-lived initrd auth key instead of keeping a 90-day one per host. An
OAuth client secret can mint keys for the whole tailnet, so it is scoped to
`Devices → Keys → Auth Keys` write only. Revoke at
<https://login.tailscale.com/admin/settings/oauth> if it leaks.

Two hashes, not one, on purpose: `leon_password_hash` feeds dovecot and is
declared with `restartUnits = [ "dovecot.service" ]`, so sharing it with the
workstation login would make changing a laptop password restart mail.

`host1_*` are the one break in the rule that secrets are credentials — they are
ordinary values that happen to reveal an origin, and the repo is public. The
Cloudflare token needs exactly two permissions, both scoped to
`Zone → Include → Specific zone → lsinfra.de`:

- `Zone → Zone → Read` — dnscontrol's first call is `GET /client/v4/zones`
- `Zone → DNS → Edit` — list/create/update/delete of records

It is deliberately not IP-locked (a push from the workstation must work) and is
not a global key, so a leak can rewrite one zone and nothing else.

## Host-scoped files

`secrets/restic/<host>.sops.yaml` holds that host's restic sftp key and is
encrypted to that host's age key plus the user's PGP key — never to both hosts.
The shared `secrets.sops.yaml` is readable by kirito *and* mail, so a key stored
there is decryptable by whichever machine is compromised, and the per-machine
Storage Box sub-account it unlocks is then shared in practice no matter what the
key is named. The file, not the key name, is the security boundary.

sops applies the **first** matching `creation_rule`, so every host file needs its
own non-overlapping `path_regex`. A generic `secrets/restic/[^/]+\.sops\.ya?ml$`
placed above the per-host rules silently captures all of them and encrypts each
to the first host's key.

## Adding a host

A host's age recipient is derived from its SSH host key, and that key must exist
**before** the secrets are encrypted to it. `scripts/enroll-host-key.sh <host>`
does the whole dance: it runs `ssh-keygen`, derives the `age1…` from the public
half, writes the `&<host>` anchor into `.sops.yaml`, adds it to the shared key
group, and runs `sops updatekeys`.

That last step needs your PGP identity, so one of:

- the **Token2** plugged in — it can decrypt, and the script imports
  `keys/leon.asc` when the fingerprint is missing. One tap.
- `SOPS_AGE_SSH_PRIVATE_KEY_FILE=<some recipient's host key>` — no card needed,
  but you must be running on a machine that already decrypts.

`scripts/deploy.sh` calls the same logic, mints the key on the control machine
and pushes it into the install over SSH; `scripts/install-locally.sh` takes that
key with `--key`.

**Enrolment has to happen before the `nixos-install` build, not after.** The
build copies `secrets.sops.yaml` into the store and that copy is what the machine
reads, so a host enrolled later boots holding ciphertext it cannot decrypt. On a
laptop that is a lockout rather than an inconvenience: `root.hashedPassword` is
`null`, and `modules.ssh.enable` is per-host opt-in, so there is no way in.
`install-locally.sh` refuses to format in that state unless forced.

Committing the re-encryption afterwards is separate. The ciphertext only has to
be correct **on disk** where the build runs — but leave it uncommitted and the
next `--flake github:…` rebuild pulls an old copy without the new recipient.

Keep host recipients in `age1…` form. An `ssh-ed25519 AAAA…` recipient is a
different scheme and `sops-install-secrets` fails on it at boot.

## Editing

```bash
sops secrets/secrets.sops.yaml          # one tap, opens $EDITOR
sops set --value-stdin <file> '["key"]' # non-interactive
```

`sops set` only works on a path matching `.sops.yaml`'s `path_regex`, so a copy
in `/tmp` fails with `Recovery failed because no master key was able to decrypt
the file`.

`--value-file` reads the file's contents as the value but did not land where
it was expected in testing; `--value-stdin` with a JSON-quoted string was the
form that worked, so that is what is documented here:

```bash
python3 -c 'import json,sys; sys.stdout.write(json.dumps(open(".k").read().strip()))' \
  | sops set --value-stdin secrets/secrets.sops.yaml '["key"]'
```

A failed operation with `at least one key has to be successful, but none were.`
is a missed tap, not a broken pipeline.

## Verifying

```bash
sops -d secrets/secrets.sops.yaml                     # via the card
SOPS_AGE_SSH_PRIVATE_KEY_FILE=/path/to/hostkey \
  sops -d secrets/secrets.sops.yaml                   # via a host key, no card
```

## ⚠️ Losing things

- **A host key.** That host's secrets are unreadable after a reinstall. The fix
  is to enrol the *new* key and re-encrypt, which needs a different identity —
  hence the card, or any other enrolled machine.
- **The card.** `keys/leon.asc` is public, so nothing is lost from this repo;
  restore the master from its offline backup and the file still decrypts.
- **`secrets.sops.yaml`.** Backups of it are useless without a key, and the keys
  are useless without it. Keep both.

## 🔗 Resources

- [sops](https://github.com/getsops/sops)
- [sops-nix](https://github.com/Mic92/sops-nix)
- [age](https://age-encryption.org/)
