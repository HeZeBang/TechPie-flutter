# Watch companion builds

On a clean checkout, `build.ps1` creates an unsigned local `build-profile.json5`
from `build-profile.template.json5`. It never overwrites an existing profile.
The generated profile is ignored by Git. Configure device installation signing
locally in DevEco Studio; signing material and passwords must stay local.

The committed phone identity matches the signed Android release certificate.
Both `build.ps1` and the Lite packaging hook validate it against
`.github/workflows/android-release.yml` before packaging and signing.

For a local Android debug APK, explicitly supply its public certificate SHA256:

```powershell
$env:HUAWEI_PHONE_FINGERPRINT = '<64 hexadecimal characters from your debug certificate>'
./build.ps1
Remove-Item Env:HUAWEI_PHONE_FINGERPRINT
```

The override changes generated watch JavaScript only. Never commit a debug
certificate into `wear-config.js`, and leave this environment variable unset
when packaging the companion for Android release users. The build mode named
`debug` is the SDK's Lite BIN packaging path; it does not select the phone's
certificate. A fresh compilation is required when changing the override.

Run the portable checks without the Huawei SDK:

```sh
node --test harmonyos_watch/scripts/*.test.cjs harmonyos_watch/scripts/*.test.mjs
```

Before distribution, verify pairing using the signed phone and watch artifacts,
then check code scanning, code expiry, reconnect, logout, and reminder delivery
on a supported watch. Unit tests cannot verify vendor authorization or optics.
