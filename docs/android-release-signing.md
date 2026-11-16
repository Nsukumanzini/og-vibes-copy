# OG Vibes Android release signing

The Android release build reads its private upload key from:

- `android/app/og-vibes-upload.jks`
- `android/key.properties`

Both files are ignored by Git. Run this once if they do not exist:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\setup_android_signing.ps1
```

Back up both files together in at least two encrypted locations. Do not email
them, commit them, upload them to Vercel, or share their passwords. Every future
OG Vibes Android release must use this same upload key.

Verify a built APK with:

```powershell
keytool -printcert -jarfile .\build\app\outputs\flutter-apk\app-release.apk
```
