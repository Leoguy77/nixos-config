# Signed Commits

Commit signing is configured declaratively in
[`modules/home/base/core.nix`](../modules/home/base/core.nix) via Home Manager's
`programs.git` — it is not a repo-local hook.

## What's configured

```nix
programs.git = {
  signing = {
    key = myvars.git.signingKey;   # ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFZ0JSHt…
    signByDefault = true;
  };
  settings.gpg = {
    format = "ssh";
    "ssh".program = "/run/current-system/sw/bin/op-ssh-sign";
  };
};
```

`op-ssh-sign` resolves the matching private key from the 1Password vault (item
`Github`) — git passes it the public key, so no wrapper script is needed. The
same settings sign tags (`tag.gpgsign` follows `signByDefault`).

Because this lives in Home Manager, the effective config is checked with:

```bash
git config --get-regexp '^(commit|tag|gpg|user)\.'
```

and any override belongs in a host's `home.nix`, not in `git config` by hand —
a manual edit is overwritten on the next `home-manager switch`.

## Verifying

```bash
git log -1 --format='%h %G? %s'      # G = good signature
git cat-file -p HEAD | grep gpgsig   # raw signature block
```

`%G?` reports `N` (no signature) and `git log --show-signature` errors with:

```
error: gpg.ssh.allowedSignersFile needs to be configured and exist for ssh signature verification
```

**That is a verification gap, not a signing gap** — the commits do carry a valid
SSH signature (confirmed with `git cat-file -p`). Git cannot *check* it because
no `allowedSignersFile` is set. GitHub verifies them independently against the
uploaded key. To make local verification work, add to a host's `home.nix`:

```nix
programs.git.settings.gpg.ssh.allowedSignersFile = "~/.ssh/allowed_signers";
home.file.".ssh/allowed_signers".text = "leonschneider29@googlemail.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFZ0JSHt…";
```

## What is *not* enforced

There is **no** hook that blocks unsigned commits. `git commit --no-gpg-sign`
succeeds, and nothing checks the result. Signing happens because
`signByDefault = true`, not because anything forbids the alternative.

The `pi-extensions/enforce-signed-commits/` directory contains an old hook that
was meant to fill this role. **Do not install it**: `install.sh` overwrites
`.git/hooks/pre-commit`, which this repo generates from
[`.pre-commit-config.yaml`](../.pre-commit-config.yaml) (deadnix, nixfmt, statix)
— you would trade lint for a config check. If enforcement is wanted, implement it
as a `post-commit` check (git-hooks.nix only manages `pre-commit`) or as a CI
step, not by clobbering that file.

## Rotating the signing key

1. Generate/import the new key in 1Password and store the item holding it.
2. Update `vars/default.nix` → `git.signingKey` (used by `programs.git.signing.key`).
3. Upload the new public key to GitHub → Settings → SSH and GPG keys → *Signing keys*.
4. `home-manager switch` on every host that commits.

## Learn more

- [GitHub: signing commits](https://docs.github.com/en/authentication/managing-commit-signature-verification/signing-commits)
- [1Password SSH agent](https://developer.1password.com/docs/ssh/agent/)
- [git-format-signature](https://git-scm.com/docs/gitformat-signature)
