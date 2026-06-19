# Google OAuth Setup (Quickstart)

Mobile sign-in uses the native **Google Sign-In** SDK (not a WebView). You need **two** OAuth clients in the same Google Cloud project.

## 1. Web application client (backend token exchange)

- Go to https://console.cloud.google.com/apis/credentials
- **Create Credentials → OAuth client ID → Web application**
- Name: e.g. `Timely Backend`
- **Authorized redirect URIs** (optional, for browser testing only):
  - `http://localhost:8000/api/v1/google/callback`
- Leave **Authorized JavaScript origins** empty.
- Copy **Client ID** and **Client secret** into `backend/.env`:

```env
GOOGLE_OAUTH_CLIENT_ID=<web-client-id>
GOOGLE_OAUTH_CLIENT_SECRET=<web-client-secret>
GOOGLE_OAUTH_REDIRECT_URI=http://localhost:8000/api/v1/google/callback
```

> Web clients only accept `http://` or `https://` redirect URIs. Custom schemes like `com.googleusercontent.apps...` are **not** allowed here.

## 2. Android client (required for the mobile app)

In the **same Google Cloud project**, create a second OAuth client:

- **Create Credentials → OAuth client ID → Android**
- Package name: `com.example.kairos`
- SHA-1 certificate fingerprint (debug keystore):

```powershell
keytool -list -v -keystore "$env:USERPROFILE\.android\debug.keystore" -alias androiddebugkey -storepass android -keypass android
```

Example SHA-1: `0E:71:A3:18:04:8A:5C:68:4A:A1:41:18:A7:9E:E9:93:C4:24:D6:AD`

No redirect URI is needed for the Android client.

## 3. Enable Google Calendar API

In Google Cloud Console → **APIs & Services → Library**, enable **Google Calendar API**.

## 4. OAuth consent screen

Configure the OAuth consent screen and add your Google account as a **test user** while the app is in testing mode.

## 5. Run locally

```powershell
cd backend
python -m uvicorn app.main:app --reload --port 8000
```

```powershell
cd frontend
flutter run
```

Open **Account → Connect**. Sign-in uses the native Google account picker (not a WebView).

## Troubleshooting

| Error | Fix |
|---|---|
| `403 disallowed_useragent` | Old WebView flow — rebuild app after pulling latest code |
| `Invalid redirect: Must use http or https` | Custom scheme in **Web** client — use Android client instead |
| `ApiException: 10` / sign-in fails silently | Android OAuth client missing or SHA-1 / package name mismatch |
| `server auth code` is null | `serverClientId` in app must match the **Web** client ID |
