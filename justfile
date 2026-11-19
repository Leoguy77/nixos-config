# Run `just` inside `nix develop .#` to get the flake's tooling. sops and gpg are
# also on the system PATH (modules/nixos/packages.nix), so secrets works either way.
set shell := ["bash", "-euo", "pipefail", "-c"]

# Default host for the deploy/iso recipes.
host := "mail"

# Show what is available.
default:
    @just --list

# Install <host> through nixos-anywhere. Prompts for the LUKS passphrase and mints the host key, which is also its sops identity.
deploy target h=host disk="/dev/vda":
    scripts/deploy.sh {{h}} {{target}} {{disk}}

# Same, partition/format only in a throwaway VM. Touches no real disk.
deploy-vm target h=host disk="/dev/vda":
    VM_TEST=1 scripts/deploy.sh {{h}} {{target}} {{disk}}

# Build the per-host installer ISO. Needs a static address in vars/default.nix; symlinks to /tmp/iso-<host>.
iso h=host:
    #!/usr/bin/env bash
    set -euo pipefail
    nix build ".#installerIso-{{h}}" -o "/tmp/iso-{{h}}"
    iso=$(readlink -f "/tmp/iso-{{h}}"/iso/*.iso)
    printf '\n%s\n  %s bytes\n  %s\n' "$iso" \
      "$(stat -Lc %s "$iso")" "$(nix hash file "$iso")"

# Build a host's system closure without deploying it.
build h=host:
    nix build ".#nixosConfigurations.{{h}}.config.system.build.toplevel" --no-link --print-out-paths

# Emergency path: refresh inputs, prove every server host builds, push the lock,
# then deploy each one. For when waiting out CI's ~13h is not acceptable — a fresh
# nginx/sudo/openssl advisory, not a routine bump.
#
# Push BEFORE deploying, not after: autoUpgrade pulls the *pushed* commit, so a
# lock that was deployed but never pushed gets reverted on the host's next hourly
# run. That ordering is the point of the recipe.
#
# Both the host list and the addresses are derived — server hosts from their
# profile import, addresses from vars/. A new server needs no edit here.

# Emergency input refresh across all server hosts.
update-servers:
    #!/usr/bin/env bash
    set -euo pipefail

    user=$(nix eval --raw --impure --expr '(import ./vars {}).username')
    hosts=$(grep -l 'profiles/server\.nix' hosts/*/default.nix | cut -d/ -f2)
    [ -n "$hosts" ] || { echo "update-servers: no server hosts" >&2; exit 1; }
    echo "server hosts: $(echo $hosts)"

    nix flake update

    # Build every server before touching git, so a lock that does not compile
    # never reaches the branch autoUpgrade reads.
    for h in $hosts; do
      echo ":: building $h"
      nix build ".#nixosConfigurations.$h.config.system.build.toplevel" --no-link
    done

    # Commit only flake.lock, even if other files are dirty. `--` keeps git from
    # reading the path as a flag. Signing comes from commit.gpgsign.
    if git diff --quiet -- flake.lock; then
      echo "flake.lock unchanged, nothing to push"
    else
      git commit -m "chore(deps): emergency lock bump" -- flake.lock
      git push
    fi

    for h in $hosts; do
      addr=$(nix eval --raw --impure --expr \
        "(import ./vars {}).networking.hostsAddr.$h.ipv4")
      echo ":: deploying $h to $user@$addr"
      nixos-rebuild switch --flake ".#$h" \
        --target-host "$user@$addr" --elevate=sudo
    done

# Decrypt the secrets to stdout. sops uses the PGP identity already in your
# keyring: the Token2 card (23CDB62B…), tapped for PIN. No ssh-to-pgp step —
# the card carries only subkeys and ~/.ssh/GPG is a *different* key that is not
# a recipient in .sops.yaml.

# Decrypt the secrets to stdout.
secrets:
    sops -d secrets/secrets.sops.yaml

# Re-encrypt to the current recipients in .sops.yaml. deploy.sh already does this for its own host.
updatekeys:
    sops updatekeys --yes secrets/secrets.sops.yaml

# Format the tree.
fmt:
    nix fmt

# Lint everything the flake exposes.
check:
    nix flake check

# Summarise the DMARC aggregate reports sitting in the mail box's .DMARC folder.
dmarc target="leoguy77@91.132.147.216" folder="/var/vmail/lsinfra.de/leon/mail/.DMARC":
    #!/usr/bin/env bash
    set -euo pipefail
    # sudo: /var/vmail is 0700 virtualMail. The account is in wheel with
    # passwordless sudo, so this needs no prompt.
    ssh {{target}} "sudo nix shell nixpkgs#python3 -c python3 - {{folder}}" < scripts/dmarc-report.py
