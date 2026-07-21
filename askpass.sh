#!/usr/bin/env bash
# GUI askpass helper for KDE Plasma — pops up a password dialog
# Used by SUDO_ASKPASS for non-terminal sudo (e.g. pi agent)
exec kdialog --title "sudo" --password "Password for sudo:"
