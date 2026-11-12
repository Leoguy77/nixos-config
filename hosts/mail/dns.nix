# The lsinfra.de zone, as declared records.
#
# `modules.dns.push.enable` in ./default.nix makes this host publish it. PURGE is
# on, so anything absent here is DELETED from Cloudflare on the next rebuild —
# this list is the zone, not a patch on top of it.
#
# Deliberately NOT here:
#   _acme-challenge.*   written by ACME during cert issuance; see `ignore` below
#   _validation-persist, _domainkey._acme  Let's Encrypt account bookkeeping
#
# Records for host1/asuna are in hosts/asuna/dns.nix — they follow that machine,
# not this one. Both files feed the same registry (mail's default.nix imports
# both).
{
  config,
  mylib,
  myvars,
  ...
}:

let
  ipv4 = myvars.networking.hostsAddr.mail.ipv4;
  ipv6 = myvars.networking.hostsAddr.mail.ipv6;

  # dnscontrol's TTL() is in seconds; the export had Cloudflare's "automatic"
  # recorded as 1. CF_PROXY_ON records must use TTL(1).
  auto = "TTL(1)";

  rr =
    text:
    mylib.publishDns {
      zone = "lsinfra.de";
      inherit text;
    };
in
{
  modules.dns.records = [
    # ── This host (mail) ──────────────────────────────────────────────────
    # DNS-only: SMTP/IMAP/ManageSieve cannot traverse the HTTP proxy, and an MX
    # target must resolve to the real host.
    (rr ''A("mail", "${ipv4}", CF_PROXY_OFF, ${auto})'')
    (rr ''AAAA("mail", "${ipv6}", CF_PROXY_OFF, ${auto})'')
    (rr ''A("webmail", "${ipv4}", CF_PROXY_OFF, ${auto})'')
    (rr ''AAAA("webmail", "${ipv6}", CF_PROXY_OFF, ${auto})'')
    (rr ''TXT("mail", "v=spf1 a -all")'')

    # Mail autodiscovery + MTA-STS, all aliases onto this host. nginx picks the
    # vhost by Host header; each name has its own certificate.
    (rr ''CNAME("autoconfig", "mail.lsinfra.de.", CF_PROXY_OFF, TTL(300))'')
    (rr ''CNAME("autodiscover", "mail.lsinfra.de.", CF_PROXY_OFF, TTL(300))'')
    (rr ''CNAME("mta-sts", "mail.lsinfra.de.", CF_PROXY_OFF, TTL(300))'')

    # ── Mail routing ──────────────────────────────────────────────────────
    (rr ''MX("@", 10, "mail.lsinfra.de.")'')
    # `mx` authorises the MX target only. No a:/ip4: for host1: that would
    # publish its address.
    (rr ''TXT("@", "v=spf1 mx -all")'')
    (rr ''TXT("_dmarc", "v=DMARC1; p=reject; rua=mailto:postmaster@lsinfra.de")'')
    # MTA-STS. The `id` is read from the module, not typed: senders ignore a
    # policy whose id differs from this record, so a stale literal here would
    # silently pin every sender to the previous rules.
    (rr ''TXT("_mta-sts", "v=STSv1; id=${config.modules.mail.mtaStsId}")'')
    (rr ''TXT("_smtp._tls", "v=TLSRPTv1; rua=mailto:postmaster@lsinfra.de")'')

    # ── Mail autoconfig (client autodiscovery) ────────────────────────────
    # Only protocols actually served: 143/587/POP3/JMAP/CalDAV/CardDAV are not
    # enabled on this box, and advertising them sent clients into dead ports.
    (rr ''SRV("_imaps._tcp", 0, 1, 993, "mail.lsinfra.de.", TTL(300))'')
    (rr ''SRV("_submissions._tcp", 0, 1, 465, "mail.lsinfra.de.", TTL(300))'')

    # ── DKIM ──────────────────────────────────────────────────────────────
    # `mail` is the selector rspamd actually signs with. Its keypair lives in
    # sops (dkim_mail_private_key) so this record can be declared before first
    # boot instead of pasted in afterwards. The public half belongs here.
    (rr ''TXT("mail._domainkey", "v=DKIM1; k=rsa; p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAvzCJZiLH2Ugi8XDZqNu1WWYOWqrOxHF+Nyk2iTnxrAHNFOgIIES33esGUdW7f5N8BZfP+RBK7uCUStqE99jptJk+I63P0y9EgKUD/OD7L6XnIv2nu2OIggL2LmAVj7zI3ITfQ3lZXyXZryoAVx0zelKYkB/rANAEM/v9thg3Mx0lpB9yg4wovK+++CC24MpxQMXa9t4JFiiMCbKaSYvyl8L3lvc4w+/BGlAW9I1l0z+eqx7fpJsn+xbkjmUSkafr4fdEkJt0zqJenLpKzWftpyd056WqYWkO6Ci89tj6ot78XeRDAA6PJy5knI8AfxW0wpkg53qMwBnMexXMrqxeDwIDAQAB")'')

    # Retired selectors from the pre-NixOS server: nothing signs with these any
    # more, and SPF only authorises mail.<domain>. Kept only so a message sent
    # before the migration still verifies; drop them once mail has run a week.
    (rr ''TXT("v1-ed25519-20260810._domainkey", "v=DKIM1; k=ed25519; h=sha256; p=ZzzsPGo8I8cSasdyfeI00j5TOPzlgMd9N3HHSREIgy0=")'')
    (rr ''TXT("v1-ed25519-20261105._domainkey", "v=DKIM1; k=ed25519; h=sha256; p=WxPjierQBB4rIQmhu6ErH8BFpJrZtpF50T+ZR/hUxNc=")'')
    (rr ''TXT("v1-rsa-20260810._domainkey", "v=DKIM1; k=rsa; h=sha256; p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAsedoxQUgDEdP3Hy6Uc3UJlfbVVh648jEgycF9uE+c1QBARg5iNIIZQjBmQcZMMOIssuw221K3Grr7fD3gqsV7XQuRlPn1bsPMqeNLYGfmO7VJ0lO8354CfHvcCQbdh9t2z1Lo0SSCoJDfF23kdSiQffpJe1d5TXwnU1E7et9Q08G7L6KSrcyFZh05RkQO35XctCa/vg5wxnE7berDdyKmhAXzC2SR27VcjV2YSJ2W9Bwtt8lF6BX06nQT4URkFpKKgtJnaGrqsv4kUg5C/Rhw2ReRHOEEh1UcBED0SZHqM0TZhyyK7T1KdwL/n1azSaT6HkH8QwRaPbDyv6rZQRJxQIDAQAB")'')
    (rr ''TXT("v1-rsa-20261105._domainkey", "v=DKIM1; k=rsa; h=sha256; p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAp7cWMot1sdcClkeG1J8MEQRnINHJD0PMDAJV6NoBk9W3LK84gtp/1BpV7CNj7nEUGpGIMSoAy/UDdnyOU7fNUQW7E59dHKFLC/+Gsb/FOTgG+eFsJ6cS61mSNj7HbOuZucDJNgTubtQtaE7JHFZfWCmiUBXuF7F9GnZH7633kItpk2QrkB+fEGyw4XaGwytjd4Kx5GlOMX0gDeMnPF0H4r8Jp8xHVQTOvN9bSIHcCuHr0ibArtemJ0qoSEyURtHSP/s9DqnVNE0axI1CbmZAllUfsNudEUtGrTYEwBJgmHpOSIrXdsBuxfChwkwqTTgsrctav/AqHKGproh5zJBWqwIDAQAB")'')

    # ── TLS policy ────────────────────────────────────────────────────────
    # DANE (RFC 7672). Usage 2 = DANE-TA, 1 = SPKI, 1 = SHA-256, so this pins the
    # public key of ISRG Root X2 — the trust anchor this chain actually serves
    # (leaf -> YE1 -> Root YE -> ISRG Root X2).
    #
    # Deliberately NOT usage 3 (DANE-EE, the leaf key): the 36 records that used
    # to live here were exactly that, and every one had gone stale against the
    # live leaf, so remote senders were hard-failing. A leaf key changes on each
    # ACME renewal; the anchor does not. Pinning the anchor costs nothing in
    # security here because the leaf is proof of possession of the key the
    # anchor vouches for, and it cannot silently rot.
    #
    # Only `_25._tcp`: DANE for SMTP applies to port 25, which is the only port
    # remote MTAs connect to. This host does not accept mail on 465 from the
    # outside — that is submission, used by authenticated local users.
    (rr ''TLSA("_25._tcp.mail", 2, 1, 1, "762195c225586ee6c0237456e2107dc54f1efc21f61a792ebd515913cce68332")'')

    # accounturi pins issuance to one ACME account; drop that clause if the
    # account is ever recreated, or renewal fails.
    (rr ''CAA("@", "issue", "letsencrypt.org; accounturi=https://acme-v02.api.letsencrypt.org/acme/acct/3618244571", TTL(300))'')
    (rr ''CAA("@", "iodef", "mailto:postmaster@lsinfra.de", TTL(300))'')
  ];
}
