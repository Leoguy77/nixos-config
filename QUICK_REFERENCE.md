# Quick Reference Card

## Build Commands

```bash
# Build and switch to new configuration
sudo nixos-rebuild switch --flake .#surface

# Build without switching
sudo nixos-rebuild build --flake .#surface

# Home Manager standalone
home-manager switch --flake .#leoguy77@surface

# Update flake inputs
nix flake update

# Check configuration
nix flake check
```

## Module Structure

```
nixos-config/
├── hosts/surface/          # Your machine config
│   ├── default.nix         # Main entry point
│   ├── hardware.nix        # Hardware overrides
│   └── home.nix            # User overrides
├── modules/
│   ├── nixos/              # System modules
│   │   ├── boot.nix
│   │   ├── system.nix
│   │   ├── services.nix
│   │   ├── packages.nix
│   │   ├── users.nix
│   │   └── security.nix
│   └── home/               # User modules
│       ├── core.nix
│       ├── development.nix
│       ├── desktop.nix
│       └── pi.nix
└── lib/                    # Shared utilities
```

## Enable/Disable Modules

In `hosts/surface/default.nix`:
```nix
{
  modules.boot.enable = true;
  modules.system.enable = true;
  modules.services.enable = true;
  modules.packages.enable = true;
  modules.users.enable = true;
  modules.security.enable = true;
  
  modules.home.core.enable = true;
  modules.home.development.enable = true;
  modules.home.desktop.enable = true;
  modules.home.pi.enable = true;
}
```

## Override Defaults

### System hostname
```nix
modules.system.hostName = "myhost";
```

### Add packages
```nix
modules.packages.extraPackages = with pkgs; [ telegram-desktop discord ];
```

### Disable dark mode
```nix
modules.home.desktop.darkMode = false;
```

### Change timezone
```nix
modules.system.timeZone = "America/New_York";
```

## Add New Host

1. Create `hosts/newhost/default.nix`
2. Add to `flake.nix`:
```nix
nixosConfigurations.newhost = nixpkgs.lib.nixosSystem {
  inherit system specialArgs;
  modules = commonModules ++ [ ./hosts/newhost ];
};
```
3. Build: `sudo nixos-rebuild switch --flake .#newhost`

## Add New Module

1. Create `modules/nixos/myfeature.nix`:
```nix
{ config, pkgs, lib, ... }:
let cfg = config.modules.myfeature; in
{
  options.modules.myfeature = {
    enable = lib.mkEnableOption "my feature";
  };
  config = lib.mkIf cfg.enable {
    # your config
  };
}
```
2. Import in host config
3. Enable: `modules.myfeature.enable = true`

## Documentation

- [MODULES.md](./MODULES.md) - Full module reference
- [MODULARIZATION_GUIDE.md](./MODULARIZATION_GUIDE.md) - Migration guide
- [README.md](./README.md) - Overview
