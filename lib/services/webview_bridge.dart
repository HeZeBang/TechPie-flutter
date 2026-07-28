const String techPieDocumentStartScript = r'''
(() => {
  window.__techPieBridgeReady = true;
  window.__techPieResolve = window.__techPieResolve || ((value) => value);
  window.BH_MOBILE_SDK = window.BH_MOBILE_SDK || {};
  window.BH_MOBILE_SDK.bridge = window.TechPieBridge;
})();
''';
