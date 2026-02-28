-- migration: 20260228000001_add_smart_tasks_attachments.sql
-- description: Adds a JSONB attachments column to smart_tasks for file/image uploads.

ALTER TABLE public.smart_tasks 
ADD COLUMN IF NOT EXISTS attachments JSONB DEFAULT '[]'::jsonb;

-- Each attachment entry looks like:
-- {
--   "name": "photo.jpg",
--   "url": "https://...",
--   "type": "image/jpeg",
--   "size": 123456,
--   "uploaded_at": "2026-02-28T..."
-- }
