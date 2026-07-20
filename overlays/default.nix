# Custom package overlays
# Overlays customize or override packages from nixpkgs without modifying it.
#
# These overlays are imported in host configs via:
#   nixpkgs.overlays = import ./overlays;
#
# With useGlobalPkgs = true (set in host configs), overlays applied here
# affect both NixOS system packages and Home Manager packages.
#
# Each overlay is a function: final: prev: { ... }
# - final: The final package set (with all overlays applied)
# - prev: The previous package set (before this overlay)

[
  # ── Example: Override a package with custom options ──────────────
  # (final: prev: {
  #   vscode = prev.vscode.override { isInsiders = false; };
  # })

  # ── Example: Add a custom package from this repo ─────────────────
  # (final: prev: {
  #   my-custom-tool = final.callPackage ./my-custom-tool { };
  # })

  # ── Example: Pin a package to a different version ────────────────
  # (final: prev: {
  #   nodejs = prev.nodejs-18_x;
  # })
]
