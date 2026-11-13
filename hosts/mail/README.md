# hosts/mail — mail.lsinfra.de (netcup VPS pico G11s)

Encrypted-root NixOS mail server: **Postfix + Dovecot + rspamd** via
[nixos-mailserver](https://gitlab.com/simple-nixos-mailserver/nixos-mailserver)
plus **Roundcube** webmail. Everything — accounts, aliases, quotas, DKIM, TLS —
is declared in `modules/nixos/mail.nix`. There is no setup wizard and no
configuration that lives in a database Nix cannot read.

```
                :443 / :80                     ┌──────────────────────────┐
  Internet ──────────────────────────────────►│ nginx  webmail.lsinfra.de│─► Roundcube (php-fpm)
                                               │        mail.lsinfra.de   │─► ACME HTTP-01 answer only
                :25 :465 :587 :143 :993 :4190 ─────────────────────────────► Postfix / Dovecot (rspamd milter)
```

One certificate, `mail.lsinfra.de`, issued over plain **HTTP-01** and read from
`/var/lib/acme` by nginx, Postfix and Dovecot alike. No TLS passthrough, no
ALPN: the NixOS ACME module supports neither (its only non-DNS modes are
`webroot`, `listenHTTP` and `s3Bucket`), and a single cert needs neither.

## ⚠ Verify these five values before you install

A wrong value here means a server you cannot reach.

| Value | Used in | Status |
|---|---|---|
| IPv4 `91.132.147.216/22`, gw `91.132.144.1` onlink | `hosts/mail/default.nix` | ✅ confirmed (`ip -4 route`) |
| IPv6 `2a03:4000:37:c32:6860:64ff:fe3b:ddb0/64`, gw `fe80::1` onlink | same | ✅ confirmed (`ip -6 route`) |
| Disk device `/dev/vda` | `--disk main <dev>` | ✅ confirmed from `lsblk` |
| NIC | matched by link type (`Type=ether`) | ✅ eth0 / enp0s3 / ens3 all match |
| rDNS | netcup CCP | ✅ set — both `mail.lsinfra.de` (verified) |

## Prerequisites

1. **netcup CCP**
   - Enable **UEFI boot** for the server (otherwise systemd-boot finds no ESP).
   - Set **rDNS/PTR** for the IPv4 address *and* the IPv6 address to
     `mail.lsinfra.de`. Mail that leaves without matching rDNS is rejected by
     most receivers.
   - No firewall/port blocking on 25/80/443/465/993/4190. Port 80 is not
     cosmetic: it is the only thing Let's Encrypt can reach for HTTP-01.
2. **DNS for lsinfra.de** — this is **not a manual step**. The zone is applied
   by `dns-sync.service`, driven by `modules.dns.records` in
   `hosts/mail/dns.nix` and `hosts/asuna/dns.nix`. On a rebuild:

   | Name | Type | Value |
   |---|---|---|
   | `mail` | A | `91.132.147.216` |
   | `mail` | AAAA | `2a03:4000:37:c32:6860:64ff:fe3b:ddb0` |
   | `webmail` | A / AAAA | same |
   | `lsinfra.de` | MX 10 | `mail.lsinfra.de` |
   | `lsinfra.de` | TXT | `v=spf1 mx -all` |
   | `_dmarc` | TXT | `v=DMARC1; p=reject; rua=mailto:postmaster@lsinfra.de` |

   The whole zone is in `hosts/mail/dns.nix` + `hosts/asuna/dns.nix` and pushed
   with `PURGE`, so a record not declared there is deleted on the next rebuild.
   The records that must not appear in this public repo (the apex, `nix-cache`,
   `meshview`, `pelican`, `wing`) are declared with variable names —
   `host1_ipv4` / `host1_ipv6` — whose values come from sops at push time.

   DKIM included: the `mail._domainkey` keypair is generated once, off-repo
   (`rspamadm dkim_keygen`), the private half lives in sops as
   `dkim_mail_private_key`, and the public half is a literal `TXT` in
   `hosts/mail/dns.nix`. Nothing about the zone depends on the host existing.
   Do **not** publish MTA-STS/TLSA yet.
3. **A machine with Nix** for `nixos-anywhere` (kirito/surface).
4. **SSH key** already in the repo config (the `Github` ed25519 key at
   `modules.server.adminKeys`). Add more keys there if you need them.

## Install

⚠ This wipes `/dev/vda` (currently an unencrypted 3-partition install).

### This box needs the ISO route, not kexec (1 GB RAM)

`nixos-anywhere` normally boots its own kexec installer, and that image is
**405 MiB compressed / 449 MiB uncompressed** — it has to sit in RAM, which on a
963 MiB box leaves nothing for the install:

```
963 MiB RAM - 474 MiB (kernel + initrd ramfs) = 489 MiB usable
489 MiB - 446 MiB (disko tool closure)        =  43 MiB → OOM
```

The installer also lacks `sgdisk`/`mkfs.btrfs`/`dosfstools`/`parted`, so the
usual `--no-disko-deps` workaround swaps an OOM for `command not found` (the
custom ISO below fixes that part by putting those tools on sshd's PATH).

**Boot the stock NixOS ISO instead.** Its root is a squashfs on the CD, so
nothing is copied to RAM:

```
963 MiB RAM - 54 MiB (kernel + initrd) = 909 MiB usable
```

And the ISO ships every tool disko needs. `nixos-anywhere` detects the ISO
(`VARIANT_ID=installer`) and skips kexec automatically — no flags, no code
change.

#### Steps

There is a pre-built ISO for this host — static IP, admin key and all the
disko tools baked in. Build the current one and upload it:

```bash
nix build .#installerIso-mail
# → result/iso/nixos-installer-mail-*.iso  (~1.4 GiB)
```

1. netcup SCP → **Media → DVD Drive → Custom ISO** → upload that file → mount
   it. (Custom ISO uploads expire after 48 hours.)
2. Boot it (SCP *Power → Reset*). No VNC step: it comes up on
   `91.132.147.216` with your key in `/root/.ssh/authorized_keys`.
3. From kirito, run the normal deploy (inside the dev shell — it needs `sops`):

   ```bash
   nix develop .# --command scripts/deploy.sh mail root@91.132.147.216 /dev/vda
   ```

4. Unmount the DVD and reboot when it is done.

That image is `modules/iso/installer.nix`: `installation-cd-minimal` plus static
networking for `eth0` in both the initrd and stage 2, NetworkManager forced off
(it would DHCP eth0 and cut the SSH session mid-copy), root login by key only,
and `systemd.services.sshd.path` carrying every tool disko needs. The last point
matters: it lets `--no-disko-deps` work, so the closure copied into RAM is
19 KiB instead of 446 MiB.

<details>
<summary>Fallback: stock ISO + VNC console</summary>

If you have no custom ISO to hand, the stock one works — it costs one VNC
session where you set the IP and drop the key by hand.

1. Download `nixos-minimal-*.iso` from <https://nixos.org/download>.
2. netcup SCP → **Media → DVD Drive → Custom ISO** → upload it → mount it.
3. Boot (SCP *Power → Reset*). Open the SCP **VNC console** — you need it once.
4. On the live system, get it reachable over SSH:

   ```bash
   # static IP, matching hosts/mail/default.nix exactly (interface is eth0)
   sudo ip addr add 91.132.147.216/22 dev eth0
   sudo ip -6 addr add 2a03:4000:37:c32:6860:64ff:fe3b:ddb0/64 dev eth0
   sudo ip route add default via 91.132.144.1 dev eth0 onlink
   sudo ip -6 route add default via fe80::1 dev eth0
   sudo mkdir -p /root/.ssh && sudo tee /root/.ssh/authorized_keys <<'EOF'
   ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFZ0JSHtQqJfwycHbi+qUTFO1CfmP5tiFIEWMeOpEP8l Github
   EOF
   ```

   (DHCP may already have given you one of these — `ip -br addr` first and only
   add what is missing. The ISO runs sshd with `PermitRootLogin yes` but an
   empty password, so the key is the way in.)
5. From kirito, run `nix develop .# --command scripts/deploy.sh mail root@91.132.147.216 /dev/vda`.
6. Unmount the DVD and reboot when it is done.

</details>

`nixos-anywhere` still needs `tar`, `cpio` and `setsid` on the target even when
it skips kexec; both ISOs ship all three (verified).

### The normal route (only for hosts with ≥1.5 GB RAM)

```bash
# 1. Exercise the disk layout in a throwaway VM first (no real disk touched).
VM_TEST=1 nix develop .# --command scripts/deploy.sh mail root@91.132.147.216 /dev/vda

# 2. Deploy. Prompts for the LUKS passphrase (used at every boot) and mints +
#    enrols this host's SSH host key (which is also its sops identity).
nix develop .# --command scripts/deploy.sh mail root@91.132.147.216 /dev/vda

# Connecting as a non-root user with password-less sudo works too:
#   nix develop .# --command scripts/deploy.sh mail leoguy77@91.132.147.216 /dev/vda
```

`scripts/deploy.sh` is the general installer for every host of this flake
(`scripts/deploy.sh <host> <user@address> [disk]`); for this one it wraps
`nixos-anywhere` with `--flake path:$PWD#mail --target-host root@91.132.147.216
--disk main /dev/vda --disk-encryption-keys /tmp/luks-password <passfile>`,
plus the host-key minting and `--extra-files` staging described above.

It uses `path:` rather than the default `git+file:` because git flakes copy only
tracked files — the gitignored initrd authkey would otherwise be missing from
the build.

The disk layout is **imported by the host** (`inputs.disko.nixosModules.disko` +
`modules/disko/luks-btrfs-server.nix`), which is why `--disk main` can override
`disko.devices.disk.main.device`. There is no `--disko` flag. No
`--generate-hardware-config` either: the hardware file is committed and kept
free of `fileSystems`, which disko now owns — the script refuses to run if it
finds `fileSystems` there.

## Initrd SSH: tailnet only, never public

The initrd runs `tailscaled` (state on the ESP, see below) and joins the tailnet
as **`mail-initrd`** before the disk is unlocked. sshd then binds to the address
tailscaled handed out — **only** that address:

```
initrd-sshd: listening only on 100.x.y.z:2222
```

Nothing listens on `91.132.147.216` during stage 1. If tailscale does not come
up, the bind script exits non-zero (`Restart=` retries) and sshd never starts: it
fails closed rather than falling back to the public interface.

### No expiring credential (this is the point)

The node identity lives in **`/run/initrd-boot/tailscale-initrd.state`** on the
ESP — unencrypted, so it is readable before the root is unlocked. Consequences:

| | |
|---|---|
| Auth key needed | only to bootstrap the *first* join |
| Auth key expires | irrelevant — not used after boot 1 |
| Node identity | stable (same name, same 100.x address every boot) |
| Key expiry | disable it once for this node (below) and it never re-auths |

That is the answer to “can it not expire”: a Tailscale **auth key cannot exceed
90 days** (hard limit), but a **node** does not need one once its state is
persisted. In the admin console → Machines → `mail-initrd` → **Disable key
expiry** (servers are the documented case for this).

### Bootstrap the first join — nothing to edit

This is a **default for every server host**: `modules.server` turns on
`modules.initrdTailscale`, and the module looks for its bootstrap key at the
conventional path `secrets/tailscale-initrd-<hostname>.authkey` (gitignored).
There is no option to toggle and no file to place by hand — `scripts/deploy.sh`
mints one and deletes it again afterwards.

#### No auth key to create, ever

A fresh install wipes the ESP, so the persisted node identity goes with it and a
new auth key is needed. Rather than keeping a 90-day key around per host,
`deploy.sh` mints a **1-hour** key on demand from a Tailscale **OAuth client**
stored in sops:

```yaml
# secrets/secrets.sops.yaml — set once, used for every server
tailscale_oauth_client_id: kreo…
tailscale_oauth_client_secret: tskey-client-…
```

Setup, one time in the admin console:

1. <https://login.tailscale.com/admin/settings/oauth> → **New credential**
2. Scopes: **Devices → Keys → Auth Keys → Write**. Nothing else.
3. Tags: `tag:fde-unlock`, and add it to `tagOwners` in the tailnet policy file:

   ```json
   "tagOwners": { "tag:fde-unlock": ["autogroup:admin"] },
   ```

Why an OAuth client rather than a key: an **auth key cannot live longer than 90
days** (hard limit), and every reinstall consumes one, so a stored key is a
recurring manual chore. An OAuth client secret **never expires**, so this works
for every server indefinitely with no manual step. The tag means a leaked
credential can only ever enroll an FDE-unlock node.

| Override | Effect |
|---|---|
| `secrets/tailscale-initrd-<host>.authkey` exists | used as-is, API not called |
| `tailscale_initrd_authkey_<host>` in sops | static fallback if minting fails |
| `TS_TAG=tag:other` | mint with a different tag |

The key never needs to outlive the install: after the first join the identity
lives in `tailscale-initrd.state` on the ESP. Disable key expiry on the
`mail-initrd` **node** (Machines → `mail-initrd` → Disable key expiry) — that is
the node key, a different thing from the auth key, and it can be non-expiring.

Because nothing secret is needed to *build* the host, the initrd produced by
GitHub `autoUpgrade` carries **no** credential at all. The persisted node state
makes that harmless.

### Unlock

```bash
ssh -p 2222 root@mail-initrd      # -p 2222; the node name is the initrd's
# in that session:
systemd-tty-ask-password-agent --watch
```

The initrd host key is generated at build time, so the fingerprint changes
whenever the key derivation is rebuilt. Take the current one out of the boot of
a running system (`ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` over the
tailnet) or just accept the prompt the first time.

Fallback if the tailnet join failed: netcup CCP → **Console (VNC)**.

### Why not sops here?

A sops secret has to be decrypted by something, and that something has to run in
the initrd — i.e. its key would also sit on the unencrypted `/boot`. That is the
same exposure as the secret itself, one indirection longer. sops is the right
tool for stage-2 secrets (restic password, the account password hash), which is
why `modules.sops.enable` stays off only until the host key is in `.sops.yaml`.

### Updates

`system.autoUpgrade` stays **on** for `mail`: nothing secret is needed to build
this host, because the initrd node state lives on the machine itself. The nightly
GitHub rebuild also removes the bootstrap key from the initrd image incidentally
(GitHub cannot see the gitignored file), which is exactly what you want.

Manual rebuild from the workstation:

```bash
nixos-rebuild switch --flake .#mail --target-host leoguy77@91.132.147.216 --use-remote-sudo
```

Once stage 2 is up, the normal system joins as **`mail`** (separate node, own
state on the encrypted root):

```bash
ssh leoguy77@91.132.147.216 'sudo tailscale up --ssh --accept-dns=false'
```

## First-run configuration

There is none. Accounts, aliases, quotas, DKIM, the whole DNS zone and the
host's own sops identity are all settled before the machine first boots.

### 0. Commit the rotated secrets

`scripts/deploy.sh` generated this host's SSH host key on the control machine,
enrolled its `age1…` as `&mail` in `.sops.yaml`, re-encrypted
`secrets/secrets.sops.yaml` to it, and seeded the key into the install — then
deleted its own plaintext copy. Those two files on disk are now the **only**
thing holding ciphertext that this machine's key can read:

```bash
git add .sops.yaml secrets/secrets.sops.yaml
git commit -m 'chore(secrets): authorise mail'
```

Do that before the host runs `autoUpgrade` again. If the commit is skipped, the
remote still has ciphertext for a key that only exists on the machine — which
works, but leaves the repo unable to decrypt itself.

If the install failed instead, `deploy.sh` restored both files, so nothing is
lost and the run can simply be repeated.

### 1. Test mail

Nothing to publish: `mail._domainkey.lsinfra.de` is already in the zone and was
verified against Cloudflare's authoritative servers. Send a test mail to
<https://www.mail-tester.com> and to a Gmail address, and check both directions
over IPv4 *and* IPv6. Expect a full score only after SPF, DKIM and DMARC all
agree.

If you deliberately rotate the DKIM key (`rspamadm dkim_keygen` → `sops set
secrets/secrets.sops.yaml '["dkim_mail_private_key"]' …`), the `p=` in
`hosts/mail/dns.nix` must change with it, or signing breaks.

### 2. Webmail

<https://webmail.lsinfra.de> logs in against `mail.lsinfra.de` over IMAPS and
SMTPs; the domain suffix is filled in automatically. It also edits server-side
filters over ManageSieve (port 4190), so a filter set in the webmail is a real
Sieve script on the server.

## The host key is the sops identity

`/etc/ssh/ssh_host_ed25519_key` is two things at once: the SSH host identity, and
the age identity sops-nix uses at boot (`age.sshKeyPaths`).

The private half exists in exactly two places, and only one of them persists:

| Where | How long |
|---|---|
| `mktemp -d` on the control machine | during `deploy.sh`, removed by its EXIT trap |
| `/etc/ssh/ssh_host_ed25519_key` on the host | forever |

It is never in this repo. What the repo *does* carry is the derived public
`age1…` recipient, generated in the same run by
`ssh-keygen -y -f <key> | ssh-to-age` and written into `.sops.yaml` as `&mail`.
A fresh keypair is minted on every `deploy.sh` run, so re-installing re-enrols
the machine automatically — no manual `sops updatekeys` step, ever.

Lost the key? The host cannot decrypt its secrets. Reinstall (or
`ssh-keygen` a new one into `/etc/ssh`, re-run `sops updatekeys` with its new
recipient in `.sops.yaml`, rebuild) — the loop is the same one `deploy.sh`
automates.

## Operating notes

- **Updates**: `system.autoUpgrade` rebuilds daily from GitHub with
  `allowReboot = false`, because a reboot needs the passphrase.
  Manual: `nixos-rebuild switch --flake github:Leoguy77/nixos-config#mail`.
- **RAM**: 1 GB total, plus a 2 GB swapfile on the encrypted root. That budget
  is why `virusScanning = false` (ClamAV's signature DB alone wants ~1 GB RSS)
  and `fullTextSearch.enable = false` (Dovecot's FTS index is the other hog).
  Check `systemd-cgtop` / `free -m` after a week of real traffic; rspamd is the
  process to watch first.
- **Disk**: 30 GB, `/var` is a separate subvolume with `nodatacow`. That was
  chosen for the previous database-backed stack; for a plain mail spool it only
  costs a little space amplification. Check `btrfs filesystem usage /`.
- **TLS**: one cert, `mail.lsinfra.de`, renewed by `acme-mail.lsinfra.de.service`
  over HTTP-01 and reloaded into nginx, Postfix and Dovecot by the cert's
  `reloadServices`. `webmail.lsinfra.de` has its own cert. If renewal fails,
  check that port 80 still reaches nginx — that is the only thing the challenge
  needs.
- **Backups**: `modules.backup` (restic) covers `/var/vmail` and
  `/var/lib/roundcube`; set `modules.backup.repository` to an off-site target
  once you have one.
- **Ports**: `nft list ruleset`. Only 22, 25, 80, 443, 465, 993, 4190 are open,
  plus the tailnet interface. No 143 (IMAP without TLS is deprecated, RFC 8314)
  and no 587 (submission is on 465/implicit TLS).
- **DKIM keys**: the keypair is *not* generated on this host. The private half
  is decrypted from sops to `/run/secrets/dkim_mail_private_key` (owned by
  `rspamd`, mode 0400) and `mailserver.dkim.domains.<domain>.selectors.mail.keyFile`
  points rspamd at it. Rotating it means regenerating the key, updating the
  sops entry, and updating the `p=` in `hosts/mail/dns.nix` — all three, or
  receivers will fail the signature.
- **Spam**: rspamd learns per-user ham/spam from the Junk folder via
  `imapsieve`; users should move misclassified mail rather than delete it.
