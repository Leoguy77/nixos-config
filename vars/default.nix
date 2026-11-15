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
      surface = {
        ipv4 = "192.168.3.100"; # Update with actual IP
        ipv6 = ""; # Update with actual IPv6
        iface = "wlan0"; # Update with actual interface
      };

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

  # SSH public keys — one ed25519-sk (FIDO2) credential per Token2 key, so
  # each is independently revocable. Key A = serial 57059485 (one dot),
  # Key B = serial 99577136 (two dots). Resident + verify-required:
  # usable only with the token present, PIN known, and touch given.
  ssh = {
    keyA = "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAILcvZH+C4G29qVEP34shM+QPg8SOxoP58GJ7M76PFiTIAAAAC3NzaDpsc2luZnJh leoguy77@kirito tokenA";
    keyB = "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIFjju7Rsiq+BMPBYktR5tollrhj2dAW0r+2RP+ZO1oMPAAAAC3NzaDpsc2luZnJh leoguy77@kirito tokenB";
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
