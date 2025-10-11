# 🔐 Google Sign-In Setup Guide

## ✅ Code Changes Complete!

I've already added all the necessary code to your app. Now you just need to configure Google and Supabase.

---

## 📋 STEP-BY-STEP SETUP (Do This Once)

### **PART 1: Google Cloud Console Setup**

#### Step 1: Create Google Cloud Project

1. **Go to Google Cloud Console**
   - Visit: https://console.cloud.google.com/
   - Sign in with your Google account

2. **Create a New Project**
   - Click the project dropdown (top left)
   - Click "NEW PROJECT"
   - Project name: `VinaBike ERP` (or any name)
   - Click "CREATE"
   - Wait for the project to be created (~30 seconds)
   - **Select the project** from the dropdown

#### Step 2: Configure OAuth Consent Screen

1. **Go to OAuth Consent Screen**
   - Left menu → "APIs & Services" → "OAuth consent screen"
   
2. **Choose User Type**
   - Select **"External"**
   - Click "CREATE"

3. **Fill in App Information**
   - **App name**: `VinaBike ERP`
   - **User support email**: Your email (select from dropdown)
   - **App logo**: (Optional, can skip)
   - **App domain**: (Can skip for now)
   - **Authorized domains**: (Can skip for now)
   - **Developer contact information**: Your email
   - Click "SAVE AND CONTINUE"

4. **Scopes Page**
   - Just click "SAVE AND CONTINUE" (don't add scopes)

5. **Test Users Page**
   - Click "SAVE AND CONTINUE" (can add test users later)

6. **Summary Page**
   - Review and click "BACK TO DASHBOARD"

#### Step 3: Create OAuth Credentials

1. **Go to Credentials**
   - Left menu → "APIs & Services" → "Credentials"

2. **Create OAuth Client ID**
   - Click "+ CREATE CREDENTIALS" (top)
   - Select "OAuth client ID"
   
3. **Configure Client**
   - **Application type**: Select **"Web application"**
   - **Name**: `VinaBike ERP Web Client`
   - **Authorized JavaScript origins**: Leave EMPTY for now
   - **Authorized redirect URIs**: We'll add this in the next step
   - Click "CREATE"

4. **Save Your Credentials**
   - A popup will show your **Client ID** and **Client Secret**
   - **COPY BOTH** (you'll need them in Supabase)
   - Click "OK"

---

### **PART 2: Supabase Configuration**

#### Step 4: Get Supabase Callback URL

1. **Go to Supabase Dashboard**
   - Visit: https://supabase.com/dashboard
   - Sign in
   - Select your **VinaBike project**

2. **Navigate to Authentication**
   - Left sidebar → Click "Authentication"
   - Click "Providers" tab

3. **Find Google Provider**
   - Scroll down to find "Google" in the provider list
   - You'll see a **"Callback URL (for OAuth)"**
   - **COPY THIS URL** - it looks like:
     ```
     https://xxxxxxxxxx.supabase.co/auth/v1/callback
     ```

#### Step 5: Add Callback URL to Google

1. **Go Back to Google Cloud Console**
   - Go to "APIs & Services" → "Credentials"
   - Click on your OAuth client (the one you created)

2. **Add Redirect URI**
   - Under "Authorized redirect URIs"
   - Click "+ ADD URI"
   - **Paste the Supabase callback URL** you copied
   - Click "SAVE" (bottom right)

#### Step 6: Enable Google in Supabase

1. **Back to Supabase Dashboard**
   - Authentication → Providers
   - Find "Google" in the list

2. **Enable and Configure**
   - Toggle the switch to **ENABLE** Google
   - **Client ID**: Paste the Google Client ID
   - **Client Secret**: Paste the Google Client Secret
   - Leave other settings as default
   - Click "Save"

---

## 🎯 **THAT'S IT! Setup Complete!**

---

## 🧪 How to Test

### On Windows:
1. Run the app: `flutter run -d windows`
2. You'll see the login screen
3. Click "Continuar con Google" button
4. Browser opens with Google sign-in
5. Choose your Google account
6. You'll be redirected back to the app
7. Should automatically log in!

### On Android:
1. Install the APK on your phone
2. Same process as above
3. Google sign-in opens in Chrome or in-app browser

---

## 🎨 What I Changed in the Code

### 1. **AuthService** (`lib/shared/services/auth_service.dart`)
Added new method:
```dart
Future<bool> signInWithGoogle() async {
  final response = await _client.auth.signInWithOAuth(
    OAuthProvider.google,
    redirectTo: 'io.supabase.vinabikeerp://login-callback/',
  );
  return response;
}
```

### 2. **Login Screen** (`lib/shared/screens/login_screen.dart`)
Added:
- New `_signInWithGoogle()` method
- "Continuar con Google" button with Google logo
- Divider with "o continuar con" text
- Error handling for Google sign-in

---

## 🔧 Troubleshooting

### Problem: "Error 400: redirect_uri_mismatch"
**Solution**: 
- Make sure the Supabase callback URL is EXACTLY in Google Cloud Console
- Check for typos, extra spaces, or http vs https

### Problem: Google button doesn't work
**Solution**:
- Check that Google provider is enabled in Supabase (toggle should be ON)
- Verify Client ID and Secret are correct
- Check browser console for errors

### Problem: "Access blocked: This app's request is invalid"
**Solution**:
- Complete the OAuth consent screen setup in Google Cloud
- Make sure app is published or your email is added as test user

### Problem: User gets logged in but redirects to wrong page
**Solution**:
- Check the app router in `lib/shared/routes/app_router.dart`
- The auth state listener should handle navigation to `/dashboard`

---

## 📱 Android Deep Linking (Optional Enhancement)

If you want better mobile experience, you can set up deep linking:

1. **Add to AndroidManifest.xml**:
```xml
<intent-filter>
  <action android:name="android.intent.action.VIEW" />
  <category android:name="android.intent.category.DEFAULT" />
  <category android:name="android.intent.category.BROWSABLE" />
  <data
    android:scheme="io.supabase.vinabikeerp"
    android:host="login-callback" />
</intent-filter>
```

This is already configured in the code with:
```dart
redirectTo: 'io.supabase.vinabikeerp://login-callback/'
```

---

## 🎉 Benefits of Google Sign-In

✅ **No password needed** - Users sign in with Google  
✅ **Faster onboarding** - One-click registration  
✅ **More secure** - Google handles security  
✅ **Better UX** - Familiar login flow  
✅ **Auto profile** - Gets name and email from Google  

---

## 📊 What Happens Behind the Scenes

1. User clicks "Continuar con Google"
2. App opens browser with Google OAuth page
3. User selects Google account and authorizes
4. Google redirects to Supabase callback URL
5. Supabase creates/updates user in database
6. Supabase redirects back to your app
7. App receives auth token
8. User is logged in!

---

## 🔐 Security Notes

- **Client Secret is safe** - It's stored in Supabase, not in your app
- **Token refresh** - Supabase handles automatic token refresh
- **Logout works** - Users can sign out and sign back in
- **Multi-provider** - Users can have both email and Google login

---

## 📝 Summary Checklist

- [ ] Create Google Cloud project
- [ ] Configure OAuth consent screen
- [ ] Create OAuth client credentials
- [ ] Copy Client ID and Secret
- [ ] Get Supabase callback URL
- [ ] Add callback URL to Google Console
- [ ] Enable Google provider in Supabase
- [ ] Paste Client ID and Secret in Supabase
- [ ] Test login on Windows
- [ ] Test login on Android

---

**Need help?** Just paste any error messages and I'll help you fix them!

**Estimated setup time**: 10-15 minutes ⏱️
