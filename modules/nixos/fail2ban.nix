# Fail2ban: escalating bans on auth-failure repeat offenders.
#
# Single purpose: brute-force/abuse defence via fail2ban. Which jails are on
# is data, configured by enable on the host (the sshd jail is the universal
# one; mail.nix adds dovecot/postfix/roundcube jails itself).
{
  config,
  lib,
  ...
}:

{
  options.modules.fail2ban = {
    enable = lib.mkEnableOption "fail2ban brute-force defence";
  };

  config = lib.mkIf config.modules.fail2ban.enable {
    services.fail2ban = {
      enable = true;
      maxretry = 5;
      bantime = "1h";
      # Repeat offenders come back the moment the hour is up, from the same
      # address or the same /24. Escalating bans cost nothing and turn a
      # rotating-code brute force into a one-time event.
      bantime-increment = {
        enable = true;
        multipliers = "2";
        maxtime = "1w";
      };
      ignoreIP = [
        "127.0.0.1/8"
        "::1"
      ];
      # Ban history must outlive the longest ban, or a restart forgets who is
      # banned and an escalated offender starts from zero. The stock 1d is
      # shorter than `maxtime` below.
      daemonSettings.DEFAULT.dbpurgeage = "30d";
      jails.sshd.settings = {
        enabled = true;
        backend = "systemd";
        findtime = "10m";
      };

      # Every other jail's ban expires and the offender simply waits it out;
      # this one reads fail2ban's own log, so a source that collects bans keeps
      # collecting them. `bantime.increment` then escalates this to the 1w cap.
      # findtime is long because it counts *bans*, not auth failures.
      jails.recidive = {
        enabled = true;
        filter = "recidive";
        settings = {
          backend = "systemd";
          findtime = "1d";
          maxretry = 3;
          bantime = "1w";
        };
      };
    };
  };
}
