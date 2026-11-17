# A login credential the flake can actually reproduce.
#
# Single purpose: give the human account a password and an authorised key, so a
# fresh install is reachable without a console step. Without this a reinstall
# produces a machine nobody can log into:
#
#   - nothing in this repo set a password or an authorized key for the desktop
#     user, and `modules.accounts` (which does set keys) is only enabled by
#     profiles/server.nix
#   - disko-install calls `nixos-install --no-root-password`
#   - `modules.ssh` sets `PermitRootLogin = "no"` on desktops
#
# `users.mutableUsers` was hiding it. With the default `true`, the hash lives in
# the live /etc/shadow, written once by `passwd` and never rebuilt, so today's
# machine looks fine while a fresh install gets nothing.
#
# So this module turns `mutableUsers` off. That is the actual fix, not a
# side effect: the flake becomes the only source of the password, which means
#   - no drift between "what the flake says" and "what /etc/shadow holds"
#   - nothing to persist for ephemeral root — /etc/shadow is regenerated from
#     the declaration every boot and lands on the same hash
#   - `passwd` stops working, which is correct here; change the password by
#     re-encrypting the sops secret, not by editing one machine
# It matches what this repo already does on servers: accounts.nix sets the same
# flag, so a laptop and a VPS now behave the same way.
#
# Ordering is sops-nix's, not ours: `neededForUsers` moves the secret to
# /run/secrets-for-users and makes the `users` activation step depend on the
# decryption step, so the hash file exists before /etc/shadow is rewritten.
{
  config,
  lib,
  myvars,
  ...
}:

let
  cfg = config.modules.login;
in
{
  options.modules.login = {
    enable = lib.mkEnableOption "a password + authorised key for the main user";

    passwordUser = lib.mkOption {
      type = lib.types.str;
      default = myvars.username;
      description = ''
        Account that gets {option}`passwordSecret`. One account only: a hashed
        password file carries a single hash, so two users would silently end up
        with the same password — a second account needs its own hash, which
        means a second option, not a second name here.
      '';
    };

    passwordSecret = lib.mkOption {
      type = lib.types.str;
      # Keyed by user, not by host: one human has one install password, and every
      # host this module is enabled on reads the same secret. Same shape as
      # johnae/world's profiles/admin-user/user.nix, which shares a single hash
      # across all its hosts — the only change is keeping it in sops instead of
      # hardcoding it in a public repo.
      default = "${config.modules.login.passwordUser}_password_hash";
      defaultText = lib.literalExpression ''"''${config.modules.login.passwordUser}_password_hash"'';
      description = ''
        sops secret holding the `mkpasswd` hash (the full `$6$…` string) for
        {option}`passwordUser`.

        One password, all hosts. A workstation login is not a per-machine
        credential — you are the same person at every keyboard, so rotating it
        once should change it everywhere. Generating a per-host hash would mean
        N secrets to rotate and N chances for one to drift into a lockout.

        Deliberately *not* the mailserver's `leon_password_hash`. That one is an
        IMAP credential that dovecot reads and restarts on; keeping your OS login
        separate means rotating your laptop password does not silently change
        your mail password, and a drifted mail hash cannot reinstall this machine
        with a login nobody knows.
      '';
    };

    keys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ myvars.ssh.key ];
      description = ''
        SSH public keys authorised for {option}`passwordUser`. The Token2
        OpenPGP auth subkey is public and already in git, so baking it into an
        installer ISO leaks nothing a `git clone` does not.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Not `mkDefault`: an immutable /etc/shadow is the point of the module, and a
    # host that quietly kept it mutable would silently lose the flake-owned
    # password again. A host that needs a mutable account should not enable this.
    users.mutableUsers = false;

    users.users.${cfg.passwordUser} = {
      hashedPasswordFile = config.sops.secrets.${cfg.passwordSecret}.path;
      openssh.authorizedKeys.keys = cfg.keys;
    };

    # Leave `mode` at sops-nix's 0400 default. The only reader is
    # users-groups.pl running as root, which can open a root-owned 0400 file.
    #
    # Setting the nested attribute is what *declares* the secret: sops.secrets is
    # an attrsOf submodule, so this both creates the entry and flips the flag.
    # Assigning `= { }` alongside it would be a second definition of the same
    # dynamic attribute and fails to evaluate.
    sops.secrets.${cfg.passwordSecret}.neededForUsers = true;
  };
}
