# Signed Commits Enforcement

## 🔒 Extension Installed: `enforce-signed-commits`

This repository now has **automatic enforcement** of signed commits. All commits MUST be signed with your 1Password SSH key.

## ✅ What's Protected

1. **Pre-commit Hook** - Runs before every commit
2. **Configuration Validation** - Checks all signing settings
3. **1Password SSH Agent** - Verifies agent is running
4. **Blocked Unsigned Commits** - No way to bypass

## 📁 Extension Location

```
pi-extensions/enforce-signed-commits/
├── extension.json          # Extension metadata
├── README.md               # Extension documentation
├── setup.sh                # Configuration script
├── install.sh              # Quick install script
└── hooks/
    └── pre-commit          # The enforcement hook
```

## 🚀 How It Works

### Before Every Commit

The pre-commit hook automatically:

1. ✅ Checks `commit.gpgsign` is enabled
2. ✅ Verifies `gpg.format` is set to `ssh`
3. ✅ Confirms `SSH_AUTH_SOCK` is set (1Password agent)
4. ✅ Validates `allowedSignersFile` exists
5. ✅ Checks 1Password CLI is installed

### If Any Check Fails

```
🔒 Enforce Signed Commits - Checking configuration...

✗ Commit signing is NOT enabled
  Fix: git config commit.gpgsign true

╔════════════════════════════════════════════════════════╗
║  COMMIT BLOCKED: 1 configuration issue(s) found        ║
╚════════════════════════════════════════════════════════╝

Run the setup script to fix all issues:
  ./pi-extensions/enforce-signed-commits/setup.sh
```

### If All Checks Pass

```
🔒 Checking commit signing configuration...

✓ Commit signing is enabled
✓ Using SSH for signing
✓ SSH agent is configured
✓ Allowed signers file exists

✓ All signing checks passed!

Proceeding with signed commit...
```

## 🛠️ Installation (Already Done)

The extension is already installed and active. To reinstall or update:

```bash
# Quick install
./pi-extensions/enforce-signed-commits/install.sh

# Or run full setup
./pi-extensions/enforce-signed-commits/setup.sh
```

## 🔧 Configuration

Your Git is configured with:

```bash
commit.gpgsign = true
gpg.format = ssh
gpg.ssh.program = /run/current-system/sw/bin/op-ssh-sign
gpg.ssh.allowedSignersFile = ~/.ssh/allowed_signers
tag.gpgsign = true
```

## 📝 Verifying Signed Commits

### Check Last Commit
```bash
git log -1 --show-signature
```

### Check Multiple Commits
```bash
git log --show-signature -5
```

### Verify Specific Commit
```bash
git show --show-signature <commit-hash>
```

### Expected Output
```
Good "git" signature for leonschneider29@googlemail.com
with RSA key SHA256:3bUpuxxjGx3Uha/N2M/WXXVZEqCNZS7LPn2Aeu1ifVw
```

## 🔍 Troubleshooting

### 1. "SSH_AUTH_SOCK is not set"

**Problem:** 1Password SSH agent not running

**Fix:**
```bash
eval $(op ssh-agent --start)
```

### 2. "Allowed signers file not found"

**Problem:** Missing `~/.ssh/allowed_signers`

**Fix:**
```bash
./pi-extensions/enforce-signed-commits/setup.sh
```

### 3. "1Password CLI (op) not found"

**Problem:** 1Password CLI not installed

**Fix:**
```bash
# On NixOS, it's usually in your path
# Or install from: https://1password.com/downloads/command-line/
```

### 4. "Commit signing is not enabled"

**Problem:** Git config missing

**Fix:**
```bash
git config commit.gpgsign true
git config gpg.format ssh
git config gpg.ssh.program op-ssh-sign
```

## 🚫 Can I Bypass This?

**Short answer:** No (by design)

**Long answer:** The pre-commit hook will block unsigned commits. Even if you try to bypass with `--no-verify`, the repository's Git configuration requires signing:

```bash
# This won't work - Git itself will reject it
git commit --no-gpg-sign  # ERROR: Git requires signed commits
```

## 📚 Related Files

- `pi-extensions/enforce-signed-commits/` - Extension source
- `~/.ssh/allowed_signers` - Your SSH public key for verification
- `.git/hooks/pre-commit` - Installed hook (auto-generated)

## 🎯 Benefits

✅ **Security** - All commits are cryptographically signed
✅ **Verification** - Easy to verify commit authenticity
✅ **Compliance** - Meets security requirements
✅ **Audit Trail** - Clear chain of custody for code
✅ **Automatic** - No manual steps needed

## 📖 Learn More

- [GitHub: Signing Commits](https://docs.github.com/en/authentication/managing-commit-signature-verification/signing-commits)
- [1Password SSH Agent](https://developer.1password.com/docs/ssh/agent/)
- [Git Tools: Signing Work](https://git-scm.com/book/en/v2/Git-Tools-Signing-Work)

---

## ⚠️ Important Notes

1. **Don't commit the `.git/hooks/` directory** - It's auto-generated per-repo
2. **Keep 1Password running** - Required for signing
3. **Backup your allowed_signers file** - Needed for verification
4. **This is intentional** - Unsigned commits are blocked by design

---

**Last Updated:** 2026-06-28
**Extension Version:** 1.0.0
**Status:** ✅ Active and Enforcing
