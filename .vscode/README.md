# VS Code Launch Configuration Setup

## 🔐 Auto-Login for Development Mode

To enable automatic authentication when running the app in debug mode:

### 1. Copy the example configuration
```powershell
Copy-Item .vscode\launch.json.example .vscode\launch.json
```

### 2. Edit `launch.json` and update credentials
Replace the placeholder values in the `🚀 Flutter: Run (Development)` configuration:

```json
{
  "name": "🚀 Flutter: Run (Development)",
  "args": [
    "--dart-define=DEBUG_EMAIL=your-email@example.com",  // ← Your Supabase email
    "--dart-define=DEBUG_PASSWORD=your-password-here"     // ← Your password
  ]
}
```

### 3. Run the development configuration
Select **"🚀 Flutter: Run (Development)"** from VS Code's debug dropdown (F5)

## ✅ How It Works

When running in debug mode (`kDebugMode`), the app will:
- Read `DEBUG_EMAIL` and `DEBUG_PASSWORD` from environment variables
- Automatically call `signInWithPassword()` if no session exists
- Skip auto-login if already authenticated
- Fall back to manual login screen on error

**Security Notes:**
- `launch.json` is gitignored to prevent committing credentials
- Auto-login only runs in debug mode (disabled in production)
- Use `launch.json.example` as template (safe to commit)

## 🔧 Other Configurations

- **🌐 Web (Chrome)**: Run app in Chrome browser with HTML renderer
- **🪟 Windows**: Run as native Windows desktop app

## Supabase Edge Function Diagnostics

Files under `supabase/functions/` run on Deno, not Node.js. The workspace settings
enable the Deno language server only for that folder so URL imports and globals
such as `Deno.env` are understood without changing TypeScript behavior elsewhere.

Install the recommended **Deno** extension when prompted. After first installing
or enabling it, reload the editor window so stale TypeScript problems are cleared.

## 📝 Troubleshooting

**Issue**: Auto-login not working
- Verify credentials are correct in `launch.json`
- Check console for: `✅ [AuthService] Auto-login successful!`
- Ensure you're running **Development** configuration (not Web/Windows)

**Issue**: "launch.json not found"
- Run: `Copy-Item .vscode\launch.json.example .vscode\launch.json`
- Edit the new file with your credentials
