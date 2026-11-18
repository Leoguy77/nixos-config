# Installing kirito from the stock NixOS ISO

No custom ISO. The stock `nixos-minimal-*.iso` is enough because this repo is
public: the installer has no network access to your secrets, but it does not need
any — it needs the *flake*, and the flake is on GitHub.

Two things the stock image lacks, both solvable on the command line:

| Gap | Why it matters | Fix |
|---|---|---|
| flakes are disabled (`nix.settings.experimental-features = []`) | every `nix build github:…` below fails with *"experimental Nix feature 'nix-command' is disabled"* | `--extra-experimental-features 'nix-command flakes'` |
| `disko` is not installed (the other 11 tools — `cryptsetup`, `btrfs-progs`, `parted`, `gptfdisk`, `dosfstools`, `lvm2`, `util-linux`, `e2fsprogs` — all are) | `disko` does not exist | `nix shell nixpkgs#disko -c disko` |

Everything else the stock image already gives you: NetworkManager on DHCP, sshd,
passwordless sudo, a writable root, and console autologin as `nixos`.

---

## 0. Create the login password, then push

The installer fetches `github:Leoguy77/nixos-config#kirito`, so it installs whatever
is **pushed**, not what is in your working tree. The login credential
(`modules/nixos/login.nix`) does not exist in any pushed commit yet, so installing
before pushing reproduces the original bug: a machine that boots and then refuses
every login.

### 0a. Create `leoguy77_password_hash`

`modules/nixos/login.nix` reads this secret and nothing else, so activation fails
until it exists. It is **not** the mail password — deliberately a separate
credential, so rotating one does not rotate the other.

One hash covers every host this module is enabled on. That is on purpose: you are
the same person at every keyboard, so the password should rotate once, not N
times. (johnae/world does the same thing with a hardcoded hash in
`profiles/admin-user/user.nix`; the only difference here is that it lives in sops
because this repo is public.)

```sh
cd ~/Desktop/Code/nixos-config

# -s keeps the password off the terminal, out of argv and out of shell history.
read -rsp 'Password: ' P; echo
read -rsp 'Again:    ' P2; echo
[ "$P" = "$P2" ] || { echo mismatch; exit 1; }

printf '%s\n' "$P" | mkpasswd -m sha-512 -s | tr -d '\n' \
  | python3 -c 'import json,sys; sys.stdout.write(json.dumps(sys.stdin.read()))' \
  | sops set --value-stdin secrets/secrets.sops.yaml '["leoguy77_password_hash"]'

unset P P2
```

`--value-stdin` rather than `--value-file` or an argument: the plaintext never
appears in `ps`, and this is the form that actually works (a `--value-file` path
must point at a file whose contents sops can read, which is easy to get wrong).

Then verify the stored hash accepts that password. Do not skip this — a hash that
does not match is indistinguishable from a locked account at the login prompt:

```sh
H=$(sops -d secrets/secrets.sops.yaml | sed -n 's/^leoguy77_password_hash: //p' | tr -d '"')
S=$(echo "$H" | grep -oP '^\$6\$\K[^$]+')     # the salt
read -rsp 'Password again: ' P3; echo
[ "$(printf '%s\n' "$P3" | mkpasswd -m sha-512 -S "$S" -s)" = "$H" ] && echo 'HASH OK' || echo 'MISMATCH'
unset P3 H S

git add secrets/secrets.sops.yaml
```

`mkpasswd`, not `openssl passwd -6`: openssl is **not installed** on this machine,
and the tool that made the hash is the honest one to reproduce it. Better still,
use `scripts/verify-login-password.sh`, which does all of the above and
distinguishes a wrong password (exit 1) from a broken setup (exit 2).

`mkpasswd -m sha-512` produces `$6$…`, which is what `update-users-groups.pl`
expects and what `login.nix` documents.

### 0b. Push

```sh
# from the running system, before you unplug anything
git status                                  # confirm only intended files
nix flake check --no-build
git push origin main
git log --oneline origin/main -1             # must contain the login commit
```

Then confirm the pushed flake evaluates to a host with a password:

```sh
nix eval --impure --json \
  'github:Leoguy77/nixos-config#nixosConfigurations.kirito' \
  --apply 'c: { pw = c.config.users.users.leoguy77.hashedPasswordFile != null; key = c.config.users.users.leoguy77.openssh.authorizedKeys.keys != []; }'
# → { "pw": true, "key": true }
```

If that prints `false`, stop — the install will produce a locked machine.

---

## 0c. Before you leave the running system

The new machine's **sops/age identity is its SSH host key**, and kirito's age
recipient is already in `.sops.yaml`. So you have two options, and the difference
matters a lot:

**A. Keep the host key on a separate USB stick (recommended).** The age recipient
does not change, `secrets/secrets.sops.yaml` keeps decrypting, and there is no
`.sops.yaml` edit and no re-encryption.

Do **not** put it on the installer stick. A NixOS ISO is isohybrid: `sda1` is a
read-only `iso9660`, and its 3 MB vfat ESP (`sda2`) **starts at sector 284, inside
`sda1`** — measured with `sfdisk -d /dev/sda`:

```
/dev/sda1 : start=           0, size=     7579904, type=0, bootable
/dev/sda2 : start=         284, size=        6144, type=ef
```

Because the extents overlap, `sda2` mounts fine while booted from the installed
system and fails with *cannot read blockdevice* in the live installer, where the
ISO already has `sda1` mounted at `/iso`. The `EFI/BOOT` directory visible under
`/iso` belongs to the ISO's El Torito boot image — a different filesystem from the
ESP, so the key is not there either.

So write the key to any **second, ordinary** USB stick, or read it off the old root
partition from inside the installer (step 2) — the latter is simpler and needs no
extra hardware, because that key is still on `nvme0n1p2` and identical to the one
on the installer stick.

Off-machine copy, from the running system:

```sh
sudo install -m 0600 /etc/ssh/ssh_host_ed25519_key /mnt/other-stick/hostkey
```

Verify the copy before you rely on it — this is the one file whose absence makes
every secret on the new machine fail to decrypt:

```sh
# The recipient comes from the PUBLIC key. `-private-key` prints the identity
# instead (`AGE-SECRET-KEY-1…`), which is what sops-nix feeds to age at boot —
# useful, but not comparable to the anchor in .sops.yaml.
ssh-keygen -y -f /mnt/other-stick/hostkey > /mnt/other-stick/hostkey.pub
nix shell nixpkgs#ssh-to-age -c \
  ssh-to-age -i /mnt/other-stick/hostkey.pub
# must equal the &kirito anchor in .sops.yaml
# age1pr3nmcpwycezz3zc5w2ejgt7m2m46k38kufals8set4948hgss8q55vs9x
```

**B. Let it rotate (see step 5).** Nice for the thief scenario, but then nothing decrypts
until you run `sops updatekeys` from another machine holding a `.sops.yaml`
recipient. Do not pick this at 1am with no second machine.

Either way, take a restic snapshot first. **`/home` does NOT survive this** — it is a
btrfs subvolume *inside* the LUKS `cryptroot` container, so `--mode format`
destroys the whole partition table and `/home` with it. The only reason `/home` is
not ephemeral is that it survives a *reboot*; it does not survive a reinstall.

```sh
sudo systemctl start restic-backups-system.service
sudo systemctl status restic-backups-system.service     # wait for Result=success
```

Then prove the snapshot restores, because a backup you have not restored is a hope:

```sh
T=$(mktemp -d)
sudo restic restore latest --target "$T" --include /home/$USER/Desktop
sudo du -sh "$T"; sudo rm -rf "$T"
```

## 1. Boot the USB stick

Write the stock ISO to the stick (`dd`, or Rufus/balenaEtcher on the Windows
boxes). Boot it — **the stick is already written**, so this is just the boot step.
You land on a `nixos` console with `sudo` and DHCP.

If you want to drive it from another machine instead of the laptop keyboard:

```sh
sudo passwd nixos          # or install an authorized key
ip -brief address          # note the address
```

## 2. Get the flake, install, capture the recovery key

First, take the host key off the root partition that is about to be wiped. It is
the same key that is on your USB stick, and reading it here means the stick's
unmountable ESP never enters the picture:

```sh
sudo -i
mkdir -p /root/oldroot
mount -o ro /dev/nvme0n1p2 /root/oldroot
install -m 0600 /root/oldroot/etc/ssh/ssh_host_ed25519_key /root/hostkey
umount /root/oldroot
ssh-keygen -lf /root/hostkey
# must print: 256 SHA256:8V/kHcalL1+Dvgv6aaK34a7yxdp7iDiyyQ1WmAxrFRk root@kirito (ED25519)
```

**The `umount` is not optional.** A partition still mounted at `/root/oldroot`
makes disko fail with *device busy*. `/root/hostkey` lives in RAM, so it survives
the repartition.

Both containers enroll your FIDO2 token (tap only, no PIN) and are formatted with
an autogenerated throwaway key that is wiped at the end of the format step. There
is **no passphrase to set** — `enrollFido2 = true` makes disko ignore
`/tmp/luks-password` entirely and run `systemd-cryptenroll --wipe-slot=0`.

That makes the **recovery key the only way back in**, so the format step will
stop and wait for you:

```
Press Enter when you scanned the QR code offscreen or that the recovery key is stored securely.
```

It prints twice, once per container. Store both. Everything else on this machine
is reproducible from the flake; these two strings are not, and losing them means
the disk is unrecoverable if the token is lost or breaks.

Plug the Token2 in **before** starting — disko pauses waiting for a `/dev/hidraw*`
node, but its check is `ls /dev/hidraw*`, which also matches non-FIDO HID devices
(this laptop has one), so it may sail past that wait and fail inside
`systemd-cryptenroll` instead.

```sh
cd /tmp
export NIX_CONFIG='experimental-features = nix-command flakes'
DISKO_SKIP_SWAP=1 nix shell nixpkgs#disko -c disko \
    --mode destroy,format,mount \
    --flake github:Leoguy77/nixos-config#kirito \
    --root-mountpoint /mnt

# 1. Where the sops/age identity has to live for an EPHEMERAL root. `neededForUsers`
#    secrets (the login password) are decrypted by sops-nix's `setupSecretsForUsers`
#    ACTIVATION SCRIPT, and NixOS runs activation from the initrd —
#    initrd-nixos-activation does `exec chroot /sysroot …/prepare-root` because
#    users must exist before any stage-2 unit starts. impermanence's
#    /persist/etc/ssh → /etc/ssh bind mount happens LATER, so only the persisted
#    path is readable at that point. profiles/state.nix therefore adds
#    /persist/etc/ssh/ssh_host_ed25519_key to sops.age.sshKeyPaths; without this
#    copy the users step fails with "0 successful groups required, got 0", no
#    password reaches /etc/shadow, and the machine boots to an unusable greeter.
mkdir -p /mnt/persist/etc/ssh
cp /root/hostkey /mnt/persist/etc/ssh/ssh_host_ed25519_key
chmod 600 /mnt/persist/etc/ssh/ssh_host_ed25519_key

# 2. Belt and braces for the /etc path. Not what the fix depends on: with
#    profiles/state.nix pointing sops.age.sshKeyPaths at /persist/etc/ssh/…, the
#    install-time activation (which chroots into /mnt, where /persist IS mounted)
#    already finds the key. This copy only matters for a stage-2 service reading
#    /etc/ssh/ssh_host_ed25519_key after impermanence's bind mount.
mkdir -p /mnt/etc/ssh
cp /root/hostkey /mnt/etc/ssh/ssh_host_ed25519_key
chmod 600 /mnt/etc/ssh/ssh_host_ed25519_key

# 3. Prove those two copies are the key the secrets were re-encrypted to,
#    BEFORE spending the install on it. A mismatch means nothing decrypts, the
#    password hash never reaches /etc/shadow, and the machine boots to a greeter
#    nobody can log into — the failure that looks like a broken flake.
#
#    Compare the RECIPIENT, which is derived from the public key. With
#    `-private-key` ssh-to-age prints the identity instead (AGE-SECRET-KEY-1…),
#    which is exactly what sops-nix hands to age at boot and is NOT the anchor.
ssh-keygen -y -f /root/hostkey > /root/hostkey.pub
nix shell nixpkgs#ssh-to-age -c ssh-to-age -i /root/hostkey.pub
# must equal the &kirito anchor in .sops.yaml:
# age1pr3nmcpwycezz3zc5w2ejgt7m2m46k38kufals8set4948hgss8q55vs9x

nixos-install \
    --flake github:Leoguy77/nixos-config#kirito \
    --no-channel-copy --no-root-password
```

- **`disko`, then `nixos-install` — not `disko-install`.** `disko-install` builds
  the whole system configuration *inside the live store* before copying it to the
  target (`nix build …` with no `--store`, then `xcp`). The live store is an
  overlay whose upper layer is a **tmpfs with no `size=` option**
  (`iso-image.nix:813`), so it defaults to 50% of RAM ≈ 7.5 GiB here — and
  kirito's closure is **13.9 GiB**. It dies with `No space left on device` no
  matter how large you remount `/nix/.rw-store`, because the RAM is the limit, not
  the mount option. `nixos-install` builds with `--store /mnt/nix/store`
  (line 289 of `nixos-install.sh`), so nothing is held in RAM.
- Mountpoint is **`/mnt`**, not disko's default `/mnt/disko-install-root` —
  `nixos-install` looks at `/mnt` unless told otherwise.
- **`DISKO_SKIP_SWAP=1`** keeps `disko` from `swapon`-ing the new encrypted swap
  (`share/disko/lib/types/swap.nix:97`). `disko-install` sets it too
  (`.disko-install-wrapped:273`) because activating a swap device on the disk you
  are actively writing can bite if anything is unmounted or ejected mid-install.
  It is not needed for space: `nixos-install` writes to `/mnt/nix/store`, and
  `/nix` is its **own** btrfs subvolume on `cryptroot`, not part of the 8 GiB
  tmpfs root — only `/` is tmpfs under `ephemeralRoot`.
- `nixpkgs#disko` is **floating**. `disko` builds the format script from the
  package's own `cli.nix` and reads only `disko.devices.disk` out of your flake,
  so a running disko much newer than the pinned one can disagree with the declared
  config. Pin it to the flake's own input if the format step misbehaves:
  `nix shell github:nix-community/disko/1dd30c29c88d99ce295f15e27f93c49bc5fbae07 -c disko …`
- `--mode destroy,format,mount` is explicit and required here. Bare `--mode mount`
  reuses existing partitions instead of partitioning — on this disk that would put
  the new system on top of the old ext4 root. `destroy,format,mount` is the mode
  formerly known as `--mode disko`, and unlike `format` it also unmounts first.
- `--write-efi-boot-entries` was `disko-install`'s job; now it is `nixos-install`'s
  bootloader step. Verified for this host: `boot.loader.systemd-boot.enable = true`,
  `grub = false`, `efi.canTouchEfiVariables = true`, `efiSysMountPoint = "/boot"` —
  so the NVRAM entry is written without any extra flag.
- The host key is copied by plain `cp` to **two** places before `nixos-install`:
  `/mnt/persist/etc/ssh/` (first boot, via impermanence) and `/mnt/etc/ssh/`
  (the install itself, because `setupSecretsForUsers` runs as an activation
  script inside the chroot and decrypts with `/etc/ssh/ssh_host_ed25519_key`).
  `disko-install --extra-files` did the same thing
  (`cp -ar "$source" "$mountPoint/$destination"`, line 278 of
  `.disko-install-wrapped`); doing it by hand is one line per destination and
  removes the argument-collapsing trap described next.
- If you ever do go back to `--extra-files`: pass **one** pair, targeting
  `/persist`, and never the same SOURCE twice. It stores its arguments in an
  associative array keyed by SOURCE, so a duplicate silently keeps only the last
  destination. impermanence's `persist-…-etc-ssh-…` service bind-mounts
  `/persist/etc/ssh/…` onto `/etc/ssh/…` **before** `local-fs.target`, so the
  `/etc` copy would be shadowed a second later anyway.
- `nixos-install` does **not** pass `--no-root-password` unless you ask, and with
  `users.mutableUsers = false` it has nothing to prompt for; leaving it out makes
  the install stop at an unusable prompt on a passwordless root. Keep the flag.

To add a passphrase as a *third* way in afterwards (not needed, and it weakens
the point of the token): `cryptsetup luksAddKey /dev/disk/by-partlabel/disk-main-root`.
Use the partlabel, not `pN` — the GPT order is ESP=1, swap=2, root=3 and the
numbering shifts whenever a partition is added.

## 3. Watch for the two things that usually go wrong

`nixos-install` is quiet for minutes at a time; it is fetching a ~13.9 GiB closure
onto the target disk. If it dies:

- **`No space left on device` on `/nix/.rw-store`** — you ran `disko-install`, or
  something else that builds in the live store. See the tmpfs-overlay explanation
  above; the answer is `nixos-install --flake …`, not a bigger remount.
- **`device busy` during the format step** — the old root is still mounted
  somewhere (`/root/oldroot` from step 2). `findmnt -R /dev/nvme0n1` and unmount.
- **`error: experimental Nix feature 'nix-command' is disabled`** from inside a
  nested nix call — the `--extra-experimental-features` flag did not propagate.
  Export it first: `export NIX_CONFIG='experimental-features = nix-command flakes'`.

## 4. Reboot

`reboot`, remove the USB stick. The initrd asks for a **token tap on each
container** — twice, because user presence is a fresh HMAC-SHA1 challenge per
`cryptsetup open` and the kernel keyring does not carry it across containers.
There is no PIN (both containers enroll `--fido2-with-client-pin=no`) and no
passphrase prompt to fall back to.

If the token is missing or broken, type the recovery key from install time when
prompted — that is the slot disko kept for exactly this case.

The recovery key is *not* in the flake and is not recoverable from it. The age key
on the machine cannot unlock the disk, and losing both the token and the recovery
key means the data is gone — the restic repository on host1 is the only copy that
survives.

## 5. Restore /home from host1

Nothing put your files back. `/home/leoguy77` now exists and is empty except for
what home-manager generated. The restic repository on host1 has them, and the new
machine can already reach it: the host key was carried across, so sops decrypts
`restic_password` and `restic_ssh_key` on first boot, and `programs.ssh.knownHosts`
already pins host1.

Log in as `leoguy77` and run it **as root**, because the backup was taken as root
and only root can write files back with their original ownership.

Use **`restic-system`, not `restic`**. nixpkgs generates a wrapper named after the
backup config that presets `RESTIC_REPOSITORY`, `RESTIC_PASSWORD_FILE` and
`sftp.args`; plain `restic` has none of them and will stop with
*unable to open config file* / *repository not specified*.

```sh
sudo -i
restic-system snapshots --latest 3
restic-system restore latest --target / --verify
```

- `--target /` restores to the original absolute paths, so `/home/leoguy77/...`
  lands where it came from. Do not point it at `/home/leoguy77` — that would create
  `/home/leoguy77/home/leoguy77/...`.
- `--verify` re-reads the restored data and compares it to the repository, so a
  silent bit-rot in the repo is caught now rather than at the next restore.
- `Downloads` and `.cache` were excluded, so they will not come back. Everything
  else does.
- Restoring over the fresh home-manager symlinks will replace them. Run
  `home-manager switch` (or reboot) afterwards to put the config links back.

The restic config, password file and SSH key are already in place, so no flags are
needed. `restic-system` is the wrapper described above.

## 6. If the host key rotated (option B)

From a machine that holds a `.sops.yaml` recipient:

```sh
ssh-keyscan -t ed25519 kirito > /tmp/kirito.pub     # or read it off the console
ssh-to-age < /tmp/kirito.pub                        # → age1…
# replace the &kirito anchor in .sops.yaml with that age1…
sops updatekeys secrets/secrets.sops.yaml
git commit .sops.yaml secrets/secrets.sops.yaml
```

Until this is done the machine boots but **no secret decrypts**, so there is no
restic password, no WireGuard key and no Tailscale auth. Do it before you rely on
anything.

## 7. First boot is the real test

`profiles/state.nix` enumerates exactly what survives: 9 directories and 7 files.
A successful first boot proves the list is complete. The things that will be
obviously wrong if it is not:

- sshd comes up with a *new* host key → the key was not at `/persist/etc/ssh`
- the login password is gone → `modules.login` is not doing its job
- the tailnet shows a new node → `/var/lib/tailscale` was not persisted

Log in as `leoguy77` with the password from `leoguy77_password_hash`, then `sudo -i`.
`users.mutableUsers = false` means `passwd` will refuse — that is intended. To
change the password, repeat step 0a (same secret name, `sops set` overwrites) and
`nixos-rebuild switch`.
