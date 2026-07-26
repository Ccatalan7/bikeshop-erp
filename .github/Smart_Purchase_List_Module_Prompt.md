# 🚀 Copilot Agent Task --- Smart Purchase List Module (ERP for Bike Shops)

> [!WARNING]
> **Historical business context; not UI authority.** This prompt may retain
> useful purchase-planning behavior, but every visual, layout, navigation,
> component, color, spacing, metric-card, modal/dialog/snackbar, responsive,
> and platform recipe is superseded by
> [`GUI_DESIGN_PRINCIPLES.md`](GUI_DESIGN_PRINCIPLES.md) and
> [`GUI_MOBILE_DESIGN_PRINCIPLES.md`](GUI_MOBILE_DESIGN_PRINCIPLES.md). Do not
> copy a competitor, screenshot, or old component. Choose inline, in-block,
> pane, popover, sheet, blocking surface, or full route from the actual task;
> none is an automatic module-wide pattern.

## 🧠 General Goal

We want to develop a **Smart Purchase List Module**, an intelligent
system that automatically builds and manages purchase needs in real
time.\
The module should be **context-aware, data-driven, and practical for a
workshop environment**
--- especially for our mountain bike repair and parts shop.

The goal is to **automatically generate and manage a centralized
purchase list** where products are combined intelligently, categorized
by supplier, and enriched with real-time KPIs that guide purchasing
decisions.

------------------------------------------------------------------------

## ⚙️ Technical Environment

-   **IDE:** Visual Studio Code\
-   **Language:** Dart\
-   **Framework:** Flutter\
-   **Auth & Database:** Supabase\
-   **App type:** ERP system for Bike Shops (Accounting core)\
-   **Navigation:** Preserve the current purchase-list context across related
    work. Select the lightest justified interaction surface under the canonical
    navigation rules rather than prescribing one route shape.

All data must be **hardcoded and globally available** for prototype
mode.\
The agent must **reuse the existing backend logic and data structures**
--- **never create or modify tables unless it's strictly necessary**.\
Work primarily at the **logic, query, and UI level**, extending only
where required for the module to function properly.

------------------------------------------------------------------------

## 🧩 Core Functionality Description

### 🧠 Smart Purchase List Logic

-   Whenever a product's quantity reaches or falls below its defined
    minimum/alert level, it should be **automatically added to the
    Purchase List**.
-   Each entry (row) represents a product awaiting purchase.
-   The table supports **manual additions**, including:
    -   Non-registered items (ad-hoc inputs)
    -   Temporary items that don't belong to the official catalog

### 🔍 Smart Columns (Conceptual, Not Database Schema)

  -----------------------------------------------------------------------
  Field                       Description
  --------------------------- -------------------------------------------
  Added date                  Day when the product was added (usually
                              when it reached low stock)

  Product                     Product name (auto-fetched from existing
                              data, or manually entered)

  Supplier                    Related supplier (existing link)

  Suggested qty               Estimated restock quantity based on
                              rotation and consumption

  Rotation KPI                Smart indicator of how fast the item moves

  Priority                    Calculated dynamically based on rotation,
                              lead time, and urgency

  Status                      (Pending / Ordered / Received / Ignored)

  Linked document             Automatically references purchase or
                              expense document once created

  Added by                    User who added the item manually (if
                              applicable)
  -----------------------------------------------------------------------

> **Formula idea for Priority (in logic, not database):**\
> `priority = (rotation * 0.6) + (supplier_reliability * 0.3) + (days_since_last_purchase * 0.1)`

------------------------------------------------------------------------

## 🧠 Smart Features & Automations

1.  **Auto-Add Products**
    -   Triggered when product quantity ≤ alert level.
    -   Add automatically with default data and pending status.
2.  **Supplier Grouping**
    -   Dropdown to select "Generate purchase order by supplier".
    -   When a supplier is selected:
        -   All pending items linked to that supplier are grouped.
        -   The app opens the canonical purchase-document creation flow with
            those items preloaded and supplier preselected, while preserving
            the originating purchase-list context for return.
3.  **Smart Removal**
    -   When a related purchase or expense document is marked as
        completed/paid/received, the item is automatically removed or
        marked as resolved in the list.
4.  **Manual Additions**
    -   Allow manual rows.
    -   The "Product" field supports smart search or text entry.
    -   Ad-hoc items remain valid and can be added to any purchase or
        expense document.
5.  **Expense Linking**
    -   Some items will never go through purchase orders (e.g.,
        consumables, tools, cleaning products).
    -   Add an option to send items directly to an expense document
        instead of a purchase order.
6.  **Manual Controls**
    -   Select items manually via checkbox.
    -   Add selected items to a new or existing purchase document.
    -   Option to bulk add all items from the same supplier.
7.  **Decision Summary**
    -   Show a compact summary only when these values change the purchasing
        decision:
        -   Total pending items
        -   Most urgent items (by priority)
        -   Supplier with most pending products
        -   Average purchase completion time
8.  **Filters & Sorting**
    -   Filter by supplier, priority, category, or status.
    -   Sort by priority, added date, or rotation speed.
9.  **UI/UX**
    -   Follow both canonical GUI guides and produce a modern, professional,
        visually considered operational surface.
    -   Communicate priority through text and semantics plus a measured
        theme-owned treatment; never through a literal hue scale or color
        alone.
    -   Use purposeful motion and contextual editing only where they improve
        continuity; neither is a compulsory pattern.

------------------------------------------------------------------------

## 🔗 Integration Guidelines

-   Do **not create or modify existing tables unless it's strictly
    necessary**.\
-   Use the already available data models for:
    -   Products and suppliers\
    -   Stock levels\
    -   Purchase or expense documents\
    -   User metadata (for "added by" info)
-   Extend functionality **only when unavoidable** --- otherwise, build
    logic at the service or UI layer.\
-   Use existing joins, computed properties, or backend functions where
    possible.\
-   Implement smart logic in Dart, working with the live Supabase data
    streams.

------------------------------------------------------------------------

## 💡 Improvements Copilot Can Add Freely

-   Smart restock quantity based on historical sales (average
    consumption over time).\
-   Supplier reliability score to refine priority calculation.\
-   "Next Purchase Suggestion" widget that predicts which items will hit
    low stock soon.\
-   "Mark as Acquired Externally" option for items bought outside the
    system.\
-   Automatic alerts for critical shortages.

------------------------------------------------------------------------

## 🧱 Expected Deliverables

-   Flutter/Dart UI for the Smart Purchase List screen.\
-   Business logic layer handling auto-addition, priority scoring, and
    document linking.\
-   Navigation integration:
    -   Purchase list → Purchase document form\
    -   Purchase list → Expense document form\
-   Clean modular structure (providers, states, or blocs as needed).\
-   Hardcoded sample data for demo mode.\
-   **No database creation/modification unless strictly necessary**.

------------------------------------------------------------------------

## ✅ General Guidelines

-   Do not create or alter existing database entities **unless it's
    strictly necessary** for module integration.\
-   Focus on reusing existing structures and connecting logic
    elegantly.\
-   Keep UI consistent with ERP visual style --- professional,
    functional, modern.\
-   Build this as a **next-gen intelligent purchase planner** focused on
    automation, usability, and workshop efficiency.\
-   Think dynamically --- add improvements, but never clutter or
    duplicate logic.

------------------------------------------------------------------------

**Main Objective for Copilot Agent:**\
\> Develop the **Smart Purchase List Module**, fully integrated into the
existing ERP structure, using only current models and data flows.
Implement all logic, UI, and automations described above, improving
where useful --- but only create or modify structures if strictly
necessary for functionality.
