# Printing (CUPS) + print-to-file.
{
  config,
  lib,
  ...
}:

{
  options.modules.printing = {
    enable = lib.mkEnableOption "printing (CUPS)";
  };

  config = lib.mkIf config.modules.printing.enable {
    services.printing.enable = true;
  };
}
