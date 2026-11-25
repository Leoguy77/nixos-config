# Shell baseline for hosts without home-manager.
#
# Deliberately basic: servers are not a daily driver. This exists only to fix
# two things that are broken out of the box, and adds nothing else.
#
#   1. Backspace typed spaces instead of deleting.
#   2. Every login opened the `zsh-newuser-install` wizard.
#
# Desktops are unaffected: they get zsh from `modules/home/base/core.nix` via
# home-manager. Enable this from profiles/server.nix only — it sets ZDOTDIR
# system-wide, which makes zsh ignore `~/.zshrc`, and on a desktop that would
# silently discard the whole home-manager configuration.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.modules.zsh;

  zshrc = ''
    autoload -Uz compinit && compinit -C

    setopt HIST_FCNTL_LOCK HIST_IGNORE_DUPS SHARE_HISTORY

    # ZDOTDIR is /etc, which is read-only: without this, zsh tries to write its
    # history next to the rc file and loses it.
    HISTFILE=~/.zsh_history
    HISTSIZE=5000
    SAVEHIST=5000

    PROMPT='%F{blue}%n@%m%f %F{yellow}%~%f > '
  '';
in

{
  options.modules.zsh = {
    enable = lib.mkEnableOption "a basic system-wide zsh configuration (hosts without home-manager)";
  };

  config = lib.mkIf cfg.enable {
    programs.zsh.enable = true;

    # kitty advertises TERM=xterm-kitty, which base terminfo has no entry for.
    # ZLE then cannot resolve `kbs`, so Backspace arrives as a literal space and
    # nothing is ever deleted. Terminfo only, not kitty — a server has no
    # business pulling a GUI stack.
    environment.systemPackages = [ pkgs.kitty.terminfo ];

    # zsh runs zsh-newuser-install on login when none of .zshenv, .zprofile,
    # .zshrc, .zlogin exists in $HOME. Declarative users never get those files,
    # so a server hits the wizard every session. ZDOTDIR relocates the lookup; it
    # reaches the shell via /etc/set-environment, which /etc/zshenv sources
    # before any startup file is read, so it is in place in time.
    environment.variables.ZDOTDIR = "/etc/zsh";
    environment.etc."zsh/.zshrc".text = zshrc;
  };
}
