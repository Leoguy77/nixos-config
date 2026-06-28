# Custom package overlays
# Use overlays to customize or override packages without modifying nixpkgs
#
# Usage in flake.nix:
#   nixpkgs.overlays = import ./overlays inputs;
#
# Each overlay is a function: final: prev: { ... }
# - final: The final package set (with all overlays applied)
# - prev: The previous package set (before this overlay)

[
  # Example 1: Override a package with custom options
  # (final: prev: {
  #   vscode = prev.vscode.override {
  #     isInsiders = false;
  #   };
  # })
  
  # Example 2: Add a custom package
  # (final: prev: {
  #   my-custom-tool = final.callPackage ./my-custom-tool { };
  # })
  
  # Example 3: Replace a package with a different version
  # (final: prev: {
  #   nodejs = prev.nodejs-18_x;
  # })
]
