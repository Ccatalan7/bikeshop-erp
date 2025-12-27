# Page Caching Problem Documentation

## Problem Statement

The public store website pages are being **disposed and recreated on every navigation**, causing:
- Data refetching on every page visit
- Loading spinners appearing repeatedly
- Loss of scroll position and form state
- Poor user experience

## Goal

Keep main pages (Home, Products, Contact, Cart, Account Dashboard) **alive in memory** when navigating between them, so `initState()` only runs once per session.

---

## Current Router Location

**File:** `/Users/Claudio/Dev/bikeshop-erp/lib/public_store/routes/public_store_router.dart`

---

## Approaches Tried

### 1. AutomaticKeepAliveClientMixin ❌ FAILED

**What we tried:** Added `AutomaticKeepAliveClientMixin` to all StatefulWidget pages.

**Why it failed:** This mixin only works inside `PageView`, `TabBarView`, or `ListView.builder` - widgets that use Flutter's `KeepAlive` internally. Standard `go_router` navigation **disposes widgets on every route change** by design.

**Evidence:** Debug prints showed `dispose()` called on every navigation:
```
🏠 [PublicHomePage] initState() called
🔄 [ProductCatalogPage] dispose() called  ← Widget destroyed
🔄 [ProductCatalogPage] initState() called ← Recreated from scratch
```

### 2. StatefulShellRoute.indexedStack ❌ NOT WORKING AS EXPECTED

**What we tried:** Refactored router to use `StatefulShellRoute.indexedStack` with 5 branches:
- Branch 0: Home (`/` and `/tienda`)
- Branch 1: Products (`/productos` and `/tienda/productos`)
- Branch 2: Contact (`/contacto` and `/tienda/contacto`)
- Branch 3: Cart (`/carrito` and `/tienda/carrito`)
- Branch 4: Account (`/cuenta` and `/tienda/cuenta`)

**Current Structure:**
```dart
StatefulShellRoute.indexedStack(
  builder: (context, state, navigationShell) {
    return _PublicStoreShell(navigationShell: navigationShell);
  },
  branches: [
    StatefulShellBranch(
      routes: [
        GoRoute(path: '/', ...),
        GoRoute(path: '/tienda', ...),
      ],
    ),
    StatefulShellBranch(
      routes: [
        GoRoute(path: '/productos', ...),
        GoRoute(path: '/tienda/productos', ...),
      ],
    ),
    // ... more branches
  ],
)
```

**Why it's failing:** Pages are STILL being disposed despite StatefulShellRoute. Debug prints still show:
```
🐚 [PublicStoreShell] build() - currentIndex: 1
🔄 [ProductCatalogPage] initState() called
🔄 [ProductCatalogPage] dispose() called  ← SHOULD NOT HAPPEN
📞 [ContactPage] initState() called
```

---

## Potential Root Causes to Investigate

### 1. PublicStoreLayout Might Be Forcing Rebuilds

The shell wraps pages in `PublicStoreLayout`:
```dart
class _PublicStoreShellState extends State<_PublicStoreShell> {
  @override
  Widget build(BuildContext context) {
    return PublicStoreLayout(
      child: widget.navigationShell,  // This is the IndexedStack
    );
  }
}
```

**File:** `/Users/Claudio/Dev/bikeshop-erp/lib/public_store/widgets/public_store_layout.dart`

`PublicStoreLayout` is a **StatefulWidget** (3700+ lines). It might be:
- Rebuilding on every navigation due to providers
- Recreating its child subtree unnecessarily
- Using context.watch() on providers that change during navigation

### 2. Shell Widget Wrapper Might Be Problematic

The current `_PublicStoreShell` is a StatefulWidget that receives `StatefulNavigationShell` as a prop. This might cause the widget to be recreated if go_router creates a new shell instance on each build.

**Possible fix:** Remove the StatefulWidget wrapper and use the shell directly:
```dart
StatefulShellRoute.indexedStack(
  builder: (context, state, navigationShell) {
    return PublicStoreLayout(
      child: navigationShell,
    );
  },
)
```

### 3. Navigator Keys Might Be Missing

Each `StatefulShellBranch` might need its own `navigatorKey` to properly cache state:
```dart
StatefulShellBranch(
  navigatorKey: GlobalKey<NavigatorState>(),  // Add this?
  routes: [...],
)
```

### 4. Navigation Method Might Be Wrong

When navigating via header links, the app might be using `context.go()` instead of `navigationShell.goBranch()`. This could bypass the shell's branch switching.

**Check:** How are the navigation links in the header implemented?  
**File:** `/Users/Claudio/Dev/bikeshop-erp/lib/public_store/widgets/public_store_layout.dart`

---

## Key Files to Investigate

1. **Router:** `/lib/public_store/routes/public_store_router.dart` (614 lines)
2. **Layout:** `/lib/public_store/widgets/public_store_layout.dart` (3700+ lines)
3. **Home Page:** `/lib/public_store/pages/public_home_page.dart`
4. **Products Page:** `/lib/public_store/pages/product_catalog_page.dart`
5. **Contact Page:** `/lib/public_store/pages/contact_page.dart`

---

## Debug Prints Already Added

These pages have debug prints in `initState()`, `dispose()`, and `build()`:
- `public_home_page.dart` - prefix `🏠`
- `product_catalog_page.dart` - prefix `🔄`
- `contact_page.dart` - prefix `📞`

The shell has a debug print showing `currentIndex`:
```dart
debugPrint('🐚 [PublicStoreShell] build() - currentIndex: ${widget.navigationShell.currentIndex}');
```

---

## Expected Behavior (When Fixed)

1. Navigate Home → Products → Contact → Home
2. Console should show:
   - `🏠 [PublicHomePage] initState()` - **ONCE** (first visit)
   - `🔄 [ProductCatalogPage] initState()` - **ONCE** (first visit)
   - `📞 [ContactPage] initState()` - **ONCE** (first visit)
   - **NO dispose() calls** when switching between shell pages
   - Only `build()` calls on the visible page

---

## Reference: go_router StatefulShellRoute

Official documentation: https://pub.dev/documentation/go_router/latest/go_router/StatefulShellRoute-class.html

The `IndexedStack` variant should keep all branch navigators alive:
> "The indexedStack factory uses an IndexedStack widget to manage the branch navigators, keeping all branches in memory."

---

## Summary

The issue is that `StatefulShellRoute.indexedStack` is implemented but pages are still being disposed. Something in the widget tree (likely `PublicStoreLayout` or the shell wrapper) is causing the branch pages to be recreated instead of preserved.

**Key question:** Why is the IndexedStack not keeping pages alive as documented?
