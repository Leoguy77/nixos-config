# NixOS Configuration Structure

This directory contains a **fully modular** NixOS configuration using flakes and Home Manager.

## Directory Structure

```
nixos-config/
├── flake.nix                      # Flake entry point with inputs
├── flake.lock                     # Locked flake dependencies
├── configuration.nix              # Main NixOS configuration (legacy)
├── home.nix                       # Home Manager configuration (legacy)
├── hardware-configuration.nix     # Hardware config (auto-generated)
├── lib/                           # Shared utility functions
│   └── default.nix
├── hosts/                         # Host-specific configurations
│   └── surface/
│       ├── default.nix            # Surface host configuration
│       ├── hardware.nix           # Surface hardware overrides
│       └── home.nix               # Surface user overrides
├── modules/
│   ├── nixos/                     # NixOS system modules
│   │   ├── default.nix            # Module index
│   │   ├── boot.nix               # Bootloader, kernel, hardware (with options)
│   │   ├── system.nix             # Core system, nix, networking (with options)
│   │   ├── services.nix           # Display, audio, SSH, power (with options)
│   │   ├── packages.nix           # System-wide packages (with options)
│   │   ├── users.nix              # User accounts (with options)
│   │   └── security.nix           # Security settings (with options)
│   └── home/                      # Home Manager modules
│       ├── default.nix            # Module index
│       ├── core.nix               # Git, GPG, Zsh, direnv (with options)
│       ├── development.nix        # Tmux, mise, 1password (with options)
│       ├── desktop.nix            # Kitty, Firefox, dark mode (with options)
│       └── pi.nix                 # Pi agent configuration (with options)
└── README.md                      # Usage instructions
```

## Key Features

### ✅ Modular Design
- Each module has **options** and **config** sections
- Use `lib.mkDefault` for overridable defaults
- Enable/disable modules with `modules.*.enable = true/false`

### ✅ Host-Specific Configurations
- `hosts/surface/` contains machine-specific settings
- Easy to add new hosts (e.g., `hosts/laptop/`, `hosts/server/`)
- Hardware overrides in `hardware.nix`
- User overrides in `home.nix`

### ✅ Reusable Modules
- All modules export options for customization
- Import modules via `./modules/nixos/default.nix` or `./modules/home/default.nix`
- Share utility functions via `lib/default.nix`

### ✅ Flake-Based
- Build via: `sudo nixos-rebuild switch --flake .#surface`
- Home Manager: `home-manager switch --flake .#leoguy77@surface`
- Legacy support via `configuration.nix` and `home.nix`

## Module Options Reference

### NixOS Modules (`modules/nixos/`)

| Module | Options | Description |
|--------|---------|-------------|
| `boot.nix` | `modules.boot.enable`<br>`modules.boot.systemdBoot`<br>`modules.boot.efi` | Bootloader configuration |
| `system.nix` | `modules.system.enable`<br>`modules.System.hostName`<br>`modules.System.timeZone`<br>`modules.System.locale`<br>`modules.System.keymap` | Core system settings |
| `services.nix` | `modules.services.enable`<br>`modules.services.x11`<br>`modules.services.plasma`<br>`modules.services.pipewire`<br>`modules.services.ssh`<br>`modules.services.autoCpufreq` | System services |
| `packages.nix` | `modules.packages.enable`<br>`modules.packages.extraPackages` | System packages |
| `users.nix` | `modules.users.enable`<br>`modules.users.mainUser`<br>`modules.users.userShell` | User accounts |
| `security.nix` | `modules.security.enable`<br>`modules.security.sudo` | Security settings |

### Home Manager Modules (`modules/home/`)

| Module | Options | Description |
|--------|---------|-------------|
| `core.nix` | `modules.home.core.enable`<br>`modules.home.core.username`<br>`modules.home.core.gitUserName`<br>`modules.home.core.gitUserEmail` | Git, GPG, Zsh, CLI tools |
| `development.nix` | `modules.home.development.enable`<br>`modules.home.development.tmux`<br>`modules.home.development.mise`<br>`modules.home.development.onepassword` | Dev tools |
| `desktop.nix` | `modules.home.desktop.enable`<br>`modules.home.desktop.kitty`<br>`modules.home.desktop.firefox`<br>`modules.home.desktop.darkMode` | Desktop apps |
| `pi.nix` | `modules.home.pi.enable`<br>`modules.home.pi.extensions` | Pi agent |

## Usage

### Build System (Flake)
```bash
sudo nixos-rebuild switch --flake .#surface
```

### Build Home Manager (Flake)
```bash
home-manager switch --flake .#leoguy77@surface
```

### Build System (Legacy)
```bash
sudo nixos-rebuild switch
```

### Update Flake Inputs
```bash
nix flake update
```

### Garbage Collection
```bash
nix-collect-garbage --delete-older-than 14d
```

## Adding New Hosts

1. Create directory: `mkdir -p hosts/newhost`
2. Create `hosts/newhost/default.nix`:
```nix
{ config, pkgs, lib, inputs, ... }:

{
  imports = [
    ../../hardware-configuration.nix
    ../../modules/nixos/boot.nix
    # ... other modules
  ];

  networking.hostName = "newhost";
  
  home-manager.users.leoguy77 = {
    imports = [
      ../../modules/home/core.nix
      # ... other modules
    ];
  };
}
```
3. Add to `flake.nix`:
```nix
nixosConfigurations.newhost = nixpkgs.lib.nixosSystem {
  inherit system;
  specialArgs;
  modules = commonModules ++ [ ./hosts/newhost ];
};
```

## Adding New Modules

1. Create `.nix` file in `modules/nixos/` or `modules/home/`
2. Define options and config:
```nix
{ config, pkgs, lib, ... }:

let
  cfg = config.modules.myModule;
in

{
  options.modules.myModule = {
    enable = lib.mkEnableOption "my module";
    # Add more options...
  };

  config = lib.mkIf cfg.enable {
    # Your configuration here
  };
}
```
3. Import in host configuration or `configuration.nix`/`home.nix`
4. Enable: `modules.myModule.enable = true;`

## Customization Examples

### Override System Hostname
```nix
# In hosts/surface/hardware.nix
{
  modules.system.hostName = "surface-custom";
}
```

### Add Extra Packages
```nix
# In hosts/surface/default.nix
{
  modules.packages.extraPackages = with pkgs; [
    telegram-desktop
    discord
  ];
}
```

### Disable Dark Mode
```nix
# In hosts/surface/home.nix
{
  modules.home.desktop.darkMode = false;
}
```

### Enable Custom Service
```nix
# In hosts/surface/default.nix
{
  modules.services.ssh = true;
  services.openssh.settings.PermitRootLogin = "yes";
}
```
