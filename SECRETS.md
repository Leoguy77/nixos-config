# Secrets Management with Agenix

## 🔐 Overview

This configuration uses [agenix](https://github.com/ryantm/agenix) for encrypted secrets management. Secrets are encrypted with age encryption and can only be decrypted by authorized recipients.

## 📁 Structure

```
secrets/
├── .gitkeep              # Placeholder (safe to commit)
├── secrets.nix           # Secret definitions & recipients (safe to commit)
├── ssh-key.age           # Encrypted SSH key (example)
├── api-token.age         # Encrypted API token (example)
└── ...                   # Add your secrets here
```

## 🚀 Quick Start

### 1. Install Agenix CLI

```bash
# One-time installation
nix profile install github:ryantm/agenix
```

### 2. Create Your First Secret

```bash
# Create an encrypted secret
echo "my-super-secret-value" > secrets/my-secret.age

# Edit with your favorite editor (automatically encrypts)
agenix -e secrets/my-secret.age
```

### 3. Define Recipients

Edit `secrets/secrets.nix`:

```nix
let
  leon = "ssh-rsa AAAA...";  # Your SSH public key
  surface = "ssh-ed25519 AAAA...";  # Host SSH key
in
{
  "my-secret.age".publicKeys = [ leon surface ];
}
```

### 4. Use in Configuration

In your NixOS modules:

```nix
{ config, agenix, ... }:

{
  imports = [ agenix.nixosModules.default ];
  
  age.secrets = {
    "my-secret".file = ../secrets/my-secret.age;
  };
  
  # Access the secret
  environment.variables.MY_SECRET = config.age.secrets.my-secret.path;
}
```

## 🔑 Recipients

Secrets can be decrypted by:

### SSH Public Keys
```nix
leon = "ssh-rsa AAAAB3NzaC1yc2E...";
```

### SSH Key Files
```nix
"/home/leon/.ssh/id_ed25519.pub"
```

### Age Public Keys
```nix
age1...  # Get with: age-keygen -y key.txt
```

## 📝 Common Use Cases

### SSH Host Keys
```nix
# secrets/secrets.nix
{
  "ssh-host-key.age".publicKeys = [ leon surface ];
}

# modules/nixos/services.nix
age.secrets."ssh-host-key".file = ../../secrets/ssh-host-key.age;
age.secrets."ssh-host-key".path = "/etc/ssh/ssh_host_ed25519_key";
age.secrets."ssh-host-key".mode = "600";
age.secrets."ssh-host-key".owner = "root";
```

### API Tokens
```nix
# secrets/secrets.nix
{
  "github-token.age".publicKeys = [ leon ];
}

# modules/home/development.nix
age.secrets."github-token".file = ../../secrets/github-token.age;
home.sessionVariables.GITHUB_TOKEN = config.age.secrets."github-token".path;
```

### Database Passwords
```nix
# secrets/secrets.nix
{
  "db-password.age".publicKeys = [ leon surface ];
}

# modules/nixos/services.nix
age.secrets."db-password".file = ../../secrets/db-password.age;
services.postgresql.extraConfig = ''
  password ${config.age.secrets."db-password".path}
'';
```

## 🔒 Security Best Practices

1. **Never commit unencrypted secrets** - Only `.age` files should be in git
2. **Limit recipients** - Only add keys that actually need access
3. **Rotate secrets regularly** - Update and re-encrypt periodically
4. **Use host keys for services** - Services should use host SSH keys, not user keys
5. **Backup your keys** - If you lose all recipient keys, secrets are unrecoverable

## 🛠️ Commands

### Encrypt a Secret
```bash
agenix -e secrets/my-secret.age
```

### Decrypt a Secret
```bash
agenix -d secrets/my-secret.age
```

### Edit a Secret
```bash
agenix -e secrets/my-secret.age  # Opens in $EDITOR
```

### List Secrets
```bash
agenix -l
```

### Re-encrypt with Updated Recipients
```bash
# Update secrets.nix with new recipients, then:
agenix -r  # Re-encrypt all secrets
```

## 📚 Examples

### Example: secrets/secrets.nix
```nix
let
  # User keys
  leon = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDAj4xwu7D5e0hN7+Tr46JZhvPGc/EehC7R22xAaHiypvU/620JZSakZID5+D6oIrG0z+my3BoweV+O3DpBoPvN9OOBlP05HsDf9AUY99io5wfWKkAKUZnXTHVoORwA/xp5DMHuPTS8cLKmqwBtAcEhL9+q4lVjDjZhagR69J7DycAC678YBZrH3g0yuciJBAaTIvZPDvlTeZHc3piKrlYRdjhFq6PJ8K7fi/RhtMOLDCFHV8kv71uV7+rD+isyPYhj3OAR2tyQxoBhxdqIQM7w+rPgm5km7rh58ErlWXC0ZsllPbLz/LVsoNPSq2GqnGGILb7vZE3ytD4lqEO1fhv4nXN7OlZPLO73Ti4b/RetqsmA0y6Yf58yLU+aTGTlZ6ytKd2gJx5/ne0jgoCV9fFaVnpxD0TBw0ME5jyABby9OlzpUm4Pheu/b3SSeH2/vYBLr/dAPLAd7ARz9ZP1BGm5BHjwWtsTrzsr3aRR+00o2VFLQcrwJyqGTwWzNvA0THfe5HS/+EZg142XgyI+nhm9vYI6rIXfnISYi4p+3TF0aUzAlWRy0LH/4UMCjQiCCEvBz9azPWecehUxCCfMAkIZQtc5MVcwz5kuNlgWYBBKF7aDCUHEG7GEG6Lm0U6eHfqkI48ajCCwvsMZmERuKtLr8vl9FbjucoGcp8Bp1XqXuw==";
  
  # Host keys (get with: ssh-keyscan -t ed25519 hostname)
  surface = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI...";
  
in
{
  # User-only secrets
  "personal-token.age".publicKeys = [ leon ];
  
  # Host + user secrets (for services)
  "ssh-host-key.age".publicKeys = [ leon surface ];
  "database-password.age".publicKeys = [ leon surface ];
}
```

### Example: Using in NixOS Module
```nix
{ config, pkgs, lib, agenix, ... }:

{
  imports = [ agenix.nixosModules.default ];
  
  age.secrets = {
    "github-token".file = ../../secrets/github-token.age;
    "ssh-host-key".file = ../../secrets/ssh-host-key.age;
    "ssh-host-key".path = "/etc/ssh/ssh_host_ed25519_key";
    "ssh-host-key".mode = "600";
    "ssh-host-key".owner = "root";
  };
  
  # Use in environment
  environment.variables.GITHUB_TOKEN = config.age.secrets."github-token".path;
  
  # Use in service
  services.openssh.hostKeys = [
    {
      path = config.age.secrets."ssh-host-key".path;
      type = "ed25519";
    }
  ];
}
```

## 🔗 Resources

- [Agenix GitHub](https://github.com/ryantm/agenix)
- [Age Encryption](https://age-encryption.org/)
- [NixOS Secrets Management](https://nixos.wiki/wiki/Secrets_Management)

---

## ⚠️ Important Notes

1. **Host SSH keys** are auto-generated by NixOS on first boot
2. **Get host public keys** with: `ssh-keyscan -t ed25519 hostname`
3. **Test secrets** after building: `sudo cat /run/agenix/<secret>.age`
4. **Backup secrets.nix** - it contains your recipient list

---

**Status:** ✅ Configured and Ready
**Last Updated:** 2026-06-28
