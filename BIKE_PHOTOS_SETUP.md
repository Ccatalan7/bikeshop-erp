# 🚴 Bike Photos Feature - Setup Guide

## ✅ What Was Added

### 1. **Image Upload to Bike Form**
- **File:** `lib/modules/bikeshop/pages/bike_form_dialog.dart`
- **Features:**
  - ✅ Image picker button to select photos from gallery
  - ✅ Image preview grid showing existing and new photos
  - ✅ Support for multiple photos per bike
  - ✅ Delete/remove photos before saving
  - ✅ Upload progress indicator
  - ✅ Automatic image compression (max 1920x1080, 85% quality)
  - ✅ Images uploaded to Supabase Storage
  - ✅ URLs stored in database `bikes.image_urls` array

### 2. **Database Schema**
- **Table:** `bikes`
- **Column:** `image_urls text[] DEFAULT '{}'`
- **Status:** ✅ Already exists in `core_schema.sql`

### 3. **Service Integration**
- **ImageService:** Already exists in `lib/shared/services/image_service.dart`
- **Provider:** ✅ Added to `main.dart` providers
- **Upload Method:** Uses `ImageService.uploadBytes()` for cross-platform compatibility

---

## 🔧 Required: Supabase Storage Bucket Setup

**⚠️ IMPORTANT:** You must create a Supabase storage bucket before uploading photos.

### Steps:

1. **Go to Supabase Dashboard:**
   - Navigate to: https://supabase.com/dashboard
   - Select your project
   - Go to **Storage** section

2. **Create New Bucket:**
   - Click **"New bucket"**
   - **Bucket name:** `bike-images`
   - **Public bucket:** ✅ Enable (so images can be displayed)
   - Click **"Create bucket"**

3. **Configure Bucket Policies:**
   - Click on `bike-images` bucket
   - Go to **"Policies"** tab
   - Click **"New Policy"**
   
   **Policy 1: Allow authenticated users to upload**
   ```sql
   CREATE POLICY "Allow authenticated users to upload bike images"
   ON storage.objects FOR INSERT
   TO authenticated
   WITH CHECK (bucket_id = 'bike-images');
   ```
   
   **Policy 2: Allow public read access**
   ```sql
   CREATE POLICY "Allow public read access to bike images"
   ON storage.objects FOR SELECT
   TO public
   USING (bucket_id = 'bike-images');
   ```
   
   **Policy 3: Allow authenticated users to delete their own images**
   ```sql
   CREATE POLICY "Allow authenticated users to delete bike images"
   ON storage.objects FOR DELETE
   TO authenticated
   USING (bucket_id = 'bike-images');
   ```

4. **Verify Setup:**
   - Go to bucket settings
   - Confirm **"Public access"** is enabled
   - Test upload from app

---

## 🎯 How to Use

### Adding Photos to a New Bike:

1. Navigate to **Clientes** module
2. Click on a customer to view their logbook
3. Click **"Agregar Bicicleta"** button
4. Fill in bike details (brand, model, year, etc.)
5. Click **"Agregar Foto"** button
6. Select one or more photos from your computer
7. Preview images in the grid
8. Remove unwanted images by clicking the ❌ icon
9. Click **"Guardar"** - images will upload automatically
10. Success! Photos are now stored and displayed

### Editing Photos on Existing Bike:

1. Open customer logbook
2. Click **Edit** icon on bike card
3. Existing photos display in the grid
4. Add new photos with **"Agregar Foto"**
5. Remove unwanted photos with ❌ icon
6. Click **"Guardar"** to update

---

## 📸 Image Specifications

- **Supported Formats:** JPEG, PNG, GIF, WebP
- **Max Resolution:** 1920x1080 pixels (auto-compressed)
- **Image Quality:** 85% (optimized for web/mobile)
- **Max File Size:** No hard limit, but compression reduces size
- **Multiple Images:** ✅ Unlimited per bike
- **Storage Location:** Supabase Storage bucket `bike-images`
- **File Naming:** `bike_{customerId}_{timestamp}.jpg`

---

## 🗂️ File Structure

```
lib/modules/bikeshop/pages/
  ├── bike_form_dialog.dart         ← Updated with image picker
  └── client_logbook_page.dart      ← Displays bikes with images

lib/shared/services/
  ├── image_service.dart             ← Handles upload/download
  ├── image_service_mobile.dart      ← Mobile implementation
  └── image_service_web.dart         ← Web implementation

supabase/sql/
  └── core_schema.sql                ← bikes.image_urls column

Supabase Storage:
  └── bike-images/                   ← Bucket (must create manually)
      └── {customerId}/
          ├── bike_{customerId}_{timestamp1}.jpg
          ├── bike_{customerId}_{timestamp2}.jpg
          └── ...
```

---

## 🔍 Troubleshooting

### Problem: "Storage bucket not found" error

**Solution:**
1. Go to Supabase Dashboard → Storage
2. Create bucket named `bike-images` (exact name)
3. Enable **Public access**
4. Add storage policies (see above)

---

### Problem: Images not displaying

**Solution:**
1. Check bucket is **public**
2. Verify policies are created correctly
3. Check browser console for CORS errors
4. Ensure image URLs are valid (test in browser)

---

### Problem: Upload fails silently

**Solution:**
1. Check Supabase Storage quota (free tier limit)
2. Verify authenticated user has upload permission
3. Check network connection
4. Look for errors in console: `debugPrint('Error uploading image: $e')`

---

### Problem: Images too large / slow upload

**Solution:**
- Images are automatically compressed to 1920x1080 @ 85% quality
- If still too large, reduce `maxWidth`/`maxHeight` in `_pickImage()` method
- Consider implementing client-side image optimization

---

## 🚀 Next Steps

### Optional Enhancements:

1. **Multi-select images:**
   - Update `pickImage()` to select multiple at once
   - Currently: one at a time

2. **Drag & drop (web):**
   - Add drag-drop zone for web platform
   - Better UX for desktop users

3. **Camera capture (mobile):**
   - Add option to take photo with camera
   - Update `ImageSource.gallery` to `ImageSource.camera`

4. **Image cropping:**
   - Add `image_cropper` package
   - Let users crop before upload

5. **Image gallery viewer:**
   - Add fullscreen image viewer
   - Swipe between multiple images

6. **Delete old images from storage:**
   - When removing image from bike, delete from Supabase Storage
   - Currently: only removes URL from database

---

## 📋 Testing Checklist

- [ ] Create Supabase storage bucket `bike-images`
- [ ] Enable public access on bucket
- [ ] Add storage policies (upload, read, delete)
- [ ] Create new bike and add 1 photo → verify saved
- [ ] Add multiple photos (3+) → verify all saved
- [ ] Edit bike and remove photo → verify URL removed from database
- [ ] Edit bike and add more photos → verify merged with existing
- [ ] View bike card in logbook → verify images display correctly
- [ ] Test on Windows desktop → verify file picker works
- [ ] (Optional) Test on Android → verify gallery picker works
- [ ] (Optional) Test on Web → verify web file picker works

---

## ✅ Deployment

After testing locally and confirming everything works:

```bash
# Rebuild release .exe with photo upload feature
flutter build windows --release

# The updated .exe is at:
# build/windows/x64/runner/Release/vinabike_erp.exe
```

**That's it!** The bike photo feature is now fully integrated into your ERP system. 🎉
