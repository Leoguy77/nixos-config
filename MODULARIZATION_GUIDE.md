# Modularization Guide

This guide explains the modularization changes made to your NixOS configuration.

## What Changed?

### Before
- Flat structure with basic module imports
- No option definitions (hardcoded values)
- No host-specific configurations
- Limited reusability

### After
- ✅ **Option-based modules** with `lib.mkEnableOption` and `lib.mkDefault`
- ✅ **Host-specific configs** in `hosts/surface/`
- ✅ **Module indexes** for cleaner imports
- ✅ **Shared utilities** in `lib/`
- ✅ **Proper flake structure** with `nixosConfigurations` and `homeConfigurations`

## New Directory Structure

```
nixos-config/
├── flake.nix                      ← Enhanced with proper outputs
├── configuration.nix              ← Legacy support, now enables modules
├── home.nix                       ← Legacy support, now enables modules
├── lib/
│   └── default.nix                ← NEW: Shared utility functions
├── hosts/
│   └── surface/                   ← NEW: Host-specific config
│       ├── default.nix            ← Main host entry point
│       ├── hardware.nix           ← Hardware overrides
│       └── home.nix               ← User overrides
└── modules/
    ├── nixos/
    │   ├── default.nix            ← NEW: Module index
    │   ├── boot.nix               ← ENHANCED: With options
    │   ├── system.nix             ← ENHANCED: With options
    │   ├── services.nix           ← ENHANCED: With options
    │   ├── packages.nix           ← ENHANCED: With options
    │   ├── users.nix              ← ENHANCED: With options
    │   └── security.nix           ← ENHANCED: With options
    └── home/
        ├── default.nix            ← NEW: Module index
        ├── core.nix               ← ENHANCED: With options
        ├── development.nix        ← ENHANCED: With options
        ├── desktop.nix            ← ENHANCED: With options
        └── pi.nix                 ← ENHANCED: With options
```

## Module Pattern

Each module now follows this pattern:

```nix
{ config, pkgs, lib, ... }:

let
  cfg = config.modules.<moduleName>;
in

{
  # Define options
  options.modules.<moduleName> = {
    enable = lib.mkEnableOption "<module description>";
    someOption = lib.mkOption {
      type = lib.types.str;
      default = "default-value";
      description = "Description";
    };
  };

  # Apply configuration conditionally
  config = lib.mkIf cfg.enable {
    # Your settings here
    # Use lib.mkDefault for overridable values
  };
}
```

## Benefits

### 1. **Overridable Defaults**
```nix
# In module
boot.loader.systemd-boot.enable = lib.mkDefault true;

# In host config - overrides the default
boot.loader.systemd-boot.enable = false;
```

### 2. **Conditional Enablement**
```nix
# Enable/disable entire modules
modules.services.ssh = true;
modules.services.ssh = false;  # Won't configure SSH
```

### 3. **Host-Specific Overrides**
```nix
# hosts/surface/hardware.nix
{
  modules.system.hostName = "surface";
}

# hosts/laptop/hardware.nix
{
  modules.system.hostName = "laptop";
  modules.services.bluetooth.enable = true;  # Laptop-specific
}
```

### 4. **Reusable Across Hosts**
```nix
# Share common configuration
nixosConfigurations.surface = nixpkgs.lib.nixosSystem {
  modules = commonModules ++ [ ./hosts/surface ];
};

nixosConfigurations.laptop = nixpkgs.lib.nixosSystem {
  modules = commonModules ++ [ ./hosts/laptop ];
};
```

## Migration Path

### Option 1: Use Legacy Files (Current)
Your existing `configuration.nix` and `home.nix` still work:
```bash
sudo nixos-rebuild switch
```

### Option 2: Use Flake (Recommended)
```bash
sudo nixos-rebuild switch --flake .#surface
```

### Option 3: Gradual Migration
1. Keep using legacy files
2. Test new modules in `hosts/surface/`
3. Switch to flake when ready

## Testing

### Check Module Options
```bash
nix flake show .#surface
```

### Build Without Applying
```bash
sudo nixos-rebuild build --flake .#surface
```

### Dry Run
```bash
sudo nixos-rebuild dry-build --flake .#surface
```

## Adding New Modules

### Step 1: Create Module File
```nix
# modules/nixos/myfeature.nix
{ config, pkgs, lib, ... }:

let
  cfg = config.modules.myfeature;
in

{
  options.modules.myfeature = {
    enable = lib.mkEnableOption "my feature";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.myfeature;
      description = "My feature package";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];
  };
}
```

### Step 2: Add to Module Index
```nix
# modules/nixos/default.nix
{
  myfeature = ./myfeature.nix;
  # ... other modules
}
```

### Step 3: Import in Host Config
```nix
# hosts/surface/default.nix
{
  imports = [
    ../../modules/nixos/myfeature.nix
  ];
  
  modules.myfeature.enable = true;
}
```

## Best Practices

### ✅ Do
- Use `lib.mkDefault` for values that should be overridable
- Use `lib.mkIf cfg.enable` for conditional configuration
- Keep modules focused (single responsibility)
- Document options with `description`
- Use `lib.mkEnableOption` for boolean enable flags

### ❌ Don't
- Hardcode values without `lib.mkDefault`
- Create monolithic modules
- Skip option descriptions
- Mix NixOS and Home Manager in same module

## Next Steps

1. **Test the build**: `sudo nixos-rebuild switch --flake .#surface`
2. **Review options**: Check `MODULES.md` for all available options
3. **Customize**: Add overrides in `hosts/surface/hardware.nix` or `home.nix`
4. **Extend**: Add new modules as needed

## Resources

- [NixOS Options Search](https://search.nixos.org/options)
- [Nixpkgs Manual](https://nixos.org/manual/nixpkgs/stable/)
- [Home Manager Options](https://nix-community.github.io/home-manager/options.xhtml)
