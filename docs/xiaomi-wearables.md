# Xiaomi wearable integration

The settings entry groups the existing Apple Watch settings with an Android-only Xiaomi device list. Apple Watch online/offline preferences, session synchronization and payment checks remain upstream's implementation. The application ID, release version, update endpoint and signing configuration are unchanged; no RCCE test keystore is included.

Android uses XMS Wearable SDK 1.4 to discover the connected device, request permission, exchange course/deadline snapshots, schedule class reminders and optionally export offline payment data after explicit confirmation. Reminder delivery can be delayed by the OS. APK signing identity and application registration must be approved by Xiaomi for the production app; the development RCCE certificate is not a substitute for that registration.

The bundled `vela_app` is a **diagnostic companion**, with connection state, test messages and a protocol/signature library. It does not yet provide the complete timetable or payment UI. The phone-side protocol is not proof of end-to-end wrist payment support. Device names in the selector are connection matching options, not a certification matrix.

Offline credentials default off and are only exported after user confirmation. They must not be logged. Tests cover SM2 interoperability and device-list behavior; physical pairing, permission approval, signing registration and scans need a compatible watch and the production identity.
