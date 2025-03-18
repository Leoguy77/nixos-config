{
  pkgs,
  ...
}: {
  imports = [
    ./global
    
  ];
  wallpaper = pkgs.inputs.themes.wallpapers.aenami-dawn;

  #  ------   -----   ------
  # | DP-3 | | DP-1| | DP-2 |
  #  ------   -----   ------
  monitors = [
    {
      name = "DP-1";
      width = 1920;
      height = 1280;
      workspace = "1";
      primary = true;
    }
  ];
}
