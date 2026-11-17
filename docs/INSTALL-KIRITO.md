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

## 0. Push the fix first

The installer fetches `github:Leoguy77/nixos-config#kirito`, so it installs whatever
is **pushed**, not what is in your working tree. The login credential
(`modules/nixos/login.nix`) does not exist in any pushed commit yet, so installing
before pushing reproduces the original bug: a machine that boots and then refuses
every login.

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

## 2. Set the LUKS passphrase, get the flake, install

```sh
# The disko layout reads the passphrase from this fixed path (both containers).
# disko-install does NOT prompt for it or create this file — without it, the
# format step fails with "No such file or directory".
printf '%s' 'YOUR PASSPHRASE' | sudo tee /tmp/luks-password >/dev/null
sudo chmod 600 /tmp/luks-password

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

Both containers are formatted with that one passphrase. To give the swap volume a
different one, `cryptsetup luksChangeKey /dev/disk/by-partlabel/disk-main-swap`
afterwards — the partlabel, not `pN`, because the GPT order is ESP=1, swap=2,
root=3 and the numbering shifts whenever a partition is added.

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

`reboot`, remove the USB stick. You will be asked for the passphrase twice
(`cryptroot` and `cryptswap`) — or once if you gave them the same one and your
initrd caches it.

The passphrase is *not* in the flake and is not recoverable from it. The age key
on the machine cannot unlock the disk, and a lost passphrase means the data is
gone — the restic repository on host1 is the only copy that survives.

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

Log in as `leoguy77` with the password from `leon_password_hash`, then `sudo -i`.
`users.mutableUsers = false` means `passwd` will refuse — that is intended. To
change the password, re-encrypt the sops secret and rebuild.
