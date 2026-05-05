#!/usr/bin/env bash
set -e

echo "🔧 NixOS Configuration Installer"
echo "================================="
echo ""

# Check if running as root
if [ "$EUID" -eq 0 ]; then
  echo "❌ Don't run this script as root. It will use sudo when needed."
  exit 1
fi

# Step 1: Copy hardware configuration
echo "📋 Copying hardware configuration..."
sudo cp /etc/nixos/hardware-configuration.nix ~/dotfiles/nixos-config/
echo "✅ Hardware config copied"
echo ""

# Step 2: Commit hardware config
echo "💾 Committing hardware configuration..."
cd ~/dotfiles
git add nixos-config/hardware-configuration.nix
git commit -m "Add hardware configuration" || echo "No changes to commit"
echo ""

# Step 3: Create symlink
echo "🔗 Creating symlink /etc/nixos -> ~/dotfiles/nixos-config..."
sudo mv /etc/nixos /etc/nixos.backup.$(date +%Y%m%d_%H%M%S) 2>/dev/null || true
sudo ln -sfn ~/dotfiles/nixos-config /etc/nixos
echo "✅ Symlink created"
echo ""

# Step 4: Test build
echo "🔨 Testing configuration build..."
echo "   This may take a while on first run..."
nixos-rebuild build --flake ~/dotfiles/nixos-config#surface
echo "✅ Build successful!"
echo ""

# Step 5: Apply configuration
echo "🚀 Applying configuration..."
read -p "Ready to switch to new configuration? (y/n): " confirm
if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
  sudo nixos-rebuild switch --flake ~/dotfiles/nixos-config#surface
  echo "✅ Configuration applied!"
else
  echo "⏭️  Skipped applying configuration. Run manually later:"
  echo "   sudo nixos-rebuild switch --flake ~/dotfiles/nixos-config#surface"
fi
echo ""

# Step 6: Update flake lock
echo "📝 Updating flake.lock..."
git add nixos-config/flake.lock
git commit -m "Update flake.lock after build" || echo "No changes to commit"
echo ""

echo "🎉 Setup complete!"
echo ""
echo "Next steps:"
echo "  1. Add GitHub remote: git remote add origin git@github.com:leoguy77/dotfiles.git"
echo "  2. Push: git push -u origin main"
echo "  3. Reboot to verify everything works"
