# Stalwart mail server + Bulwark webmail, and the TLS front for both.
#
# Why containers: nixpkgs only ships `stalwart-mail` 0.15.x, and Bulwark needs
# Stalwart >= 0.16.6 (1.0 needs Bulwark >= 1.18). Pinning the upstream images on
# a release line keeps server and webmail compatible.
#
# TLS layout (single public IPv4, two names):
#
#   :443 ──> nginx _stream_, SNI passthrough
#              webmail.<domain> ──> 127.0.0.1:8445  (nginx http, LE cert)
#              *                ──> 127.0.0.1:8443  (Stalwart's own TLS)
#   :80  ──> nginx http: ACME (webmail) + redirect
#   :25 :465 :587 :143 :993 :4190 ──> Stalwart directly
#
# Stalwart keeps a single hostname (mail.<domain>) and gets its own certificate
# with ACME/TLS-ALPN-01. The validation connects to port 443, the stream proxy
# passes the handshake through untouched, so mail.<domain> keeps one cert that
# Stalwart also uses for SMTP/IMAP. nginx never terminates TLS for that name,
# which is what keeps the two ACME clients from fighting over HTTP-01.
{ config, pkgs, lib, ... }:

let
  cfg = config.modules.mail;

  stalwartDataDir = "${cfg.stateDir}/stalwart";
  bulwarkDataDir = "${cfg.stateDir}/bulwark";

  # Ports Stalwart serves on the host. Loopback-only ports are the ones nginx
  # fronts; the rest are published directly so provider-side rDNS and client
  # autoconfiguration work without extra hops.
  stalwartPorts = [
    "25:25" # SMTP
    "465:465" # SMTPS (implicit TLS)
    "587:587" # submission (STARTTLS)
    "143:143" # IMAP (STARTTLS)
    "993:993" # IMAPS
    "4190:4190" # ManageSieve
    "127.0.0.1:8443:443" # HTTPS: JMAP, web admin, ACME TLS-ALPN-01
    "127.0.0.1:8081:8080" # plain HTTP: setup wizard (only while unconfigured)
  ];
in

{
  options.modules.mail = {
    enable = lib.mkEnableOption "Stalwart mail server and Bulwark webmail";

    hostname = lib.mkOption {
      type = lib.types.str;
      description = "Mail hostname (MX, JMAP, web admin, TLS certificate).";
      example = "mail.example.com";
    };

    webmailHostname = lib.mkOption {
      type = lib.types.str;
      description = ''
        Hostname for the Bulwark webmail UI. Must differ from {option}`hostname`
        so that only one ACME client is responsible for each name.
      '';
      example = "webmail.example.com";
    };

    acmeEmail = lib.mkOption {
      type = lib.types.str;
      description = "Contact address for Let's Encrypt.";
    };

    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib";
      description = "Parent directory for the container data.";
    };

    stalwartImage = lib.mkOption {
      type = lib.types.str;
      # Never `latest`: Stalwart 1.0 cannot open a 0.16 data store.
      default = "docker.io/stalwartlabs/stalwart:v1.0";
      description = "Stalwart container image (pin the release line).";
    };

    bulwarkImage = lib.mkOption {
      type = lib.types.str;
      default = "ghcr.io/bulwarkmail/webmail:1";
      description = "Bulwark container image (pin the release line).";
    };

    stalwartMemoryLimit = lib.mkOption {
      type = lib.types.str;
      default = "640m";
      description = "Memory limit for the Stalwart container.";
    };

    bulwarkMemoryLimit = lib.mkOption {
      type = lib.types.str;
      default = "256m";
      description = "Memory limit for the Bulwark container.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.hostname != cfg.webmailHostname;
        message = "modules.mail.hostname and modules.mail.webmailHostname must differ.";
      }
    ];

    # ── Containers ─────────────────────────────────────────────────────────
    virtualisation.oci-containers.backend = "podman";
    virtualisation.podman = {
      enable = true;
      dockerCompat = false;
    };

    virtualisation.oci-containers.containers.stalwart = {
      image = cfg.stalwartImage;
      ports = stalwartPorts;
      volumes = [
        "${stalwartDataDir}/etc:/etc/stalwart"
        "${stalwartDataDir}/data:/var/lib/stalwart"
      ];
      environment = {
        STALWART_HOSTNAME = cfg.hostname;
        # JMAP URLs published to clients live behind the stream proxy.
        STALWART_PUBLIC_URL = "https://${cfg.hostname}";
      };
      extraOptions = [
        "--memory=${cfg.stalwartMemoryLimit}"
        "--memory-swap=${cfg.stalwartMemoryLimit}"
      ];
    };

    virtualisation.oci-containers.containers.bulwark = {
      image = cfg.bulwarkImage;
      ports = [ "127.0.0.1:3000:3000" ];
      volumes = [ "${bulwarkDataDir}:/app/data" ];
      environment = {
        HOSTNAME = "0.0.0.0";
        PORT = "3000";
        # The browser talks JMAP to Stalwart directly, not through Bulwark.
        JMAP_SERVER_URL = "https://${cfg.hostname}";
      };
      extraOptions = [
        "--memory=${cfg.bulwarkMemoryLimit}"
        "--memory-swap=${cfg.bulwarkMemoryLimit}"
      ];
    };

    systemd.tmpfiles.rules = [
      "d ${stalwartDataDir} 0700 root root -"
      "d ${stalwartDataDir}/etc 0700 root root -"
      "d ${stalwartDataDir}/data 0700 root root -"
      # Bulwark's image runs as an unprivileged node user; it needs to write
      # the admin config and sessions here.
      "d ${bulwarkDataDir} 0750 1000 1000 -"
    ];

    # ── Firewall ───────────────────────────────────────────────────────────
    networking.firewall.allowedTCPPorts = [
      25
      465
      587
      143
      993
      4190
    ];

    # ── ACME for the webmail hostname ──────────────────────────────────────
    #
    # webroot (HTTP-01 through nginx on :80) keeps port 443 free for the SNI
    # passthrough, and leaves Stalwart's own ACME client alone.
    security.acme = {
      acceptTerms = true;
      defaults.email = cfg.acmeEmail;
      certs."${cfg.webmailHostname}" = {
        domain = cfg.webmailHostname;
        group = "nginx";
        webroot = "/var/lib/acme/acme-challenge";
        reloadServices = [ "nginx" ];
      };
    };

    # ── nginx: SNI passthrough + webmail vhost ─────────────────────────────
    services.nginx = {
      enable = true;
      recommendedOptimisation = true;
      recommendedTlsSettings = true;
      recommendedProxySettings = true;
      serverTokens = false;
      # Webmail uploads are bounded by Stalwart's own message size limit.
      clientMaxBodySize = "0";

      streamConfig = ''
        map $ssl_preread_server_name $mail_tls_backend {
          ${cfg.webmailHostname}  127.0.0.1:8445;
          default                 127.0.0.1:8443;
        }

        server {
          listen      443;
          listen      [::]:443;
          ssl_preread on;
          proxy_pass  $mail_tls_backend;
          # IMAP/JMAP sessions are long lived; a client must not be cut off
          # mid-session by the proxy.
          proxy_timeout 1h;
          proxy_connect_timeout 10s;
        }
      '';

      virtualHosts = {
        # Plain HTTP: ACME challenge for the webmail name, everything else is
        # redirected to the mail host.
        "${cfg.webmailHostname}" = {
          listen = [
            {
              addr = "0.0.0.0";
              port = 80;
            }
            {
              addr = "[::]";
              port = 80;
            }
          ];
          locations."/.well-known/acme-challenge/".root = "/var/lib/acme/acme-challenge";
          locations."/".return = "301 https://${cfg.hostname}$request_uri";
        };

        # HTTPS for the webmail name, reached through the SNI map above.
        "${cfg.webmailHostname}-tls" = {
          serverName = cfg.webmailHostname;
          listen = [
            {
              addr = "127.0.0.1";
              port = 8445;
              ssl = true;
            }
          ];
          # `listen` is set explicitly below, so the module needs to be told
          # that this vhost terminates TLS (it otherwise emits no ssl_* lines).
          addSSL = true;
          # Ordering against acme-<name>.service so nginx never starts
          # without the certificate it is about to load.
          useACMEHost = cfg.webmailHostname;
          locations."/" = {
            proxyPass = "http://127.0.0.1:3000";
            proxyWebsockets = true;
            extraConfig = ''
              add_header Strict-Transport-Security "max-age=31536000" always;
              add_header X-Content-Type-Options "nosniff" always;
              add_header Referrer-Policy "strict-origin-when-cross-origin" always;
              add_header X-Frame-Options "SAMEORIGIN" always;
            '';
          };
        };
      };
    };
  };
}
