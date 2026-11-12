# DNS records belonging to asuna (formerly "host1", still Debian until it is
# migrated to NixOS). Registered, not published: `modules.dns.push` on `mail`
# renders every record for lsinfra.de, so this file decides WHAT is published
# while hosts/mail decides THAT it is.
#
# Split out of hosts/mail/dns.nix so the records follow the machine they belong
# to. Every value here is secret-backed: this repository is public, and these are
# the addresses Cloudflare is proxying.
#
# NOTE: this file is NOT a NixOS module — it has no `imports` target and the
# directory intentionally has no default.nix, because the flake auto-discovers
# every hosts/*/default.nix as a buildable system and asuna cannot build yet
# (no hardware-configuration.nix). hosts/mail/default.nix imports this file
# directly. Rename it to default.nix once the hardware config exists.
{ mylib, ... }:

let
  rr =
    text:
    mylib.publishDns {
      zone = "lsinfra.de";
      inherit text;
    };
in
{
  modules.dns.records = [
    # Nothing is served at the apex, so it is parked on TEST-NET-1 (RFC 5737).
    # Proxied, so Cloudflare's edge answers and the value never resolves.
    # Declared literally rather than via host1_ipv4 so PURGE keeps it.
    (rr ''A("@", "192.0.2.1", CF_PROXY_ON, TTL(1))'')

    # Proxied, so the origin never appears in DNS. TTL 1 = "automatic", which
    # Cloudflare requires for proxied records.
    (rr ''A("meshview", host1_ipv4, CF_PROXY_ON, TTL(1))'')
    (rr ''A("nix-cache", host1_ipv4, CF_PROXY_ON, TTL(1))'')
    (rr ''AAAA("nix-cache", host1_ipv6, CF_PROXY_ON, TTL(1))'')
    (rr ''A("pelican", host1_ipv4, CF_PROXY_ON, TTL(1))'')
    # Not proxied: serves non-HTTP, so it needs the real address.
    (rr ''A("wing", host1_ipv4, CF_PROXY_OFF, TTL(1))'')
  ];
}
