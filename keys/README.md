# keys/

Public keys that are committed on purpose.

```
leon.asc    # Leon's OpenPGP public key — master 23CDB62B8549A1537F83F13A99CD2D0BD7504252
```

Nothing secret belongs here. A public key is the one kind of key that is safe in
a public repository, and this one has to be here: a machine with a fresh keyring
cannot derive it from the Token2. The card carries only the three **subkey**
fingerprints — `720BFD2F…` (sign), `37DCCB6F…` (encrypt, `6B4B5DC74EFF8D1C`),
`04457094…` (auth) — and never the master `23CDB62B…` that `.sops.yaml` names.
Without the public key gpg cannot build the key hierarchy and fails with
`public key decryption failed: No secret key`, which reads like a wrong token
but is a missing parent key. `secrets/README.md` has the long version.

Two things read this directory:

- **`scripts/enroll-host-key.sh`** imports the `.asc` when the `.sops.yaml` PGP
  recipient is not in the keyring, so enrolling a new host from a bare ISO works
  without a manual `gpg --import`.
- **`modules/nixos/mail.nix`** publishes every `*.asc` here over WKD at
  `openpgpkey.lsinfra.de`. So anything added to this directory reaches the
  public web — the builder only emits the addresses at that domain, but the key
  itself is world-readable either way.

The committed copy is 2277 bytes and is the same key that signs commits. The
master is certify-only and stays on offline media; the subkeys live on the
Token2 cards, so both cards work from this one file. No expiry on any of them.

## Regenerating

```bash
gpg --export --armor 23CDB62B8549A1537F83F13A99CD2D0BD7504252 > keys/leon.asc
```

Then check the WKD site still builds and the enroll script still imports it —
a truncated or stale export fails both silently otherwise:

```bash
nix build .#nixosConfigurations.mail.config.services.nginx.virtualHosts.\"openpgpkey.lsinfra.de\".root
GNUPGHOME=$(mktemp -d) && gpg --import keys/leon.asc && gpg --list-keys 23CDB62B8549A1537F83F13A99CD2D0BD7504252
```

Use the full fingerprint there. gpg key IDs are the **last** 16 hex characters
of a fingerprint, not the first eight, so the familiar `gpg --list-keys 23CDB62B`
fails with `No public key` even though the key is present — `99CD2D0BD7504252`
is the short form of this one.
