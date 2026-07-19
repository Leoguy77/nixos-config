# NixOS modules index
# Re-export all NixOS modules for easier imports
{
  boot = ./boot.nix;
  system = ./system.nix;
  services = ./services.nix;
  packages = ./packages.nix;
  users = ./users.nix;
  security = ./security.nix;
  backup = ./backup.nix;
  onepassword = ./onepassword.nix;
}
