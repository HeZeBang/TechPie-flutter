# TechPie mobile_scanner iOS implementation

This native-only platform package implements the existing `mobile_scanner`
method and event channels. Flutter selects it on iOS through `implements`;
the pinned dependency still supplies Dart, Android, OHOS, macOS and web code.

The iOS source and privacy manifest are derived from
`HeZeBang/mobile_scanner_ohos` commit
`83e7071204dd07dd84763f0e1b6d1f977b97fd7c`:
https://github.com/HeZeBang/mobile_scanner_ohos

The upstream BSD license is preserved in `LICENSE`.

The camera uses 1280x720 video when supported. Preview updates and first-frame
notifications stay on the main queue; a serial worker recognizes sample buffers
directly with ML Kit. Only `returnImage: true` requests create JPEG data, using
a reusable Core Image context. In-flight work is bounded to one scan, and
results from a stopped camera are discarded. Freeze, restart and forced-stop
commands keep their existing channel behavior.

The preview buffer synchronizes replacement, clearing and raster-thread retention
with a lock, so stopping the camera cannot invalidate a frame being rendered.

Run the camera scheduling tests on macOS with:

```sh
swift test --package-path packages/techpie_mobile_scanner_ios
```
