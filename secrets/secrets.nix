# ──────────────────────────────────────────────────────────
#  secrets/secrets.nix — agenix recipients & configs
# ──────────────────────────────────────────────────────────
# Tiers (directory-based, determines who can decrypt):
#   global/   — all machines + user (e.g., shared API tokens)
#   machine/  — one host + user (e.g., WiFi per host)
#   user/     — only the user via home-manager (e.g., git key)
#   shared/   — user + one host (e.g., machine-local user creds)
#
# Security levels (age.secrets.<name>.{mode,owner}):
#   noaccess       = mode 0000, root
#   restricted     = mode 0500, root
#   user_readable  = mode 0500, <user>
#
# Recipients block is read by: agenix -e (edit time)
# NixOS module reads: configs to build age.secrets
# Deploy script edits: AUTO-HOSTS section
# ──────────────────────────────────────────────────────────
{ myvars, ... }:

let
  # ── User keys ──
  leon = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDAj4xwu7D5e0hN7+Tr46JZhvPGc/EehC7R22xAaHiypvU/620JZSakZID5+D6oIrG0z+my3BoweV+O3DpBoPvN9OOBlP05HsDf9AUY99io5wfWKkAKUZnXTHVoORwA/xp5DMHuPTS8cLKmqwBtAcEhL9+q4lVjDjZhagR69J7DycAC678YBZrH3g0yuciJBAaTIvZPDvlTeZHc3piKrlYRdjhFq6PJ8K7fi/RhtMOLDCFHV8kv71uV7+rD+isyPYhj3OAR2tyQxoBhxdqIQM7w+rPgm5km7rh58ErlWXC0ZsllPbLz/LVsoNPSq2GqnGGILb7vZE3ytD4lqEO1fhv4nXN7OlZPLO73Ti4b/RetqsmA0y6Yf58yLU+aTGTlZ6ytKd2gJx5/ne0jgoCV9fFaVnpxD0TBw0ME5jyABby9OlzpUm4Pheu/b3SSeH2/vYBLr/dAPLAd7ARz9ZP1BGm5BHjwWtsTrzsr3aRR+00o2VFLQcrwJyqGTwWzNvA0THfe5HS/+EZg142XgyI+nhm9vYI6rIXfnISYi4p+3TF0aUzAlWRy0LH/4UMCjQiCCEvBz9azPWecehUxCCfMAkIZQtc5MVcwz5kuNlgWYBBKF7aDCUHEG7GEG6Lm0U6eHfqkI48ajCCwvsMZmERuKtLr8vl9FbjucoGcp8Bp1XqXuw==";

  # ── Host keys (deploy.sh adds between the markers) ──
  # AUTO-HOSTS-START
  surface = "age1surfaceplaceholder";
  # AUTO-HOSTS-END

  allMachines = [
    surface
  # AUTO-HOST-LIST
  ];

  # Security level presets
  levels = {
    noaccess = { mode = "0000"; owner = "root"; };
    restricted = { mode = "0500"; owner = "root"; };
    user_readable = { mode = "0500"; owner = myvars.username; };
  };

in {
  inherit leon surface allMachines levels;

  # Per-file recipients (for `agenix -e`)
  recipients = {
    # ── global/ — all machines decrypt ──
    # "global/cloudflared-token.age".publicKeys = [ leon ] ++ allMachines;

    # ── machine/ — one host + user ──
    # "machine/surface/wifi.age".publicKeys = [ leon surface ];

    # ── user/ — only user (home-manager agenix) ──
    # "user/github-token.age".publicKeys = [ leon ];

    # ── shared/ — user + one host ──
    # "shared/surface/docker-config.age".publicKeys = [ leon surface ];
  };

  # Per-file security config (for NixOS/home-manager modules)
  configs = {
    # "global/cloudflared-token.age" = levels.restricted;
    # "machine/surface/wifi.age" = levels.noaccess;
    # "user/github-token.age" = levels.user_readable;
    # "shared/surface/docker-config.age" = levels.restricted;
  };
}
