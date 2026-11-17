#!/usr/bin/env bash
#
# Set the login password hash for a user, in sops. Idempotent: re-running with
# the same secret name overwrites it, which is exactly how you rotate it.
#
#   scripts/set-login-password.sh                    # leoguy77_password_hash
#   scripts/set-login-password.sh --verify            # check the stored hash
#   scripts/set-login-password.sh --user alice        # alice_password_hash
#   scripts/set-login-password.sh --dry-run           # hash locally, write nothing
#
# The secret name must match modules/nixos/login.nix's `passwordSecret` default
# ("<user>_password_hash"), otherwise the module reads a secret that is not there
# and activation fails on first boot.
#
# --dry-run exists because every `sops` invocation needs a Token2 touch: you can
# prove mkpasswd and the hash roundtrip here without spending any.
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
secret_file="$repo/secrets/secrets.sops.yaml"
user="leoguy77"
mode="set"

while [[ $# -gt 0 ]]; do
	case "$1" in
	--user)
		user="$2"
		shift 2
		;;
	--verify)
		mode="verify"
		shift
		;;
	--dry-run)
		mode="dry-run"
		shift
		;;
	-h | --help)
		sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
		exit 0
		;;
	*)
		echo "unknown argument: $1" >&2
		exit 2
		;;
	esac
done

key="${user}_password_hash"

if [[ ! -f $secret_file ]]; then
	echo "missing $secret_file" >&2
	exit 1
fi

for cmd in mkpasswd sops python3; do
	# --dry-run touches neither sops nor python3, so it still works without them.
	[[ $cmd != mkpasswd && $mode == dry-run ]] && continue
	command -v "$cmd" >/dev/null || {
		echo "$cmd not found on PATH" >&2
		echo "run: nix shell nixpkgs#mkpasswd nixpkgs#sops nixpkgs#python3" >&2
		exit 2
	}
done

# Compare a password against a $6$ hash without leaking either on the command
# line, using the same tool that produced it: mkpasswd -S reuses the stored
# salt. (openssl passwd -6 did the same job but is not on this host's PATH, and
# a missing tool must not look like a wrong password.)
check() {
	local hash=$1 pass=$2 salt
	salt=$(printf '%s' "$hash" | sed -n 's/^\$6\$\([^$]*\)\$.*/\1/p')
	if [[ -z $salt ]]; then
		echo "not a sha-512 crypt hash (\$6\$...): ${hash:0:20}..." >&2
		return 1
	fi
	[[ $(printf '%s\n' "$pass" | mkpasswd -m sha-512 -S "$salt" -s | tr -d '\n') == "$hash" ]]
}

if [[ $mode == verify ]]; then
	hash=$(sops -d "$secret_file" | sed -n "s/^${key}: //p" | tr -d '"')
	if [[ -z $hash ]]; then
		echo "$key is not in $secret_file — run this script without --verify" >&2
		exit 1
	fi
	printf '%s: ' "password for $key"
	read -rs pass
	echo
	if check "$hash" "$pass"; then
		echo 'HASH OK'
	else
		echo 'MISMATCH' >&2
		exit 1
	fi
	exit 0
fi

read -rsp 'Password: ' p1
echo
read -rsp 'Again:    ' p2
echo
if [[ $p1 != "$p2" ]]; then
	echo 'mismatch' >&2
	unset p1 p2
	exit 1
fi

# -s reads the password from stdin, so it never appears in argv.
hash=$(printf '%s\n' "$p1" | mkpasswd -m sha-512 -s | tr -d '\n')
unset p1 p2

if [[ $mode == dry-run ]]; then
	echo "would set $key in $secret_file (no sops call, no token touch)"
	echo "hash: ${hash:0:20}…  (${#hash} chars)"
	exit 0
fi

printf '%s' "$hash" | python3 -c 'import json,sys; sys.stdout.write(json.dumps(sys.stdin.read()))' |
	sops set --value-stdin "$secret_file" "[\"$key\"]"

echo "wrote $key to $secret_file"
echo "rotating? re-run the pipeline and 'nixos-rebuild switch' on each host."
