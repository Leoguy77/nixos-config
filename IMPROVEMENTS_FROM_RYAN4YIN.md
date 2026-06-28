# Suggested Improvements Based on ryan4yin/nix-config

After analyzing the [ryan4yin/nix-config](https://github.com/ryan4yin/nix-config) repository, here are key improvements you can adopt:

## 🎯 Key Differences & Recommendations

### 1. **Centralized Variables (`vars/`)**

**Ryan's Approach:**
- Uses a `vars/` directory for shared variables (username, networking, etc.)
- Imported as `myvars` in all modules via `specialArgs`

**Your Current Setup:**
- Hardcoded values in modules (e.g., username "leoguy77")

**Recommendation:**
```nix
# vars/default.nix
{ lib, ... }:
{
  username = "leoguy77";
  email = "leonschneider29@googlemail.com";
  fullName = "Leon";
  
  networking = {
    hostsAddr = {
      surface = {
        ipv4 = "192.168.1.100";
        ipv6 = "::1";
        iface = "wlan0";
      };
    };
  };
}
```

**Benefit:** Single source of truth, easier to maintain across multiple hosts.

---

### 2. **Auto-Scan Module Directories**

**Ryan's Approach:**
```nix
# modules/nixos/base/default.nix
{ mylib, ... }:
{
  imports = mylib.scanPaths ./.;
}
```

**Your Current Setup:**
- Manual imports in each host configuration

**Recommendation:**
Update your `lib/default.nix`:
```nix
{ lib, ... }:
{
  # Auto-scan all .nix files in a directory
  scanPaths = path:
    builtins.map (f: (path + "/${f}")) (
      builtins.attrNames (
        lib.attrsets.filterAttrs (
          name: type:
          (type == "directory") || 
          ((name != "default.nix") && (lib.strings.hasSuffix ".nix" name))
        ) (builtins.readDir path)
      )
    );
}
```

Then in modules:
```nix
# modules/nixos/default.nix
{ mylib, ... }:
{
  imports = mylib.scanPaths ./.;
}
```

**Benefit:** Add new modules without updating import lists.

---

### 3. **Multiple Nixpkgs Versions**

**Ryan's Approach:**
```nix
# flake.nix
inputs = {
  nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-26.05";
  nixpkgs-master.url = "github:nixos/nixpkgs/master";
};

# outputs/default.nix
pkgs-stable = import inputs.nixpkgs-stable { inherit system; };
pkgs-master = import inputs.nixpkgs-master { inherit system; };
```

**Your Current Setup:**
- Single nixpkgs input

**Recommendation:**
Add stable/master branches for packages that need specific versions:
```nix
# In flake.nix
inputs = {
  nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-26.05";
};

# Pass to specialArgs
specialArgs = {
  inherit inputs;
  pkgs-stable = import nixpkgs-stable { inherit system; };
};
```

**Benefit:** Use stable packages for critical tools, unstable for latest features.

---

### 4. **Separate TUI/GUI Configurations**

**Ryan's Approach:**
```
home/
├── base/           # Shared TUI configuration
│   ├── tui/
│   │   ├── shell/
│   │   ├── editors/
│   │   └── dev-tools.nix
│   └── core/
└── gui/            # GUI-specific additions
    ├── terminal/
    ├── zed-editor.nix
    └── media.nix
```

**Your Current Setup:**
- Mixed TUI/GUI in same modules

**Recommendation:**
Split your home modules:
```
modules/home/
├── base/           # Core CLI tools (git, zsh, tmux)
│   ├── shell.nix
│   ├── git.nix
│   └── editors.nix
├── tui/            # TUI-specific (btop, yazi, zellij)
│   ├── btop.nix
│   └── file-manager.nix
└── gui/            # GUI-specific (kitty, firefox, dark mode)
    ├── terminal.nix
    ├── browser.nix
    └── theme.nix
```

**Benefit:** Reuse base config across servers (TUI only) and desktops (full GUI).

---

### 5. **Host-Specific Home Configs**

**Ryan's Approach:**
```
home/hosts/linux/
├── idols-ai.nix      # Host-specific overrides
├── idols-ruby.nix
└── k3s-prod-1-master-1.nix
```

**Your Current Setup:**
- Single home.nix for all hosts

**Recommendation:**
```nix
# hosts/surface/home.nix
{
  imports = [
    ../../modules/home/base
    ../../modules/home/gui
    ./home-overrides.nix  # Surface-specific
  ];
}

# hosts/server/home.nix  
{
  imports = [
    ../../modules/home/base
    ../../modules/home/tui
    # No GUI modules for headless server
  ];
}
```

**Benefit:** Different home configs per host type.

---

### 6. **Secrets Management with agenix**

**Ryan's Approach:**
```nix
inputs = {
  agenix = {
    url = "github:ryantm/agenix";
    inputs.nixpkgs.follows = "nixpkgs";
  };
};
```

**Your Current Setup:**
- SSH keys stored in plain text (stub files)

**Recommendation:**
```nix
# Add to flake.nix
inputs = {
  agenix.url = "github:ryantm/agenix";
};

# secrets/ssh-key.age (encrypted)
# modules/nixos/security.nix
{ agenix, ... }:
{
  imports = [ agenix.nixosModules.default ];
  
  age = {
    identityPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    secrets = {
      "ssh-key".file = ../secrets/ssh-key.age;
    };
  };
}
```

**Benefit:** Encrypted secrets in git, safe to share publicly.

---

### 7. **Disk Management with disko**

**Ryan's Approach:**
```nix
inputs = {
  disko = {
    url = "github:nix-community/disko";
    inputs.nixpkgs.follows = "nixpkgs";
  };
};

# hosts/ai/disko-fs.nix
{ disko.devices = { ... }; }
```

**Your Current Setup:**
- hardware-configuration.nix (generated)

**Recommendation:**
For new installations or reproducible setups:
```nix
# hosts/surface/disko.nix
{ disko.devices = {
    disk = {
      main = {
        device = "/dev/nvme0n1";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "500M";
              type = "EF00";
              content = { type = "filesystem"; format = "vfat"; };
            };
            root = {
              size = "100%";
              content = { type = "filesystem"; format = "ext4"; };
            };
          };
        };
      };
    };
  };
}
```

**Benefit:** Declarative disk layouts, reproducible installations.

---

### 8. **Pre-commit Hooks for Code Quality**

**Ryan's Approach:**
```nix
inputs.pre-commit-hooks = {
  url = "github:cachix/git-hooks.nix";
  inputs.nixpkgs.follows = "nixpkgs";
};

# checks.pre-commit-check
hooks = {
  nixfmt.enable = true;
  typos.enable = true;  # spell checker
  prettier.enable = true;
};
```

**Your Current Setup:**
- No pre-commit hooks

**Recommendation:**
```nix
# Add to flake.nix
inputs.pre-commit-hooks.url = "github:cachix/git-hooks.nix";

# In outputs
checks = forAllSystems (system: {
  pre-commit-check = pre-commit-hooks.lib.${system}.run {
    src = ./.;
    hooks = {
      nixfmt = {
        enable = true;
        settings.width = 100;
      };
    };
  };
});
```

**Benefit:** Auto-format nix code before commits, catch errors early.

---

### 9. **Custom Overlays**

**Ryan's Approach:**
```nix
# overlays/default.nix
[
  inputs.nur-ryan4yin.overlays.default
  (final: prev: {
    my-custom-package = ...;
  })
]
```

**Your Current Setup:**
- No custom overlays

**Recommendation:**
```nix
# overlays/default.nix
[
  # Add custom package overlays here
  (final: prev: {
    # Example: override a package
    vscode = prev.vscode.override {
      isInsiders = false;
    };
  })
]

# flake.nix
outputs = { ... }@inputs: {
  nixosConfigurations.surface = nixpkgs.lib.nixosSystem {
    modules = [{
      nixpkgs.overlays = import ./overlays inputs;
    }];
  };
};
```

**Benefit:** Customize packages without modifying nixpkgs.

---

### 10. **Development Shell**

**Ryan's Approach:**
```nix
devShells = forAllSystems (system: {
  default = pkgs.mkShell {
    packages = with pkgs; [
      nixfmt
      deadnix
      statix
      typos
      prettier
    ];
    shellHook = ''
      echo "Development shell ready!"
    '';
  };
});
```

**Your Current Setup:**
- No dev shell

**Recommendation:**
```nix
# Add to flake.nix outputs
devShells = {
  x86_64-linux.default = pkgs.mkShell {
    packages = with pkgs; [
      nixfmt-classic
      deadnix
      statix
      alejandra
    ];
  };
};
```

Usage: `nix develop`

**Benefit:** Consistent development environment for all contributors.

---

### 11. **Binary Cache Substituters**

**Ryan's Approach:**
```nix
nixConfig = {
  extra-substituters = [
    "https://cache.numtide.com"
    "https://nix-gaming.cachix.org"
  ];
  extra-trusted-public-keys = [
    "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
  ];
};
```

**Your Current Setup:**
- Default substituters only

**Recommendation:**
```nix
# flake.nix
nixConfig = {
  extra-substituters = [
    "https://cache.nixos.org"
    "https://nix-community.cachix.org"
  ];
  extra-trusted-public-keys = [
    "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
  ];
};
```

**Benefit:** Faster builds from community caches.

---

### 12. **System Tags & Metadata**

**Ryan's Approach:**
```nix
# outputs/x86_64-linux/src/ai.nix
{
  name = "ai";
  tags = [ "desktop" "gaming" "nvidia" ];
  # ... configuration
}
```

**Recommendation:**
Add metadata to your host configurations:
```nix
# hosts/surface/default.nix
{
  config = {
    system.metadata = {
      name = "surface";
      type = "desktop";
      hardware = "surface-pro";
      cpu = "intel";
      gpu = "intel-iris";
    };
  };
}
```

**Benefit:** Better organization, filtering, and automation.

---

## 📋 Priority Implementation Order

### High Priority (Do First)
1. ✅ **Centralized variables** - Easy win, immediate benefit
2. ✅ **Auto-scan modules** - Reduces maintenance
3. ✅ **Pre-commit hooks** - Improves code quality
4. ✅ **Dev shell** - Better developer experience

### Medium Priority
5. **Separate TUI/GUI** - Better modularity
6. **Multiple nixpkgs** - More flexibility
7. **Binary caches** - Faster builds
8. **Host-specific home configs** - Better organization

### Lower Priority (Advanced)
9. **Agenix secrets** - Only if sharing publicly
10. **Disko** - Only for new installations
11. **Custom overlays** - When you need package customization
12. **System tags** - Nice to have for organization

---

## 🚀 Quick Start Implementation

### Step 1: Add Variables
```bash
mkdir -p vars
```
Create `vars/default.nix` with your shared values.

### Step 2: Update lib/
Add `scanPaths` function to `lib/default.nix`.

### Step 3: Add Pre-commit Hooks
```bash
nix profile install nixpkgs#git nixpkgs#nixfmt-classic
```

### Step 4: Create Dev Shell
Add `devShells` to your `flake.nix`.

---

## 📚 Additional Resources

- [Ryan's NixOS & Flakes Book](https://github.com/ryan4yin/nixos-and-flakes-book) - Comprehensive guide
- [Ryan's i3-kickstarter](https://github.com/ryan4yin/nix-config/tree/i3-kickstarter) - Simpler starting point
- [agenix](https://github.com/ryantm/agenix) - Secrets management
- [disko](https://github.com/nix-community/disko) - Declarative disk layouts
- [git-hooks.nix](https://github.com/cachix/git-hooks.nix) - Pre-commit hooks

---

## ⚠️ Important Notes

1. **Don't copy blindly** - Understand what each change does
2. **Start small** - Implement one improvement at a time
3. **Test thoroughly** - Use `nix flake check` and `nix build`
4. **Keep backups** - Version control is your friend
5. **Your needs differ** - Adapt recommendations to your workflow
