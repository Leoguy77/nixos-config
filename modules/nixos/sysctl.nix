# Kernel + journald hardening for a headless server.
#
# Single purpose: reduce the attack/reconnaissance surface of the TCP/IP and
# swap stacks, and keep the journal from filling a small disk. No service of
# its own; purely declarative sysctls and journald limits.
{
  config,
  lib,
  ...
}:

{
  options.modules.sysctl = {
    enable = lib.mkEnableOption "kernel and journald hardening";
  };

  config = lib.mkIf config.modules.sysctl.enable {
    boot.kernel.sysctl = {
      "vm.swappiness" = 100;
      # RocksDB (Stalwart's data store) mmaps a lot.
      "vm.max_map_count" = 262144;
      "net.core.somaxconn" = 1024;
      "net.ipv4.tcp_syncookies" = 1;

      # A server routes nothing and has one static uplink, so an ICMP redirect
      # is either a misconfiguration or an attempt to steer the default route.
      # `secure_redirects` only narrows which gateways may redirect — still a
      # trust decision this box has no reason to make.
      "net.ipv4.conf.all.accept_redirects" = false;
      "net.ipv4.conf.all.secure_redirects" = false;
      "net.ipv4.conf.all.send_redirects" = false;
      "net.ipv6.conf.all.accept_redirects" = false;
      # Source-routed packets let a sender pick the return path past the
      # firewall. Nothing legitimate sends them.
      "net.ipv4.conf.all.accept_source_route" = false;
      "net.ipv6.conf.all.accept_source_route" = false;
      # Log, rather than silently drop, packets whose source address could not
      # have arrived on that interface — the cheap signal of spoofing.
      "net.ipv4.conf.all.log_martians" = true;
      # TIME_WAIT assassination (RFC 1337): without it a spoofed RST can tear
      # down a half-closed connection, which is the exact shape of an SMTP
      # session waiting on DATA.
      "net.ipv4.tcp_rfc1337" = true;
    };

    services.journald.settings.Journal = {
      SystemMaxUse = "500M";
      RuntimeMaxUse = "64M";
    };
  };
}
