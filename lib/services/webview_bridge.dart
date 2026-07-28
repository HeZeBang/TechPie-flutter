const String techPieDocumentStartScript = r'''
(() => {
  window.__techPieBridgeReady = true;
  window.__techPieResolve = window.__techPieResolve || ((value) => value);
  const nativeTechPieBridge = window.TechPieBridge &&
      typeof window.TechPieBridge.postMessage === 'function'
    ? window.TechPieBridge
    : null;
  window.TechPieBridge = window.TechPieBridge || {
    postMessage(message) {
      let messageText;
      try {
        messageText = typeof message === 'string' ? message : JSON.stringify(message);
        if (typeof messageText !== 'string') {
          messageText = String(message);
        }
      } catch (_) {
        messageText = String(message);
      }

      try {
        if (nativeTechPieBridge) {
          return nativeTechPieBridge.postMessage(messageText);
        }
        if (window.chrome && window.chrome.webview &&
            typeof window.chrome.webview.postMessage === 'function') {
          return window.chrome.webview.postMessage(messageText);
        }
        if (window.webkit && window.webkit.messageHandlers &&
            window.webkit.messageHandlers.TechPieBridge &&
            typeof window.webkit.messageHandlers.TechPieBridge.postMessage === 'function') {
          return window.webkit.messageHandlers.TechPieBridge.postMessage(messageText);
        }
        window.__techPieBridgeLastError = 'TechPieBridge native transport unavailable';
        throw new Error(window.__techPieBridgeLastError);
      } catch (error) {
        window.__techPieBridgeLastError = String(error);
        throw error;
      }
    },
  };
  window.BH_MOBILE_SDK = window.BH_MOBILE_SDK || {};
  window.BH_MOBILE_SDK.bridge = window.TechPieBridge;
})();

''';
