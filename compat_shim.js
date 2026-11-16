/**
 * Chrome MV3 -> Firefox MV2 compatibility shim for Endpoint Verification.
 * Loaded before background_service_worker.js in the (non-persistent) event page.
 *
 * Stubs Chrome-only APIs (enterprise.*, platformKeys, gcm, offscreen, identity)
 * so Google's compiled background script runs unmodified on Firefox.
 *
 * No network traffic is intercepted, logged, or rewritten. Auth headers are
 * passed through untouched: the extension signs SAPISIDHASH with its real
 * moz-extension:// origin and declares it via the X-Origin header, which is
 * Google's own built-in Firefox path in the background script.
 */
(() => {
  'use strict';

  // ---------------------------------------------------------------- helpers
  const cback = (args, value) => {
    const fn = args && args[args.length - 1];
    if (typeof fn === 'function') {
      try { fn(value); } catch (e) { /* listener errors must not break the shim */ }
    }
  };
  const stub = (...args) => cback(args, undefined);
  const enumObj = (obj) => Object.freeze(Object.assign({}, obj));
  const eventStub = () => {
    const listeners = new Set();
    return {
      addListener: (fn) => { if (typeof fn === 'function') listeners.add(fn); },
      removeListener: (fn) => listeners.delete(fn),
      hasListener: (fn) => listeners.has(fn),
      hasListeners: () => listeners.size > 0,
    };
  };

  // ---------------------------------------------------------------- aliases
  if (typeof chrome.action === 'undefined' && typeof chrome.browserAction !== 'undefined') {
    chrome.action = chrome.browserAction;
  }

  // ------------------------------------------------------- enterprise stubs
  if (typeof chrome.enterprise === 'undefined') chrome.enterprise = {};
  const ent = chrome.enterprise;

  ent.deviceAttributes = {
    getDirectoryDeviceId: stub,
    getDeviceSerialNumber: stub,
    getDeviceAssetId: stub,
    getAnnotatedAssetId: stub,
    getRequestId: stub,
  };

  ent.reportingPrivate = {
    SettingValue: enumObj({ ENABLED: 'ENABLED', DISABLED: 'DISABLED' }),
    PasswordProtectionTrigger: enumObj({ PASSWORD: 'PASSWORD', PHISHING: 'PHISHING', UNSAFE: 'UNSAFE' }),
    SafeBrowsingLevel: enumObj({ DISABLED: 'DISABLED', STANDARD: 'STANDARD', ENHANCED: 'ENHANCED' }),
    RealtimeUrlCheckMode: enumObj({ DISABLED: 'DISABLED', ENABLED: 'ENABLED' }),
    CertificateStatus: enumObj({ OK: 'OK', POLICY: 'POLICY' }),
    getPersistentSecret: stub,
    getDeviceId: stub,
    getDeviceInfo: stub,
    getDeviceData: stub,
    setDeviceData: stub,
    getContextInfo: stub,
    getCertificate: stub,
  };

  ent.platformKeys = {
    getTokens: stub,
    getCertificates: stub,
    importCertificate: stub,
    removeCertificate: stub,
    challengeMachineKey: stub,
    challengeUserKey: stub,
  };

  if (typeof chrome.platformKeys === 'undefined') {
    chrome.platformKeys = {
      getKeyPair: stub,
      getKeyPairs: stub,
      selectClientCertificates: stub,
    };
  }

  // ------------------------------------------------------------------- gcm
  if (typeof chrome.gcm === 'undefined') {
    chrome.gcm = {
      onMessage: eventStub(),
      register: stub,
      unregister: stub,
      send: stub,
    };
  }

  // --------------------------------------------------------------- offscreen
  if (typeof chrome.offscreen === 'undefined') {
    chrome.offscreen = {
      Reason: enumObj({
        AUDIO_PLAYBACK: 'AUDIO_PLAYBACK',
        BLOBS: 'BLOBS',
        CLIPBOARD: 'CLIPBOARD',
        DISPLAY_MEDIA: 'DISPLAY_MEDIA',
        DOM_PARSER: 'DOM_PARSER',
        DOM_SCRAPING: 'DOM_SCRAPING',
        IFRAME_SCRIPTING: 'IFRAME_SCRIPTING',
        MATCH_MEDIA: 'MATCH_MEDIA',
        TESTING: 'TESTING',
        USER_MEDIA: 'USER_MEDIA',
        WORKERS: 'WORKERS',
      }),
      createDocument: stub,
      closeDocument: stub,
      hasDocument: stub,
    };
  }

  // --------------------------------------------------------------- identity
  if (typeof chrome.identity === 'undefined') {
    chrome.identity = {
      AccountStatus: enumObj({ ANY: 'ANY', SYNC: 'SYNC' }),
      onSignInChanged: eventStub(),
      getAuthToken: stub,
      getProfileUserInfo: (...a) => cback(a, { email: '', id: '' }),
      launchWebAuthFlow: stub,
      getRedirectURL: (p) =>
        'https://' + (chrome.runtime.id || 'unknown') + '.extensions.allizom.org/' + (p || ''),
    };
  }

  // ------------------------------------------------------ management.getSelf
  if (typeof chrome.management !== 'undefined' && typeof chrome.management.getSelf === 'undefined') {
    chrome.management.getSelf = (...a) => {
      const m = chrome.runtime.getManifest();
      cback(a, {
        id: chrome.runtime.id,
        name: m.name,
        version: m.version,
        type: 'extension',
        enabled: true,
        installType: 'development',
      });
    };
  }

  // ------------------------------------------------------------ idle extras
  if (typeof chrome.idle !== 'undefined') {
    if (typeof chrome.idle.getAutoLockDelay === 'undefined') chrome.idle.getAutoLockDelay = stub;
    if (typeof chrome.idle.setDetectionInterval === 'undefined') {
      chrome.idle.setDetectionInterval = stub;
    }
  }
})();
