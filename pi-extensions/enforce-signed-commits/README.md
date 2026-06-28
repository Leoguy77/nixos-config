# Enforce Signed Commits Extension

This extension **prevents unsigned commits** by enforcing Git commit signing with your 1Password SSH agent.

## 🔒 What It Does

1. **Validates Git signing configuration** before every commit
2. **Checks 1Password SSH agent** is running and accessible
3. **Verifies allowed_signers file** exists and is configured
4. **Blocks unsigned commits** with clear error messages
5. **Auto-fixes common issues** when possible

## 🚀 Installation

### Option 1: Enable via Pi Extension
```bash
# The extension will be automatically loaded by Pi
```

### Option 2: Manual Setup
```bash
# Run the setup script
./pi-extensions/enforce-signed-commits/setup.sh
```

## 📋 Requirements

- 1Password CLI (`op`) installed
- 1Password SSH agent running
- Git configured for SSH signing

## 🔧 Configuration

The extension automatically configures:

```bash
# Git signing settings
commit.gpgsign = true
gpg.format = ssh
gpg.ssh.program = /run/current-system/sw/bin/op-ssh-sign
gpg.ssh.allowedSignersFile = ~/.ssh/allowed_signers
tag.gpgsign = true
```

## ✅ Verification

Test the extension:
```bash
# Check signing status
git config --get commit.gpgsign

# Test a commit (should be signed)
git commit --allow-empty -m "Test commit"

# Verify signature
git log -1 --show-signature
```

## 🛠️ Troubleshooting

### 1Password SSH Agent Not Running
```bash
# Start the agent
eval $(op ssh-agent --start)

# Or via systemd
systemctl --user start 1password-ssh-agent
```

### Missing Allowed Signers File
```bash
# The extension creates this automatically
# Located at: ~/.ssh/allowed_signers
```

### Signature Verification Failed
```bash
# Ensure your SSH key is in 1Password
# And the allowed_signers file contains your key
```

## 📝 Usage

Once installed, the extension works automatically:

1. **Pre-commit hook** runs before every commit
2. **Validates configuration** and SSH agent
3. **Blocks commit** if signing is not properly configured
4. **Shows helpful error messages** with fix instructions

## 🎯 Benefits

- ✅ **Never commit unsigned code again**
- ✅ **Automatic validation** before commits
- ✅ **Clear error messages** when issues occur
- ✅ **Auto-fix common problems**
- ✅ **Works with 1Password SSH agent**

## 📚 Related

- [Git Signed Commits](https://docs.github.com/en/authentication/managing-commit-signature-verification/signing-commits)
- [1Password SSH Agent](https://developer.1password.com/docs/ssh/agent/)
- [NixOS Git Configuration](../../modules/home/core.nix)
