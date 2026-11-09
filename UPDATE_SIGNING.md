# Signing update releases

The updater in builds containing this change requires an Ed25519 signature in addition to the GitHub SHA-256 digest. It pins the public key in `Sources/Klik/UpdateSignature.swift`; changing a release and its digest on GitHub is not sufficient to produce a valid signature.

The corresponding private key is stored as the `local.klik.update-signing` / `ed25519-v1` item in the release owner's login Keychain. It is device-only and cannot be recovered from the public key. Losing it means existing installations cannot automatically trust releases signed by a different key. Do not commit or publish it. Plan a secure recovery and key rotation process before depending on it for long-term distribution.

For a release such as `v0.1.19`:

1. Build `Klik-0.1.19-arm64.dmg` and its `.sha256` file.
2. On the Mac with the signing key, run:

   ```sh
   swift Scripts/update-signing.swift sign v0.1.19 \
     Klik-0.1.19-arm64.dmg Klik-0.1.19-arm64.dmg.sig
   ```

3. Upload the DMG, checksum and `.sig` as assets of the same release. Do not rename them. The signing script refuses keys that differ from the pinned public key.

`swift Scripts/update-signing.swift public` shows only the public key. `generate` creates a key only if none exists; it never replaces one. A newly generated key on another machine will not match the pinned key until the app is deliberately updated to trust it.

Existing released versions, including 0.1.18, do not enforce this independent signature. Installing a version containing this change establishes the pinned public key for subsequent updates; the original installation and older updaters cannot acquire this protection retroactively.
