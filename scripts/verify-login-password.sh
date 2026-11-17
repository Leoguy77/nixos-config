#!/usr/bin/env bash
#
# Verify a login password against the hash stored in sops.
#
#   scripts/verify-login-password.sh              # prompts once
#   scripts/verify-login-password.sh --user alice # alice_password_hash
#
# Exits 0 on HASH OK, 1 on MISMATCH, 2 on a setup problem (missing secret, or a
# required tool not on PATH).
#
# Why this exists: a hash built from a mistyped password is indistinguishable
# from a locked account at the greeter — you find out at the login screen of a
# freshly wiped machine. This is the only cheap way to know before that.
#
# Needs one Token2 touch (sops has to decrypt) — unless you point it at this
# machine's own SSH host key instead, which is what sops-nix uses on the
# installed system and needs no token:
#
#   SOPS_AGE_SSH_PRIVATE_KEY_FILE=/path/to/hostkey scripts/verify-login-password.sh
#
# Run it right after scripts/set-login-password.sh, while the password is still
# in your head.
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
secret_file="$repo/secrets/secrets.sops.yaml"
user="leoguy77"

while [[ $# -gt 0 ]]; do
	case "$1" in
	--user)
		user="$2"
		shift 2
		;;
	-h | --help)
		sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
		exit 0
		;;
	*)
		echo "unknown argument: $1" >&2
		exit 2
		;;
	esac
done

key="${user}_password_hash"

# Checked before anything else, and exiting 2 rather than 1: a missing tool is
# not a wrong password. Getting this wrong once caused a scary MISMATCH on a
# perfectly good hash just because openssl was not installed — the failure mode
# has to distinguish "cannot check" from "check failed".
for cmd in mkpasswd sops; do
	command -v "$cmd" >/dev/null || {
		echo "$cmd not found on PATH" >&2
		echo "run: nix shell nixpkgs#mkpasswd nixpkgs#sops" >&2
		exit 2
	}
done

[[ -f $secret_file ]] || {
	echo "missing $secret_file" >&2
	exit 2
}

hash=$(sops -d "$secret_file" | sed -n "s/^${key}: //p" | tr -d '"')
if [[ -z $hash ]]; then
	echo "$key is not in $secret_file" >&2
	echo "create it with scripts/set-login-password.sh" >&2
	exit 2
fi

# The salt is the field between the second and third $: $6$<salt>$<hash>
salt=$(printf '%s' "$hash" | sed -n 's/^\$6\$\([^$]*\)\$.*/\1/p')
if [[ -z $salt ]]; then
	echo "$key is not a sha-512 crypt hash (\$6\$...)" >&2
	echo "first 20 chars: ${hash:0:20}" >&2
	exit 1
fi

printf 'password for %s: ' "$key"
read -rs typed
echo

# Recomputed with the same tool that built it, and the stored salt, so the only
# variable is the password. -s reads stdin, keeping it out of argv and `ps`.
if [[ $(printf '%s\n' "$typed" | mkpasswd -m sha-512 -S "$salt" -s | tr -d '\n') == "$hash" ]]; then
	unset typed
	echo 'HASH OK'
else
	unset typed
	echo 'MISMATCH' >&2
	echo "the stored hash was not built from that password — rerun" >&2
	echo "scripts/set-login-password.sh before installing" >&2
	exit 1
fi
