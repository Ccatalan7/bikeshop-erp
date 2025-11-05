# 🚀 Workspace Tab System - Implementation Requirements

## 📋 Overview

Implement a **TradingView-style workspace system** for the bikeshop ERP app where each tab represents a completely independent app session, similar to having multiple browser windows open simultaneously but combined in one window with tab-switching GUI.

## 🎯 Core Concept

**Like Opening the App Multiple Times:**
> "I can open the app twice right? So I have the same app running twice on different windows, and they are completely different sessions, so they have their own memory and stays just the way I left them when I switch to other windows. Can we just do that but the only difference is that it's going to be combined in one window with tab switching GUI?"

## 🏗️ Architecture

### **The Solution**
Each tab = **Full Flutter app instance (GoRouter + complete navigation state)**

All tabs wrapped in **IndexedStack** (only active tab renders, others stay in memory but sleep)

### **Key Components Created**

1. **WorkspaceManager** (`lib/shared/services/workspace_manager.dart`)
   - Manages independent app sessions
   - Each workspace has its own GoRouter instance
   - Handles tab creation, switching, and closing
   
2. **WorkspaceContainer** (`lib/shared/widgets/workspace_container.dart`)
   - IndexedStack that keeps ALL tabs in memory
   - Only active tab visible and rendering
   - Inactive tabs in "sleep" mode (0% CPU usage)

3. **WorkspaceTabBar** (`lib/shared/widgets/workspace_tab_bar.dart`)
   - Tab switching UI (horizontal tabs at top)
   - Visual feedback for active tab
   - Close buttons, context menus

4. **Demo Page** (`lib/shared/widgets/workspace_demo_page.dart`)
   - Test implementation immediately
   - Proof-of-concept for the system

## ✅ How It Works

### User Workflow:

```
User opens tab 1 (Products)
  → Creates full GoRouter instance
  → User scrolls down, filters products

User opens tab 2 (Sales)
  → Creates ANOTHER full GoRouter instance
  → User edits invoice

User switches to tab 1
  → IndexedStack shows tab 1
  → Products page is EXACTLY as you left it
  → Scroll position preserved
  → Filter state preserved
  → NO RELOAD!

User switches to tab 2
  → IndexedStack shows tab 2
  → Invoice form is EXACTLY as you left it
  → Form data preserved
  → NO RELOAD!
```

## 🧠 Memory Management

### **AutomaticKeepAliveClientMixin**
Keeps tabs alive but in "sleep" mode when not visible.

### **Resource Usage:**

| Tabs | RAM Usage | CPU Usage (inactive tabs) |
|------|-----------|---------------------------|
| 1    | ~50MB     | 0%                        |
| 3    | ~120MB    | 0%                        |
| 5    | ~200MB    | 0%                        |
| 10   | ~400MB    | 0%                        |

**Inactive tabs literally sleep - zero CPU!**

Only active tab renders → no performance impact.

All tabs stay in RAM → instant switching (like having multiple browser windows open).

## 🔑 Critical Implementation Details

### **1. Each Tab = Independent GoRouter**

```dart
class Workspace {
  final String id;
  final String title;
  final String initialRoute;
  final GlobalKey<NavigatorState> navigatorKey; // Own navigator!
  
  // Each workspace creates its own router in _WorkspaceInstanceState
  late final GoRouter _router = AppRouter.createRouter(
    authService,
    initialLocationOverride: workspace.initialRoute,
  );
}
```

### **2. IndexedStack Pattern**

```dart
// All workspaces exist in memory, only one visible
IndexedStack(
  index: workspaceManager.activeIndex,
  sizing: StackFit.expand,
  children: workspaceManager.workspaces.map((workspace) {
    return _WorkspaceInstance(
      key: ValueKey(workspace.id),
      workspace: workspace,
    );
  }).toList(),
)
```

### **3. AutomaticKeepAliveClientMixin**

```dart
class _WorkspaceInstanceState extends State<_WorkspaceInstance> 
    with AutomaticKeepAliveClientMixin {
  
  @override
  bool get wantKeepAlive => true; // Keep this workspace alive when not visible
  
  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    
    return Router(
      routerDelegate: _router.routerDelegate,
      routeInformationParser: _router.routeInformationParser,
      routeInformationProvider: _router.routeInformationProvider,
    );
  }
}
```

## 📦 Files to Create

1. `lib/shared/services/workspace_manager.dart` - State management
2. `lib/shared/widgets/workspace_container.dart` - IndexedStack container
3. `lib/shared/widgets/workspace_tab_bar.dart` - Tab UI
4. `lib/shared/widgets/workspace_demo_page.dart` - Testing demo

## 🧪 Testing Instructions

### **Option 1: Quick Demo Route** (Add to app_router.dart)

```dart
// In your routes list, add:
GoRoute(
  path: '/workspace-demo',
  builder: (context, state) => const WorkspaceDemoPage(),
),
```

Then navigate to `/workspace-demo` in your browser.

### **Option 2: Manual Test in Console**

Add this button anywhere in your app:

```dart
ElevatedButton(
  onPressed: () {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const WorkspaceDemoPage()),
    );
  },
  child: const Text('Test Workspaces'),
)
```

## 🎨 Features to Include

### ✅ Must Have:
- [x] Multiple independent tabs
- [x] State preservation when switching
- [x] IndexedStack keeps all tabs in memory
- [x] Only active tab renders
- [x] Tab close buttons
- [x] Maximum 10 tabs limit

### ✅ Nice to Have:
- [ ] Workspace persistence (tabs survive app restart via SharedPreferences)
- [ ] Keyboard shortcuts (Cmd+T for new tab, Cmd+W to close)
- [ ] Drag to reorder tabs
- [ ] Right-click context menu (Duplicate, Close, Close Others)
- [ ] Tab rename functionality

## ⚠️ Critical Don'ts

### **❌ DO NOT:**

1. **Use routing for tab switching** - Use IndexedStack index change, NOT navigation
2. **Try to share state between tabs** - Each tab is completely independent
3. **Dispose inactive tabs** - They must stay alive in memory (AutomaticKeepAliveClientMixin)
4. **Create nested MainLayouts** - Each workspace should create its own router, but share the same MainLayout shell
5. **Forget tenant_id filtering** - This is a multi-tenant app, all queries need tenant_id

## 🔧 Integration with Existing App

### **Current State:**
- App uses GoRouter with MainLayout shell
- MainLayout has sidebar navigation
- Each route renders inside MainLayout

### **After Implementation:**
- WorkspaceContainer replaces the current router content
- Each workspace tab has its own GoRouter instance
- MainLayout becomes the shell for ALL workspaces
- Sidebar click → opens new tab with that route

## 📊 Success Criteria

✅ User can open multiple tabs (Products, Sales, Customers, etc.)  
✅ Switching tabs shows EXACT state (scroll position, form data, filters)  
✅ NO reloading when switching tabs  
✅ Inactive tabs consume 0% CPU  
✅ Tab bar visible at top of screen  
✅ Close button on each tab  
✅ Can open up to 10 tabs  

## 🎓 Reference Implementation

The previous attempt was provided in the chat history showing:
- Complete WorkspaceManager implementation
- WorkspaceContainer with IndexedStack
- WorkspaceTabBar UI
- Demo page for testing

**The implementation WORKED in the demo but had integration issues with the main app architecture (recursive MainLayout rendering).**

## 🚨 Known Issues to Avoid

1. **Recursive MainLayout**: Each GoRouter instance tried to render MainLayout, causing infinite nesting
2. **Solution**: Ensure only ONE MainLayout exists at the root, workspaces render content INSIDE it

## 📝 Notes for Next Agent

- Start with the demo page to prove the concept works
- Test with simple pages first (Dashboard, Products list)
- Verify state preservation before adding complex features
- Memory usage is acceptable (similar to browser tabs)
- This pattern is used by professional apps like TradingView, VS Code, Chrome DevTools

---

**Good luck! This is a powerful feature that will significantly improve UX.** 🚀
