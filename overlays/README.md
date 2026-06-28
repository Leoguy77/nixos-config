# Custom Overlays

## 📦 What Are Overlays?

Overlays allow you to **customize or override packages** without modifying nixpkgs. They're functions that modify the package set.

## 🎯 Use Cases

1. **Override package options** - Enable features, change defaults
2. **Replace package versions** - Use older/newer versions
3. **Add custom packages** - Your own packages or from GitHub
4. **Apply patches** - Fix bugs before upstream merges

## 📁 Structure

```
overlays/
├── default.nix      # Main overlay index (list of overlays)
├── README.md        # This file
├── vscode.nix       # Example: VSCode customization
└── custom-tools/    # Example: Custom packages
    └── default.nix
```

## 🚀 Quick Start

### 1. Create an Overlay

Create `overlays/my-overlay.nix`:

```nix
# Customize VSCode
final: prev: {
  vscode = prev.vscode.override {
    isInsiders = false;
  };
}
```

### 2. Add to default.nix

Edit `overlays/default.nix`:

```nix
[
  (import ./my-overlay.nix)
]
```

### 3. Enable in Flake

In `flake.nix`:

```nix
nixpkgs.overlays = import ./overlays inputs;
```

### 4. Use the Package

```nix
environment.systemPackages = [ pkgs.vscode ];
```

## 📝 Examples

### Override Package Options

```nix
# overlays/vscode.nix
final: prev: {
  vscode = prev.vscode.override {
    isInsiders = false;
    withNodejs = true;
  };
}
```

### Replace Package Version

```nix
# overlays/nodejs.nix
final: prev: {
  nodejs = prev.nodejs-18_x;  # Use Node.js 18 instead of default
}
```

### Add Custom Package from GitHub

```nix
# overlays/custom-tool.nix
final: prev: {
  my-tool = final.callPackage (final.fetchFromGitHub {
    owner = "username";
    repo = "my-tool";
    rev = "v1.0.0";
    hash = "sha256-...";
  }) { };
}
```

### Local Custom Package

```nix
# overlays/my-package/default.nix
{ pkgs, lib, stdenv, ... }:

stdenv.mkDerivation {
  pname = "my-package";
  version = "1.0.0";
  src = ./src;
  
  buildInputs = [ pkgs.libuv ];
  
  meta = {
    description = "My custom package";
    license = lib.licenses.mit;
  };
}

# overlays/default.nix
[
  (final: prev: {
    my-package = final.callPackage ./my-package { };
  })
]
```

### Apply a Patch

```nix
# overlays/patched-package.nix
final: prev: {
  my-package = prev.my-package.overrideAttrs (old: {
    patches = (old.patches or []) ++ [
      ./fix-bug.patch
    ];
  });
}
```

## 🔧 Advanced Patterns

### Conditional Overlays

```nix
# overlays/conditional.nix
final: prev: {
  my-package = if prev.stdenv.isLinux
    then prev.my-package-linux
    else prev.my-package-darwin;
}
```

### Multiple Package Overrides

```nix
# overlays/dev-tools.nix
final: prev: {
  vscode = prev.vscode.override { isInsiders = false; };
  nodejs = prev.nodejs-18_x;
  python3 = prev.python311;
}
```

### Chain Overlays

```nix
# overlays/default.nix
[
  (import ./base.nix)    # Base customizations
  (import ./dev.nix)     # Dev tools
  (import ./gui.nix)     # GUI apps
]
```

## 🎨 Best Practices

1. **One overlay per concern** - Keep overlays focused
2. **Document overrides** - Explain why you're overriding
3. **Test thoroughly** - Overlays can break packages
4. **Pin versions** - Use specific commits/tags for GitHub sources
5. **Minimize overlays** - Only override when necessary

## 🐛 Debugging

### List Available Packages

```bash
nix repl '<nixpkgs>'
> pkgs.vscode.version
"1.85.0"
```

### Check Overlay Effects

```bash
nix build .#packages.x86_64-linux.vscode
```

### Test in Isolation

```nix
# test-overlay.nix
let
  pkgs = import <nixpkgs> {
    overlays = [ (import ./overlays/default.nix) ];
  };
in pkgs.my-package
```

## 📚 Resources

- [NixOS Wiki: Overlays](https://nixos.wiki/wiki/Overlays)
- [Nixpkgs Manual: Overlays](https://nixos.org/manual/nixpkgs/stable/#chap-overlays)
- [Overlays Chapter in Nix Book](https://nix.dev/tutorials/overlays)

---

## ⚠️ Common Pitfalls

1. **Infinite recursion** - Don't reference `final.my-package` in the same overlay
2. **Wrong override syntax** - Use `.override` for functions, `.overrideAttrs` for derivations
3. **Missing hashes** - Always include `hash` for `fetchFromGitHub`
4. **Breaking changes** - Test overlays after nixpkgs updates

---

**Status:** ✅ Ready for Custom Overlays
**Last Updated:** 2026-06-28
