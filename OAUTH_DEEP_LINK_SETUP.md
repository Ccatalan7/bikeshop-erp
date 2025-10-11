# Google OAuth Deep Link Setup for Windows Desktop

## Overview
This app now uses deep links to handle Google OAuth callbacks on Windows desktop. This fixes the "localhost refused to connect" error.

## 🔧 Required Configuration

### 1. Supabase Dashboard Configuration

1. **Go to**: https://supabase.com/dashboard/project/xzdvtzdqjeyqxnkqprtf/auth/url-configuration

2. **In "Redirect URLs" section**, add:
   ```
   io.supabase.vinabikeerp://login-callback
   ```

3. **Click "Save"**

### 2. Google Cloud Console Configuration

1. **Go to**: https://console.cloud.google.com/apis/credentials

2. **Click on your OAuth 2.0 Client ID** (the one you created for this app)

3. **Click "Edit"**

4. **In "Authorized redirect URIs"**, make sure you have BOTH:
   ```
   https://xzdvtzdqjeyqxnkqprtf.supabase.co/auth/v1/callback
   io.supabase.vinabikeerp://login-callback
   ```

5. **Click "Save"**

6. **Wait 1-2 minutes** for changes to propagate

### 3. Verify Google Provider in Supabase

1. **Go to**: https://supabase.com/dashboard/project/xzdvtzdqjeyqxnkqprtf/auth/providers

2. **Ensure "Google" is enabled**

3. **Verify your Client ID and Client Secret are filled in**

4. **Click "Save"** if you made any changes

## 🔄 How It Works

1. User clicks "Continuar con Google" in your app
2. App opens browser with Google OAuth page
3. User selects Google account and authorizes
4. Google redirects to Supabase: `https://xzdvtzdqjeyqxnkqprtf.supabase.co/auth/v1/callback`
5. Supabase processes the OAuth and redirects to: `io.supabase.vinabikeerp://login-callback`
6. Windows app catches this deep link via `app_links` package
7. Supabase auth state updates automatically
8. User is logged in! ✅

## 🧪 Testing

After configuring the above:

1. **Stop** the current app (press `q` in the terminal)
2. **Run**: `flutter run -d windows`
3. **Click** "Continuar con Google"
4. **Select** your Google account
5. **Browser should redirect** and the app should log you in
6. **No more "localhost refused" error!**

## ❗ Important Notes

- The deep link scheme is: `io.supabase.vinabikeerp://`
- This works on **Windows, Android, and iOS** (not needed for Web)
- Make sure both redirect URIs are in Google Cloud Console
- Allow 1-2 minutes after saving for Google to propagate changes

## 🐛 Troubleshooting

### Still seeing "localhost refused"?
- Check that you added the deep link to **both** Supabase and Google Console
- Wait 2-3 minutes after saving changes in Google Console
- Clear browser cache/cookies and try again
- Make sure the `app_links` package is properly installed (`flutter pub get`)

### App doesn't respond after selecting account?
- Check Supabase logs: https://supabase.com/dashboard/project/xzdvtzdqjeyqxnkqprtf/logs/explorer
- Verify the deep link listener is running (check terminal for "[DeepLink] Received:" messages)
- Ensure Google provider is enabled in Supabase with correct credentials

### "Invalid redirect URI" error?
- The redirect URI in Google Console must **exactly match** what Supabase sends
- Check for typos or extra spaces
- Ensure you have both URIs added (Supabase callback + deep link)

## 📱 Android Configuration (Future)

When building for Android, you'll need to add this to `android/app/src/main/AndroidManifest.xml`:

```xml
<intent-filter>
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data android:scheme="io.supabase.vinabikeerp" />
</intent-filter>
```

This is already handled by the `app_links` package, but you may need to verify it.

## 🎯 Next Steps After Setup

1. ✅ Configure Supabase redirect URLs
2. ✅ Configure Google Console redirect URIs
3. ✅ Test Google Sign-In on Windows
4. 🔄 Rebuild Android APK with updated OAuth
5. 🔄 Test on Android device
6. 🔄 Deploy to production

---

**Last Updated**: 2025-10-11
**App Version**: 1.0.0+1
**Supabase Project**: xzdvtzdqjeyqxnkqprtf
**Deep Link Scheme**: io.supabase.vinabikeerp
