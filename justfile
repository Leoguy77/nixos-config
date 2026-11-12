# Run `just` inside `nix develop .#` — deploy and secrets both need sops, which
# is deliberately not on the system PATH.
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

# Decrypt the secrets to stdout, deriving the PGP key from ~/.ssh/GPG.
secrets:
    #!/usr/bin/env bash
    set -euo pipefail
    export GNUPGHOME=$(mktemp -d)
    trap 'rm -rf "$GNUPGHOME"' EXIT
    ssh-to-pgp -private-key -i ~/.ssh/GPG 2>/dev/null | gpg --batch --import 2>/dev/null
    sops -d secrets/secrets.sops.yaml

# Re-encrypt to the current recipients in .sops.yaml. deploy.sh already does this for its own host.
updatekeys:
    #!/usr/bin/env bash
    set -euo pipefail
    export GNUPGHOME=$(mktemp -d)
    trap 'rm -rf "$GNUPGHOME"' EXIT
    ssh-to-pgp -private-key -i ~/.ssh/GPG 2>/dev/null | gpg --batch --import 2>/dev/null
    sops updatekeys --yes secrets/secrets.sops.yaml

# Format the tree.
fmt:
    nix fmt

# Lint everything the flake exposes.
check:
    nix flake check
