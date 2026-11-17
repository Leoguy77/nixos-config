# Installing kirito from the stock NixOS ISO

No custom ISO. The stock `nixos-minimal-*.iso` is enough because this repo is
public: the installer has no network access to your secrets, but it does not need
any — it needs the *flake*, and the flake is on GitHub.

Two things the stock image lacks, both solvable on the command line:

| Gap | Why it matters | Fix |
|---|---|---|
| flakes are disabled (`nix.settings.experimental-features = []`) | every `nix build github:…` below fails with *"experimental Nix feature 'nix-command' is disabled"* | `--extra-experimental-features 'nix-command flakes'` |
| `disko` is not installed (the other 11 tools — `cryptsetup`, `btrfs-progs`, `parted`, `gptfdisk`, `dosfstools`, `lvm2`, `util-linux`, `e2fsprogs` — all are) | `disko-install` does not exist | run it through `nix run` |

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
[ "$(openssl passwd -6 -salt "$S" "$P3")" = "$H" ] && echo 'HASH OK' || echo 'MISMATCH'
unset P3 H S

git add secrets/secrets.sops.yaml
```

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

## 0b. Before you leave the running system

The new machine's **sops/age identity is its SSH host key**, and kirito's age
recipient is already in `.sops.yaml`. So you have two options, and the difference
matters a lot:

**A. Carry the current host key across (recommended).** The age recipient does not
change, `secrets/secrets.sops.yaml` keeps decrypting, and there is no `.sops.yaml`
edit and no re-encryption. Copy it somewhere off the machine first — it is about
to be wiped:

```sh
sudo cp /etc/ssh/ssh_host_ed25519_key     /run/media/$USER/usb/hostkey
sudo cp /etc/ssh/ssh_host_ed25519_key.pub /run/media/$USER/usb/hostkey.pub
```

**B. Let it rotate (see step 5).** Nice for the thief scenario, but then nothing decrypts
until you run `sops updatekeys` from another machine holding a `.sops.yaml`
recipient. Do not pick this at 1am with no second machine.

Either way, take a restic snapshot first — `/home` is a persistent subvolume and
*is* preserved by the layout, but this is a repartition, not a reinstall in place.

## 1. Boot the USB stick

Write the stock ISO to the stick (`dd`, or Rufus/balenaEtcher on the Windows
boxes). Boot it. You land on a `nixos` console with `sudo` and DHCP.

If you want to drive it from another machine instead of the laptop keyboard:

```sh
sudo passwd nixos          # or install an authorized key
ip -brief address          # note the address
```

## 2. Get the flake, install, capture the recovery key

Both containers enroll your FIDO2 token (tap only, no PIN) and are formatted with
an autogenerated throwaway key that is wiped at the end of the format step. There
is **no passphrase to set** — `enrollFido2 = true` makes disko ignore
`/tmp/luks-password` entirely and run `systemd-cryptenroll --wipe-slot=0`.

That makes the **recovery key the only way back in**, so `disko-install` will
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
nix --extra-experimental-features 'nix-command flakes' \
    run nixpkgs#disko -- \
    disko-install \
    --flake github:Leoguy77/nixos-config#kirito \
    --disk main /dev/nvme0n1 \
    --mode format \
    --write-efi-boot-entries \
    --extra-files /run/media/nixos/usb/hostkey /etc/ssh/ssh_host_ed25519_key \
    --extra-files /run/media/nixos/usb/hostkey /persist/etc/ssh/ssh_host_ed25519_key
```

- `--disk main` names the disko disk declaration (`disko.devices.disk.main`), and
  `/dev/nvme0n1` is **the whole disk** — confirm with `lsblk` first. Everything on
  it is destroyed, including the current `/home`.
- `--mode format` partitions. Without it `disko-install` only mounts.
- `--write-efi-boot-entries` is needed because you are booting this same machine
  from that same disk. Omit it only if you are transplanting the disk.
- The two `--extra-files` seed the host key both at `/etc/ssh` (so activation and
  sops can read it) and at `/persist/etc/ssh` (`/` is tmpfs, so the `/etc` copy is
  gone next boot). Option B above: skip both.

To add a passphrase as a *third* way in afterwards (not needed, and it weakens
the point of the token): `cryptsetup luksAddKey /dev/disk/by-partlabel/disk-main-root`.
Use the partlabel, not `pN` — the GPT order is ESP=1, swap=2, root=3 and the
numbering shifts whenever a partition is added.

## 3. Watch for the two things that usually go wrong

`disko-install` is quiet for minutes at a time; it is copying a ~1.5 GiB closure.
If it dies:

- **OOM.** The live root is tmpfs and the closure lands in RAM. `zramSwap` is not
  on the stock ISO — if you have under ~8 GB, add `--option substituters ""` or
  install with `nixos-install` after a manual `disko` format/mount instead.
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

## 5. If the host key rotated (option B)

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

## 6. First boot is the real test

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
