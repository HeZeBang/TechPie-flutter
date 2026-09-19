# Watch support dependencies

The watch builds these C sources locally; no prebuilt binary or runtime download is required.

- GmSSL: https://github.com/guanzhi/GmSSL, commit `24ae482701a7b124826c382fffc55c19f76d475d`.
  Selected sources and their transitive headers are copied unchanged into
  `Sources/CWatchCrypto/gmssl`. The Apache 2.0 license is retained there, along
  with each file's copyright notices. `sm2_z256.c` retains its upstream
  OpenSSL/Intel notices. Only portable C is compiled, without architecture assembly,
  network/TLS code or key-file serialization. `WatchCrypto.c` supplies the small
  public-key setter needed by `sm2_sign.c`, validates the private scalar, invokes
  upstream SM2/SM3, and returns the raw 64-byte `r || s` signature used by the
  existing Dart protocol. Randomness uses upstream `rand_apple.c` and
  `SecRandomCopyBytes`.
- Nayuki QR Code generator: https://github.com/nayuki/QR-Code-generator, commit
  `3c6d0b3cefb4e049dc337e82237c9644399716a8`. Its C implementation and MIT license
  headers are retained in `Sources/CWatchCrypto/qrcodegen`. The wrapper uses byte
  mode at error correction level L without text/UTF-8 transcoding.

To update, compare upstream changes, preserve notices, and rerun the Swift tests,
including the Dart signature interoperability fixture and device builds.
