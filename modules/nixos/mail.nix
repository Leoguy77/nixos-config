# Mail stack: nixos-mailserver (Postfix + Dovecot + rspamd + opendkim) plus
# Roundcube webmail.
#
# Everything is Nix-declared: accounts, aliases, quotas, DKIM keys, TLS. No
# setup wizard, no configuration that lives in a database Nix cannot read.
# That is the whole reason this module exists — the previous Stalwart setup
# kept its real configuration in RocksDB, writable only through a web UI on
# first boot, so the flake never described the running server.
#
# TLS layout (one public IPv4, two names):
#
#   webmail.<domain> ──> nginx :80 (ACME webroot) and :443 (Roundcube)
#   mail.<domain>    ──> Postfix :25/:465/:587, Dovecot :143/:993, Sieve :4190
#
# A single certificate is issued for mail.<domain> over HTTP-01 and shared:
# nginx serves the challenge on :80 for that name, Postfix and Dovecot read the
# same files from /var/lib/acme. No TLS passthrough and no ALPN: the NixOS ACME
# module cannot do standalone/ALPN at all (its only non-DNS modes are
# `webroot`, `listenHTTP` and `s3Bucket`), and it does not need to.
{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.modules.mail;

  # DKIM keys are private key material, so they live outside the Nix store
  # (which is world-readable). rspamd reads them at runtime.
  dkimDir = "/var/lib/dkim";

  firstAccount = "${builtins.head (builtins.attrNames cfg.accounts)}@${cfg.domain}";
in

{
  options.modules.mail = {
    enable = lib.mkEnableOption "the mail server (Postfix, Dovecot, rspamd, Roundcube)";

    hostname = lib.mkOption {
      type = lib.types.str;
      description = "Mail hostname (MX, SMTP, IMAP, TLS certificate).";
      example = "mail.example.com";
    };

    webmailHostname = lib.mkOption {
      type = lib.types.str;
      description = ''
        Hostname for the Roundcube webmail UI. Must differ from {option}`hostname`
        so that only one nginx vhost owns port 443 for a given name.
      '';
      example = "webmail.example.com";
    };

    domain = lib.mkOption {
      type = lib.types.str;
      description = "The mail domain being served (the part after the @).";
      example = "example.com";
    };

    acmeEmail = lib.mkOption {
      type = lib.types.str;
      description = "Contact address for Let's Encrypt.";
    };

    accounts = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            hashedPasswordFile = lib.mkOption {
              type = lib.types.nullOr lib.types.path;
              default = null;
              description = ''
                File containing the account's password hash, as produced by
                `mkpasswd -m sha-512`. Use a sops secret: a hash is still a
                credential, just not a plaintext one.
              '';
            };

            passwordFile = lib.mkOption {
              type = lib.types.nullOr lib.types.path;
              default = null;
              description = ''
                File containing the plaintext password. Prefer
                {option}`hashedPasswordFile`; this exists for secrets managers
                that hand out cleartext.
              '';
            };

            aliases = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Extra addresses delivered to this account.";
            };

            quota = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              example = "4G";
              description = "Per-account mailbox quota. Null means the default.";
            };
          };
        }
      );
      default = { };
      description = ''
        Login accounts, keyed by the local part (`leon` becomes
        `leon@<domain>`).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.hostname != cfg.webmailHostname;
        message = "modules.mail.hostname and modules.mail.webmailHostname must differ.";
      }
      {
        assertion = cfg.accounts != { };
        message = ''
          modules.mail.accounts is empty: the server would accept mail for
          nobody and Dovecot would have no logins.
        '';
      }
    ];

    # ── The mail stack ─────────────────────────────────────────────────────
    mailserver = {
      enable = true;
      fqdn = cfg.hostname;
      domains = [ cfg.domain ];

      # Tracks mailserver *data-layout* migrations, not system.stateVersion.
      # 5 is the current level (required by enableManageSieve). A fresh install
      # starts here; an existing server would have to migrate up instead.
      stateVersion = 5;

      # 50 MiB, also used for Roundcube's upload ceiling.
      messageSizeLimit = 52428800;

      accounts = lib.mapAttrs' (
        name: account:
        lib.nameValuePair "${name}@${cfg.domain}" (
          {
            inherit (account) aliases;
          }
          // lib.optionalAttrs (account.quota != null) { inherit (account) quota; }
          // lib.optionalAttrs (account.hashedPasswordFile != null) {
            inherit (account) hashedPasswordFile;
          }
          // lib.optionalAttrs (account.passwordFile != null) {
            inherit (account) passwordFile;
          }
        )
      ) cfg.accounts;

      # RFC 2142 requires both to resolve; remote MTAs and DNSBLs check.
      aliases = {
        "postmaster@${cfg.domain}" = firstAccount;
        "abuse@${cfg.domain}" = firstAccount;
      };

      # ── Protocols ────────────────────────────────────────────────────────
      enableImapSsl = true; # 993, implicit TLS — what clients actually use
      enableImap = false; # 143/STARTTLS is deprecated (RFC 8314 §4.1)
      enableSubmissionSsl = true; # 465, implicit TLS submission
      enableManageSieve = true; # 4190, server-side filters from the webmail

      # ── TLS ──────────────────────────────────────────────────────────────
      # The cert is defined once below by nginx (`enableACME`); Postfix and
      # Dovecot read the same files out of /var/lib/acme.
      x509.useACMEHost = cfg.hostname;

      # ── Filtering ────────────────────────────────────────────────────────
      # Off on a 1 GB box: ClamAV's signature DB alone wants ~1 GB of RSS.
      # rspamd, included above, does the spam scoring.
      virusScanning = false;

      # rspamd queries DNSBLs constantly; a local resolver keeps the journal
      # readable instead of filling it with timeouts.
      localDnsResolver = true;

      dkim = {
        enable = true;
        keyDirectory = dkimDir;

        # The keypair is generated once, outside the repo, and the private half
        # lives in sops: its public half is a DNS record the zone declares, so
        # generating it on the host would leave the record unsettable until
        # after first boot. keyFile excludes keyType/keyLength by assertion.
        domains.${cfg.domain}.selectors.mail.keyFile = config.sops.secrets.dkim_mail_private_key.path;
      };

      # Dovecot's full-text index is the other RAM hog on this box.
      fullTextSearch.enable = false;
    };

    # ── TLS: one cert for mail.<domain>, shared ────────────────────────────
    security.acme = {
      acceptTerms = true;
      defaults.email = cfg.acmeEmail;
    };

    # No explicit `security.acme.certs."${cfg.hostname}"` here: the nginx vhost
    # below with `enableACME` creates it with the right group and webroot, and
    # nixos-mailserver appends its own reloadServices (postfix, dovecot) to the
    # same cert. A hand-written cert block would only duplicate both — and a
    # reloadServices entry naming a unit that does not exist (`dovecot2.service`;
    # the unit is `dovecot.service`) would warn on every renewal.

    # ── nginx: ACME webroot + Roundcube ────────────────────────────────────
    services.nginx = {
      enable = true;
      recommendedOptimisation = true;
      recommendedTlsSettings = true;
      serverTokens = false;
      # Uploads are bounded by Postfix's message_size_limit instead.
      clientMaxBodySize = "0";

      virtualHosts = {
        # :80 for the mail name — exists only to answer HTTP-01. Everything
        # else is redirected, so the vhost is a challenge endpoint, not a site.
        "${cfg.hostname}" = {
          enableACME = true;
          forceSSL = true;
          locations."/".return = "301 https://${cfg.webmailHostname}$request_uri";
        };

        # The webmail UI itself, on its own name and its own cert.
        "${cfg.webmailHostname}" = {
          enableACME = true;
          forceSSL = true;
          # Roundcube's module owns the php-fpm pool and the webroot; the vhost
          # is left to it (see services.roundcube below).
        };
      };
    };

    # ── Roundcube ──────────────────────────────────────────────────────────
    services.roundcube = {
      enable = true;
      hostName = cfg.webmailHostname;
      # The module then writes the vhost itself, with enableACME + forceSSL.
      configureNginx = true;
      maxAttachmentSize = config.mailserver.messageSizeLimit / 1024 / 1024;
      dicts = with pkgs.aspellDicts; [
        en
        de
      ];
      extraConfig = ''
        $config['imap_host'] = 'ssl://${cfg.hostname}:993';
        $config['smtp_host'] = 'ssl://${cfg.hostname}:465';
        $config['smtp_user'] = '%u';
        $config['smtp_pass'] = '%p';
        // The UI is served from webmail.<domain> but logs in against mail.<domain>.
        $config['username_domain'] = '${cfg.domain}';
        $config['mail_domain'] = '${cfg.domain}';
        // ManageSieve: lets the webmail edit server-side filters.
        $config['managesieve_host'] = 'tls://${cfg.hostname}:4190';
        $config['managesieve_usetls'] = true;
      '';
    };

    # ── Firewall ───────────────────────────────────────────────────────────
    # mailserver.openFirewall (default true) opens 25/465/993/4190. No 143 or
    # 587: those are the STARTTLS variants of protocols enabled below in their
    # implicit-TLS form, so they are never opened.
    networking.firewall.allowedTCPPorts = [
      80
      443
    ];

    # ── DKIM key ───────────────────────────────────────────────────────────
    # rspamd reads this directly (the path is what mailserver.dkim...keyFile
    # above points at), so the file must belong to rspamd, not root: sops-nix
    # defaults to 0400 root:root and the signer would get EACCES on every send.
    sops.secrets.dkim_mail_private_key = {
      owner = config.services.rspamd.user;
      group = config.services.rspamd.group;
      mode = "0400";
    };

    # Dovecot's userdb is generated by its ExecStartPre, which runs as root and is
    # what reads this file, so default root ownership is correct here.
    sops.secrets.leon_password_hash = { };

    # ── Disk ───────────────────────────────────────────────────────────────
    # Nothing to declare: nixos-mailserver creates dkim.keyDirectory (as a
    # tmpfiles rule owned by the rspamd user, which is what actually signs) and
    # StorageDirectory for /var/vmail. An extra rule naming an `opendkim` user
    # would fail at boot — there is no such user, DKIM here is rspamd's.
  };
}
