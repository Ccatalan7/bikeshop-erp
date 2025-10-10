# GPT-5 Codes Prompt – Accounting System & Chart of Accounts Redesign

The goal of this task is to **redesign the entire accounting system and Chart of Accounts** of the Flutter-based application, ensuring it follows **professional accounting standards**, integrates seamlessly with all other modules, and provides a clean, global structure that supports long-term scalability and clarity.

---

## Main Instruction
Redesign the **accounting system and the Chart of Accounts** from the ground up, ensuring that it:
- Adheres to double-entry bookkeeping principles.
- Includes all traditional, essential accounts used in top-tier accounting software.
- Remains modular, logical, and universally adaptable across all operations (sales, inventory, client management, etc.).
- Generates automated accounting entries for every transaction in the system.
- Maintains perfect synchronization between financial, operational, and stock data.

The new Chart of Accounts should reflect a **clear, traditional accounting hierarchy**, while allowing flexibility for categories related to the business domain (e.g., products, repairs, services).  
It should be hardcoded, globally accessible, and optimized for consistent performance and maintainability.

---

## Context and Supporting Considerations

### Database and Architecture
The current system uses **Firebase** for authentication and data storage.  
As part of the redesign, consider whether **Firebase** remains suitable for accounting or if migrating to a more robust relational solution (e.g., **LightSQL** or **ProgressSQL**) would provide better long-term integrity, transaction control, and scalability.

### User Interface (UI/UX)
The application’s interface must remain **modern, lightweight, and in-page navigable**, avoiding new windows or tabs.  
Navigation should flow seamlessly through **route-based controls** (e.g., navigation arrows) and maintain a cohesive aesthetic consistent with the rest of the system.

### Global Data and Connectivity
All accounting-related data must be **hardcoded and global**, ensuring that:
- All modules (Inventory, Sales, Purchases, Client Management) are directly connected to the accounting core.
- Financial data remains consistent, transparent, and accessible system-wide.
- Updates to any business area automatically reflect in the accounting records.

---

## Deliverable
A fully reimagined **Accounting Module and Chart of Accounts**, designed with global data integration, standard accounting principles, and long-term database scalability in mind.  
The result should be a **professional, unified, and intelligent accounting foundation** for the entire system.
