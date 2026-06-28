# Shared variables for all configurations
# Import this in modules via specialArgs as `myvars`
{ lib, ... }:

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
        ipv4 = "192.168.3.100";  # Update with actual IP
        ipv6 = "";  # Update with actual IPv6
        iface = "wlan0";  # Update with actual interface
      };
    };
    
    # Smart home configuration
    smartHome = {
      mqttBroker = "mqtt.fd";
      zigbeeController = "192.168.3.145";
    };
  };
  
  # Git configuration
  git = {
    userName = "Leon";
    userEmail = "leonschneider29@googlemail.com";
    signingKey = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDAj4xwu7D5e0hN7+Tr46JZhvPGc/EehC7R22xAaHiypvU/620JZSakZID5+D6oIrG0z+my3BoweV+O3DpBoPvN9OOBlP05HsDf9AUY99io5wfWKkAKUZnXTHVoORwA/xp5DMHuPTS8cLKmqwBtAcEhL9+q4lVjDjZhagR69J7DycAC678YBZrH3g0yuciJBAaTIvZPDvlTeZHc3piKrlYRdjhFq6PJ8K7fi/RhtMOLDCFHV8kv71uV7+rD+isyPYhj3OAR2tyQxoBhxdqIQM7w+rPgm5km7rh58ErlWXC0ZsllPbLz/LVsoNPSq2GqnGGILb7vZE3ytD4lqEO1fhv4nXN7OlZPLO73Ti4b/RetqsmA0y6Yf58yLU+aTGTlZ6ytKd2gJx5/ne0jgoCV9fFaVnpxD0TBw0ME5jyABby9OlzpUm4Pheu/b3SSeH2/vYBLr/dAPLAd7ARz9ZP1BGm5BHjwWtsTrzsr3aRR+00o2VFLQcrwJyqGTwWzNvA0THfe5HS/+EZg142XgyI+nhm9vYI6rIXfnISYi4p+3TF0aUzAlWRy0LH/4UMCjQiCCEvBz9azPWecehUxCCfMAkIZQtc5MVcwz5kuNlgWYBBKF7aDCUHEG7GEG6Lm0U6eHfqkI48ajCCwvsMZmERuKtLr8vl9FbjucoGcp8Bp1XqXuw==";
  };
  
  # Theme preferences
  theme = {
    name = "catppuccin";
    flavor = "mocha";
    accent = "mauve";
    darkMode = true;
  };
}
