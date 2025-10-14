# Custom Company Logo Feature - Implementation Summary

## Overview
Implemented a feature to upload and display a custom company logo in the application header, replacing the default icon and company name with a personalized logo image.

## Changes Made

### 1. AppearanceService (`lib/modules/settings/services/appearance_service.dart`)
- **Added logo management functionality:**
  - `_companyLogoKey`: SharedPreferences key for storing logo URL
  - `_companyLogoUrl`: Stores the current logo URL
  - `hasCustomLogo`: Getter to check if a custom logo is set
  - `uploadCompanyLogo(File)`: Uploads logo to Supabase Storage
  - `removeCompanyLogo()`: Removes the custom logo
  - Loads logo URL from SharedPreferences on initialization

### 2. AppearanceSettingsPage (`lib/modules/settings/pages/appearance_settings_page.dart`)
- **Replaced icon selector with logo uploader:**
  - Logo preview section showing current logo or placeholder
  - "Subir Logo" / "Cambiar Logo" button with image picker
  - "Eliminar Logo" button with confirmation dialog
  - Loading indicator during upload
  - Success/error notifications
  - Uses `ImageService.pickImage()` for file selection
  - Supports all image formats (jpg, png, gif, webp, etc.)

### 3. Settings Page (`lib/modules/settings/pages/settings_page.dart`)
- **Updated Apariencia section:**
  - Changed menu item from "Icono de Inicio" to "Logo de la Empresa"
  - Updated subtitle to "Subir logo personalizado para el encabezado"

### 4. MainLayout (`lib/shared/widgets/main_layout.dart`)
- **Updated both Sidebar and Drawer headers:**
  - **Desktop Sidebar (AppSidebar):**
    - Shows custom logo when available (full width, contained fit)
    - Falls back to default icon + "Vinabike" + "ERP Sistema" when no logo
    - Entire header is clickable and navigates to dashboard
    - Helper methods: `_buildDefaultHeaderWidgets()`, `_buildDefaultHeader()`
  
  - **Mobile Drawer (AppDrawer):**
    - Shows custom logo when available (full width, contained fit)
    - Falls back to default icon + text when no logo
    - Entire header is clickable, closes drawer, and navigates to dashboard
    - Helper method: `_buildDefaultDrawerHeader()`

### 5. Main App (`lib/main.dart`)
- Added `AppearanceService` to the provider tree for global state management

### 6. Router (`lib/shared/routes/app_router.dart`)
- Added route `/settings/appearance` for the appearance settings page

## Features

### Logo Upload
1. User navigates to **Configuración → Apariencia → Logo de la Empresa**
2. Clicks "Subir Logo" button
3. Selects an image file from their device
4. Image is uploaded to Supabase Storage under `company_logos/` folder
5. URL is saved to SharedPreferences
6. Logo appears immediately in all headers (sidebar and drawer)

### Logo Display
- **With Custom Logo:**
  - Logo fills the entire header space (respecting aspect ratio)
  - White background for better visibility
  - Clickable area navigates to dashboard
  - Uses CachedNetworkImage for performance

- **Without Custom Logo (Default):**
  - Shows icon (customizable, defaults to bike icon)
  - Shows "Vinabike" text
  - Shows "ERP Sistema" subtitle
  - All still clickable to navigate home

### Logo Removal
1. Click "Eliminar Logo" button
2. Confirm in dialog
3. Logo removed from storage preference
4. Header reverts to default display

## Technical Implementation

### Storage
- **Supabase Storage:** Images uploaded to default bucket, `company_logos/` folder
- **SharedPreferences:** Logo URL cached locally for fast access
- **Service Pattern:** AppearanceService manages all appearance-related settings

### UI/UX
- Responsive design works on both desktop and mobile
- Loading states during upload
- Error handling with user-friendly messages
- Confirmation dialogs for destructive actions
- Image format validation handled by ImageService
- Fallback to default header on image load errors

### Performance
- Uses `CachedNetworkImage` for efficient image loading
- Logo URL cached in memory and SharedPreferences
- No unnecessary reloads or API calls

## User Journey

1. **Access Settings:** Dashboard → Settings (gear icon) → Apariencia
2. **Upload Logo:** Click "Subir Logo" → Select image → Wait for upload → Success!
3. **View Logo:** Logo appears in sidebar/drawer header immediately
4. **Navigate Home:** Click logo to go to dashboard
5. **Change Logo:** Repeat upload process with new image
6. **Remove Logo:** Click "Eliminar Logo" → Confirm → Reverts to default

## Benefits

- **Branding:** Customize the app with company logo
- **Professional:** More personalized appearance
- **User-Friendly:** Simple upload process with clear feedback
- **Flexible:** Can switch back to default anytime
- **Consistent:** Logo appears across all screens (sidebar and drawer)
- **Interactive:** Logo is clickable for quick navigation to home

## File Structure
```
lib/
├── modules/
│   └── settings/
│       ├── services/
│       │   └── appearance_service.dart (✅ Updated - logo management)
│       └── pages/
│           ├── appearance_settings_page.dart (✅ Updated - logo uploader UI)
│           └── settings_page.dart (✅ Updated - menu entry)
├── shared/
│   ├── routes/
│   │   └── app_router.dart (✅ Updated - added route)
│   └── widgets/
│       └── main_layout.dart (✅ Updated - logo display)
└── main.dart (✅ Updated - added provider)
```

## Next Steps (Optional Enhancements)
- Add logo size/dimension requirements display
- Add image cropping tool for better logo fitting
- Support multiple logo variants (light/dark mode)
- Add logo preview before upload
- Export settings to backup/restore logo
