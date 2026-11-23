# Watch runtime libraries

The Lite runtime uses ES5-compatible integer arithmetic for local SM2/SM3 campus codes and binary QR encoding.

- `sm2.js`, `utils.js`, `ec.js`, `sm3.js`: [sm-crypto 0.3.13](https://github.com/JuneAndGreen/sm-crypto), MIT. The signing subset retains the upstream signing, digest and point arithmetic. Encryption, verification, DER output and unused key-format utility functions are omitted. Imports point to the local integer library. The unused HMAC entry point is omitted. SM3 reads big-endian words explicitly and clears typed arrays with ES5 loops, and UTF-8 conversion uses URI byte escapes instead of Annex B `unescape`.
- `jsbn.js`: [jsbn 1.1.0](https://github.com/andyperlitch/jsbn), Tom Wu license. The browser entropy pool and ARC4 generator are replaced by an injected platform CSPRNG. Missing native entropy stops signing.
- `qrcode.js`: [qrcode-generator 1.4.4](https://github.com/kazuhikoarase/qrcode-generator), MIT. The byte/matrix subset preserves binary payloads and omits browser renderers and other input modes.

License texts are included beside the sources. Device latency is measured from signing through QR drawing; host timings do not establish watch performance.
