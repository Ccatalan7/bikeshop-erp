# 🔄 Environment Switching Guide

## Quick Switch: Just Tell Me

**To test on STAGING (safe, isolated):**
```
"Run with staging"
```

**To test on PRODUCTION (real data):**
```
"Run with production"
```

## How It Works

### VS Code (Easiest - One Click)

**Press F5 or Run > Start Debugging, then select:**

1. **🧪 STAGING - Run (Development)** ← Default, safe for testing
2. **⚠️ PRODUCTION - Run (Development)** ← Real user data, use carefully

### Terminal / Command Line

**Staging (safe default):**
```bash
flutter run
# Uses staging automatically (no flags needed)
```

**Production (explicit override):**
```bash
flutter run \
  --dart-define=SUPABASE_URL=https://xzdvtzdqjeyqxnkqprtf.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inh6ZHZ0emRxamV5cXhua3FwcnRmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjAwNjQyMzUsImV4cCI6MjA3NTY0MDIzNX0.q5OswWMx6C00dbSHlFSOKlv6BA6GKx36VtVSy8ohxAM
```

## Safety Features

✅ **Staging is the default** - You can't accidentally hit production  
✅ **VS Code clearly labels** - "⚠️ PRODUCTION" has warning emoji  
✅ **Production requires explicit action** - Must select it from dropdown  
✅ **No mixed credentials** - Each environment has its own complete config  

## Files Created

- `.env.staging` → Staging credentials (kyvgmapifacpzuyreasy)
- `.env.production` → Production credentials (xzdvtzdqjeyqxnkqprtf)
- `lib/shared/config/supabase_config.dart` → Now defaults to staging
- `.vscode/launch.json` → Two new run configurations added

## Current Active Environment

The app shows which environment you're on:
- Check the Supabase dashboard URL in network requests
- Staging: `kyvgmapifacpzuyreasy.supabase.co`
- Production: `xzdvtzdqjeyqxnkqprtf.supabase.co`

## Testing the Switch

**1. Start with staging (default):**
```bash
flutter run
# Should connect to kyvgmapifacpzuyreasy
```

**2. Switch to production (explicit):**
- Press F5 → Select "⚠️ PRODUCTION - Run (Development)"
- Or use terminal command above

**3. Verify active environment:**
- Check login screen (should work on both)
- Create a test record → verify it appears in correct Supabase project dashboard
