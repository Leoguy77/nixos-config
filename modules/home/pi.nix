# Pi agent configuration
{ config, pkgs, lib, ... }:

let
  # ── Pi packages ───────────────────────────────────────────────────────────
  # Add any "npm:package-name" string here to have it declaratively installed
  # into pi's npm store (~/.pi/agent/npm/node_modules/) and registered in
  # settings.json. Pi will auto-discover and load it on next start.
  piPackages = [
    "npm:pi-mcp-adapter"
    "npm:pi-web-access"
  ];

  # ── Pi extensions ─────────────────────────────────────────────────────────
  # Extensions that need special handling (copied into ~/.pi/agent/extensions/
  # rather than going through pi's package manager). Each entry is an attrset:
  #   { npmName, globalInstallCheck }
  # where globalInstallCheck is the file to test for before skipping reinstall.
  piExtensions = [
    {
      npmName = "context-mode";
      globalInstallCheck = ".npm-global/lib/node_modules/context-mode/build/adapters/pi/extension.js";
    }
  ];

  # Extract just the npm package name from "npm:foo" → "foo"
  piPackageNames = map (p: lib.removePrefix "npm:" p) piPackages;

  # Shell snippet: install all piPackages into ~/.pi/agent/npm if missing
  installPiPackagesScript = lib.concatMapStrings (pkg: ''
    if ! [ -d ~/.pi/agent/npm/node_modules/${pkg} ]; then
      echo "Installing pi package: ${pkg}..."
      npm install --prefix ~/.pi/agent/npm ${pkg} 2>&1 || echo "Warning: Failed to install ${pkg}"
    fi
  '') piPackageNames;

  # Shell snippet: install + wire up all piExtensions
  installPiExtensionsScript = lib.concatMapStrings (ext: ''
    if ! [ -f ~/${ext.globalInstallCheck} ]; then
      echo "Installing pi extension: ${ext.npmName}..."
      npm install -g ${ext.npmName} 2>&1 || echo "Warning: Failed to install ${ext.npmName}"
    fi
    rm -rf ~/.pi/agent/extensions/${ext.npmName}
    mkdir -p ~/.pi/agent/extensions/${ext.npmName}
    if [ -d ~/.npm-global/lib/node_modules/${ext.npmName} ]; then
      cp -r ~/.npm-global/lib/node_modules/${ext.npmName}/. \
          ~/.pi/agent/extensions/${ext.npmName}/
      # Wrapper file so pi shows "context-mode" not the resolved "extension.js"
      if [ -f ~/.pi/agent/extensions/${ext.npmName}/build/adapters/pi/extension.js ]; then
        printf 'export { default } from "./${ext.npmName}/build/adapters/pi/extension.js";\n' \
          > ~/.pi/agent/extensions/${ext.npmName}.js
      fi
      echo "Wired extension: ${ext.npmName}"
    fi
  '') piExtensions;

in
{
  # Pi settings
  home.file.".pi/agent/settings.json".text = builtins.toJSON {
    lastChangelogVersion = "0.75.3";
    defaultProvider = "kisski";
    defaultModel = "qwen3.5-397b-a17b";
    packages = piPackages;
  };
  home.file.".pi/agent/settings.json".force = true;

  # Activation: install all declared pi packages + extensions
  home.activation.installPiPackages = config.lib.dag.entryAfter ["writeBoundary"] ''
    echo "Setting up pi packages and extensions..."

    # Ensure npm global directory exists
    mkdir -p ~/.npm-global
    echo "prefix=~/.npm-global" > ~/.npmrc

    # ── Pi packages (loaded via pi's package manager) ──────────────────────
    ${installPiPackagesScript}

    # ── Pi extensions (copied into ~/.pi/agent/extensions/) ────────────────
    ${installPiExtensionsScript}

    echo "Done."
  '';
}
