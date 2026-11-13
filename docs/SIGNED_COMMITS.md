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

## What is enforced now

A `commit-msg` hook refuses to let git write an unsigned commit. It is declared
in [`flake.nix`](../flake.nix) under `checks.<system>.pre-commit-check` and
installed by the devShell's `shellHook`, so entering `nix develop .#` on any
machine self-installs it.

It checks two things, because either alone is bypassable:

| Attempt | Result |
|---|---|
| plain `git commit` | allowed (and signed) |
| `git commit --no-gpg-sign` | **refused** — the flag is in git's argv |
| `git -c commit.gpgsign=false commit` | **refused** — the hook reads the effective config |
| `git config --unset commit.gpgsign` | allowed, because the global setting still says `true` |
| `git commit --no-verify` | **skipped** — see below |

### Why `commit-msg` and not `pre-commit`

`pre-commit` runs before the message exists; `commit-msg` is the last stage before
git writes the object. Anything later (`post-commit`) is a notification: the
commit already exists and a hook can no longer stop it.

### The one gap: `--no-verify`

`git commit --no-verify` skips every hook in this repository, including this one.
That is git's own escape hatch and **cannot be closed from inside a repo** — a
hook cannot veto its own suppression.

**It is now closed server-side.** A repository ruleset named `main` requires
verified signatures on the default branch:

```
remote: - Commits must have verified signatures.
remote:   Found 1 violation: ef188be8cd2444790524ba9f7f3ee29e5147b0da
 ! [remote rejected] HEAD -> main (push declined due to repository rule violations)
```

That also catches commits made from a machine that never entered the devShell,
which a hook never sees. The policy is versioned at
`.github/rulesets/main.json` and applied with
`nix shell nixpkgs#gh -c scripts/apply-rulesets.sh` — the file is the source of
truth, but **committing it does not apply it**; only the script does.

Two members of the ruleset are not about signing but are on by default because
rewriting published history costs more than it ever saves: `non_fast_forward`
(no force push) and `deletion` (no deleting `main`).

### Known interaction: the flake-lock bot

`.github/workflows/update-flake-lock.yml` is currently failing, but **not** because
of this ruleset: its job gets `403` on push because
`repos/Leoguy77/nixos-config/actions/permissions/workflow` is
`default_workflow_permissions: read`. That is a permissions problem.

Fixing it with `contents: write` will not be enough. `stefanzweifel/git-auto-commit-action`
commits **locally** with `git commit` and pushes over HTTPS; GitHub's web-flow
signature only covers commits created through the API. That commit is unsigned,
so `required_signatures` will reject it. Pick one:

- **Bypass actor** for the workflow — e.g. `RepositoryRole` admin, or the GitHub
  Actions app — scoped so only that identity skips the rule. Simplest; the daily
  lock bump is mechanical and reviewed by nobody anyway.
- **Commit through the API** (`gh api` / `peter-evans/create-pull-request`) so
  GitHub signs it, then open a PR instead of pushing to `main` — the ruleset only
  applies to the default branch, so a PR from a bot branch works without a bypass.

### Don't install the old extension

The `pi-extensions/enforce-signed-commits/` directory contains an older hook that
predates this. **Do not install it**: its `install.sh` overwrites
`.git/hooks/pre-commit`, which git-hooks.nix generates from these same flake
checks — you would trade deadnix/nixfmt/statix for a config check.

## Rotating the signing key

1. Generate/import the new key in 1Password and store the item holding it.
2. Update `vars/default.nix` → `git.signingKey` (used by `programs.git.signing.key`).
3. Upload the new public key to GitHub → Settings → SSH and GPG keys → *Signing keys*.
4. `home-manager switch` on every host that commits.

## Learn more

- [GitHub: signing commits](https://docs.github.com/en/authentication/managing-commit-signature-verification/signing-commits)
- [1Password SSH agent](https://developer.1password.com/docs/ssh/agent/)
- [git-format-signature](https://git-scm.com/docs/gitformat-signature)
