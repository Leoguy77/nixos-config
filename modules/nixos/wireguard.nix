# flipdot Hackspace WireGuard VPN — wg0, managed by NetworkManager
#
# "Per VPN in den Space": reachable only over LAN (192.168.3.0/24) and the
# WG network (192.168.6.0/24) — e.g. to open the door, access space devices.
# Ref: https://wiki.flipdot.org/en/IT-Infra-Services/wireguard
#
# Why NetworkManager instead of the NixOS systemd wireguard unit:
#  - wg0 already shows up as an NM connection in the KDE/GNOME GUI.
#  - openresolv can NOT order flipdot's resolver first when merged (implicit-metric
#    keys like NM's always precede explicit-metric keys), which forced the old
#    "exclusive" DNS. NM's per-connection `ipv4.dns-priority` is the proper way to
#    get flipdot DNS *first but still merged*, and it's conditional: while wg0 is
#    up NM pushes it via resolvconf, when the tunnel drops the DNS entry goes too.
#
# Security: the WireGuard private key lives in agenix
# (secrets/machine/kirito/wg0-private.age, encrypted to your keys + host key) and
# is injected into the NM connection at activation time, so it is never committed
# in plaintext and never baked into the Nix store.
{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.modules.wireguard;
  secretName = "machine/kirito/wg0-private.age";
  secretPath = config.age.secrets.${secretName}.path;
  # flipdot server (static, from the wiki)
  peerPubkey = "ymxWuu5f3nU/JjsZNDlBb4f0e9msRLk6cai/nQm2PlI=";
  endpoint = "157.90.144.95:51222";
in
{
  options.modules.wireguard = {
    enable = lib.mkEnableOption "flipdot WireGuard VPN (wg0, NetworkManager-managed)";

    # IP the flipdot admin assigned (192.168.6.x).
    address = lib.mkOption {
      type = lib.types.str;
      description = "flipdot-assigned 192.168.6.x/32 address.";
    };

    # flipdot DNS resolver applied to the wg0 NM connection while the tunnel is up.
    dns = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "192.168.3.254";
      description = "flipdot DNS resolver on wg0 (null disables).";
    };

    # Negative dns-priority => flipdot DNS is preferred over other connections'
    # resolvers (merged, NOT exclusive). Keeps .fd hostnames (mqtt.fd) resolving
    # while the rest of the resolver list stays available.
    dnsPriority = lib.mkOption {
      type = lib.types.str;
      default = "-50";
      description = "NetworkManager ipv4.dns-priority for wg0 (negative = preferred).";
    };
  };

  config = lib.mkIf cfg.enable {
    networking.networkmanager.enable = lib.mkDefault true;

    # (Re)create wg0 as a persistent NM connection at activation, sourcing the
    # private key from the agenix-decrypted secret. mkAfter => runs after agenix
    # has populated the secret. Idempotent: deletes then re-adds the profile.
    system.activationScripts.flipdotWg0 = lib.mkAfter ''
      set -e
      NMCLI=${pkgs.networkmanager}/bin/nmcli
      TR=${pkgs.coreutils}/bin/tr

      KEY="$("$TR" -d ' \n' < ${lib.escapeShellArg secretPath})"
      if [ -z "$KEY" ]; then
        echo "flipdot: WireGuard private key empty/missing at ${lib.escapeShellArg secretPath} — skipping wg0 setup" >&2
        exit 0
      fi

      "$NMCLI" connection delete wg0 >/dev/null 2>&1 || true
      "$NMCLI" connection add type wireguard ifname wg0 con-name wg0 \
        autoconnect yes \
        wireguard.private-key "$KEY" \
        wireguard.listen-port 51820 \
        wireguard.peer-routes yes \
        wireguard.ip4-auto-default-route 0 \
        wireguard.ip6-auto-default-route 0 \
        ipv4.method manual \
        ipv4.addresses ${lib.escapeShellArg cfg.address} \
        ${lib.optionalString (cfg.dns != null) "ipv4.dns ${lib.escapeShellArg cfg.dns}"} \
        ipv4.dns-priority ${cfg.dnsPriority} \
        ipv6.method ignore \
        >/dev/null

      # Add flipdot as a WG peer. The peer key and its properties MUST be given
      # as a SINGLE quoted argument in nmcli's `KEY prop=val prop=val` format.
      # Separate positional args after `+wireguard.peers` (endpoint / allowed-ips /
      # persistent-keepalive) are invalid and abort activation with
      #   Error: invalid <setting>.<property> 'endpoint'.
      # For multiple allowed-ips, repeat the `allowed-ips=` token — a single
      # comma-joined list confuses nmcli's peer parser.
      "$NMCLI" connection modify wg0 +wireguard.peers \
        "${peerPubkey} endpoint=${endpoint} allowed-ips=192.168.3.0/24 allowed-ips=192.168.6.0/24 persistent-keepalive=25"

      "$NMCLI" connection reload >/dev/null 2>&1 || true
      "$NMCLI" connection up wg0 >/dev/null 2>&1 || true
      true
    '';
  };
}
