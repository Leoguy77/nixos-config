# Shared variables for all configurations
# Import this in modules via specialArgs as `myvars`
_:

{
  # User information
  username = "leoguy77";
  fullName = "Leon";
  email = "leonschneider29@googlemail.com";

  # System settings
  system = {
    stateVersion = "24.11";
    defaultLocale = "en_US.UTF-8";
    timeZone = "Europe/Berlin";
    keymap = "de";
  };

  # Networking configuration
  networking = {
    # Main gateway/router IP
    mainGateway = "192.168.3.1";
    mainGateway6 = "fe80::1";

    # DNS servers
    nameservers = [
      "1.1.1.1"
      "1.0.0.1"
      "8.8.8.8"
    ];

    # Host-specific addresses
    hostsAddr = {
      # netcup VPS (pico G11s) — public mail server
      mail = {
        ipv4 = "91.132.147.216"; # /22
        ipv4Gateway = "91.132.144.1";
        ipv6 = "2a03:4000:37:c32:6860:64ff:fe3b:ddb0"; # /64
        ipv6Gateway = "fe80::1";
        iface = "eth0"; # also enp0s3 / ens3
      };
    };

    # Smart home configuration
    smartHome = {
      mqttBroker = "mqtt.fd";
      zigbeeController = "192.168.3.145";
    };
  };

  # SSH public key — the OpenPGP auth subkey 11BE08BBC020EF46. Both Token2
  # cards carry the same subkey (the keygrip derives from the public key), so
  # ONE line covers either token and any replacement card — no per-host
  # re-enrolment when a token is lost. The key never leaves the card: gpg-agent
  # signs after a PIN + touch. The master key is certify-only and stays on the
  # offline USB sticks, so it cannot be used for SSH.
  ssh = {
    key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKfgUoHJ8xxWqcS3FPnf17UPD3FAQICJS0D9zS8Iy5Mj openpgp:0xC020EF46";
  };

  # Git configuration
  git = {
    userName = "Leon";
    userEmail = "leonschneider29@googlemail.com";
    # OpenPGP master fingerprint — gpg picks the S subkey (14788494FDC10D36)
    # from the Token2 cards to sign. Old ssh-ed25519 key retired.
    signingKey = "23CDB62B8549A1537F83F13A99CD2D0BD7504252";
  };

  # Theme preferences
  theme = {
    name = "catppuccin";
    flavor = "mocha";
    accent = "mauve";
    darkMode = true;
  };
}
