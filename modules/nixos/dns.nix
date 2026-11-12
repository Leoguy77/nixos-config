# Declarative DNS for Cloudflare zones, applied by `nixos-rebuild switch`.
#
# Two separate concerns, deliberately not merged:
#
#   modules.dns.records  — a REGISTRY. Any module anywhere may append a record,
#                          regardless of which host publishes it. Costs nothing.
#   modules.dns.push     — the PUBLISHER. Exactly one host per zone renders the
#                          registry for its zone and pushes it to Cloudflare.
#
#   (mylib.publishDns { zone = "lsinfra.de"; text = ''A("foo", "192.0.2.1")''; })
#
# PURGE is on: the record list IS the zone. A record missing from it is deleted
# from Cloudflare on the next rebuild. That is the point — the config is the
# source of truth, not a diff to some unmanaged state. The guard rails are
# build-time validation (dnscontrol `check`, including duplicate detection) and
# `IGNORE_NAME` for the records an external process must own.
#
# **This repository is public.** Any value that must not be published goes in
# `modules.dns.push.variables`, which is a sops secret passed to dnscontrol with
# `-v` at push time — the /nix/store copy of the zone file contains the variable
# name, never the value.
#
# Needs `cloudflare_dns_token` in secrets/secrets.sops.yaml, scoped to
# Zone.DNS:Edit on the zone(s) this host pushes.
{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.modules.dns.push;
  registry = config.modules.dns;

  ownRecords = map (e: e.text) (builtins.filter (e: e.zone == cfg.zone) registry.records);

  varNames = builtins.attrNames cfg.variables;

  # Placeholder per variable for the build-time check. Real values never reach
  # the store, so `check` cannot see them; this only has to parse as the right
  # kind of value, which is why it is configurable (an AAAA needs a v6 literal).
  placeholderArgs = lib.concatMapStringsSep " " (
    n: "-v ${n}=${cfg.variables.${n}.placeholder}"
  ) varNames;

  # The DSL is dnscontrol's, so a record is a line of JS. Validated at build
  # time below — a typo fails the rebuild, not the activation.
  #
  # Records namespaced to another zone are dropped here; the host that owns that
  # zone renders its own file from the same registry.
  zoneFile = pkgs.writeText "dnsconfig.js" ''
    var REG_NONE = NewRegistrar("none");
    var CF = NewDnsProvider("cloudflare", "CLOUDFLAREAPI");

    D(
      "${cfg.zone}",
      REG_NONE,
      DnsProvider(CF),
    ${lib.concatMapStringsSep "\n" (r: "  ${r},") cfg.ignore}
    ${lib.concatMapStringsSep "\n" (r: "  ${r},") ownRecords}
    );
  '';

  # dnscontrol expands `$VAR` refs inside creds.json from its own environment.
  # The bare `${VAR}` form silently sends an empty token, so keep the dollars.
  credsFile = pkgs.writeText "creds.json" ''
    {"cloudflare":{"TYPE":"CLOUDFLAREAPI","apitoken":"$CF_TOKEN"}}
  '';

  # Syntax check with no provider access and no credentials. Runs as part of
  # `nix flake check` and whenever the record list changes.
  validated = pkgs.runCommand "dnsconfig-check" { } ''
    export HOME=$(mktemp -d)
    ${lib.getExe pkgs.dnscontrol} check --config ${zoneFile} ${placeholderArgs} >/dev/null
    touch $out
  '';
in

{
  options.modules.dns = {
    records = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            zone = lib.mkOption {
              type = lib.types.str;
              example = "lsinfra.de";
              description = "Fully qualified zone (no trailing dot).";
            };
            text = lib.mkOption {
              type = lib.types.str;
              example = ''A("mail", "203.0.113.9", CF_PROXY_OFF, TTL(300))'';
              description = ''
                A dnscontrol DSL expression. Anything its language can express
                works — `A`, `AAAA`, `MX`, `TXT`, `CAA`, `SRV`, `TLSA`,
                `CNAME`, and the `CF_PROXY_ON`/`CF_PROXY_OFF`/`TTL()` modifiers.
              '';
            };
          };
        }
      );
      default = [ ];
      description = ''
        Every record any module in the tree wants published, across all zones.
        This is a registry, not a claim: declaring here changes nothing until a
        host enables `modules.dns.push.enable` for that zone.

        Two records with the same name and type are a build error, not a silent
        overwrite — dnscontrol rejects duplicates.
      '';
    };

    push = {
      enable = lib.mkEnableOption "pushing one Cloudflare zone from this host";

      zone = lib.mkOption {
        type = lib.types.str;
        default = "lsinfra.de";
        description = ''
          The zone THIS host pushes. Records registered for other zones stay in
          the tree untouched — they belong to whichever host owns them.
        '';
      };

      # PURGE deletes anything not listed. These are the exceptions: names owned
      # by something other than this repo, which a push must not touch.
      ignore = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [ ''IGNORE_NAME("_acme-challenge.**")'' ];
        description = ''
          dnscontrol DSL expressions declaring names that survive a purge.
          Needed for anything written by an external process — Let's Encrypt
          challenge TXT records being the main case.
        '';
      };

      # Record values that must not enter this repository.
      variables = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            options = {
              secret = lib.mkOption {
                type = lib.types.str;
                description = ''
                  Key in secrets/secrets.sops.yaml. Exposed to the generated
                  dnsconfig.js as a bare JS identifier of the same name, so a
                  record can reference it as e.g. `host1_ipv4`.
                '';
              };
              placeholder = lib.mkOption {
                type = lib.types.str;
                default = "192.0.2.1";
                description = ''
                  Stand-in used by the build-time `dnscontrol check`. Must parse
                  as the same type as the real value (a v6 literal for an AAAA),
                  otherwise the check rejects the record.
                '';
              };
            };
          }
        );
        default = { };
        description = ''
          Secret-backed values available to `records` by name. Each becomes a
          `sops.secrets.<key>` and is passed to dnscontrol with `-v`, which
          keeps the plaintext out of the Nix store entirely.

          At build time the value is unknown, so `system.checks` validates the
          generated file with a placeholder. dnscontrol still catches malformed
          records then; the real value is only seen at push time.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = ownRecords != [ ];
        message = ''
          No records registered for zone ${cfg.zone}. Pushing an empty zone with
          PURGE on would delete every record in it.
        '';
      }
    ];

    sops.secrets = {
      cloudflare_dns_token = { };
      # One secret per declared variable; the key in secrets.sops.yaml is
      # `secret`, the JS identifier is the attrset key.
    }
    // lib.genAttrs (map (v: v.secret) (builtins.attrValues cfg.variables)) (_: { });

    systemd.services.dns-sync = {
      description = "Apply modules.dns.records for ${cfg.zone} to Cloudflare";
      wants = [ "network-online.target" ];
      after = [
        "network-online.target"
        "sops-install-secrets.service"
      ];
      wantedBy = [ "multi-user.target" ];

      # Re-run on every rebuild that changes the record list, not only on boot.
      restartTriggers = [ zoneFile ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        # The diff is printed either way; this keeps it in the journal.
        StandardOutput = "journal";
        StandardError = "journal";
      };

      script =
        let
          # `--variable name=value` per secret. Values are read from the
          # decrypted files at push time, so they appear in the process
          # environment only — never in the store, never in the journal.
          varArgs = lib.concatMapStringsSep " " (
            n: "--variable ${n}=\"$(cat ${config.sops.secrets.${cfg.variables.${n}.secret}.path})\""
          ) varNames;
        in
        ''
          set -eu
          CF_TOKEN="$(cat ${config.sops.secrets.cloudflare_dns_token.path})"
          export CF_TOKEN
          ${lib.getExe pkgs.dnscontrol} push \
            --config ${zoneFile} \
            --creds ${credsFile} \
            --no-colors \
            ${varArgs}
        '';
    };

    # Building the host now proves the DSL parses.
    system.checks = [ validated ];
  };
}
