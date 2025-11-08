# Realtime Service Initialization Blocking Issue

## Problem

**Symptom:** App freezes when navigating to pages that instantiate services with Supabase realtime subscriptions.

**Root Cause:** Service constructors calling `async void` methods that set up realtime subscriptions block the UI thread until completion, causing visible freezes on navigation.

**Example of Problematic Code:**
```dart
class CustomerService extends ChangeNotifier {
  CustomerService() {
    _setupCustomersRealtime(); // Blocks UI thread
  }
  
  // ❌ WRONG: async void blocks
  async void _setupCustomersRealtime() {
    await Supabase.instance.client
        .from('customers')
        .stream(primaryKey: ['id'])
        .listen((data) { /* ... */ });
  }
}
```

## Solution

Change realtime setup methods from `async void` to `Future<void>` to prevent blocking.

**Fixed Code:**
```dart
class CustomerService extends ChangeNotifier {
  CustomerService() {
    _setupCustomersRealtime(); // Non-blocking fire-and-forget
  }
  
  // ✅ CORRECT: Future<void> doesn't block
  Future<void> _setupCustomersRealtime() async {
    await Supabase.instance.client
        .from('customers')
        .stream(primaryKey: ['id'])
        .listen((data) { /* ... */ });
  }
}
```

## Services Fixed

- `lib/modules/crm/services/customer_service.dart` (line 349)
- `lib/shared/services/inventory_service.dart` (line 415)
- `lib/modules/bikeshop/services/bikeshop_service.dart` (line 621)

## How to Identify

**Search Pattern:**
```bash
grep -r "async void _setup.*Realtime" lib/
```

**Signs of Issue:**
- App freezes on navigation to specific pages
- Delay when instantiating service classes
- Constructor calls methods with `async void` signature

## Prevention

**Rule:** Never use `async void` in constructor-called methods. Always use `Future<void>` for fire-and-forget async operations.

**Why:** 
- `async void` = synchronous call that blocks until complete
- `Future<void>` = asynchronous call that returns immediately

## Testing Checklist

When adding new services with realtime subscriptions:
- [ ] Constructor calls realtime setup method
- [ ] Setup method signature is `Future<void>` (NOT `async void`)
- [ ] Test navigation to page using service - should be instant
- [ ] Verify realtime updates still work after change

## Related Issues

This issue may affect ANY service with Supabase realtime subscriptions. Audit all services in:
- `lib/modules/*/services/`
- `lib/shared/services/`

Search for pattern: `async void _setup` + `.stream(` or `.on(`
