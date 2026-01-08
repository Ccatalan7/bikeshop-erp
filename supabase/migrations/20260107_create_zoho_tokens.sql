-- Migration: Create zoho_tokens table for storing Zoho OAuth refresh tokens
-- This table stores the refresh token per user for persistent Zoho Mail access

CREATE TABLE IF NOT EXISTS public.zoho_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    refresh_token TEXT NOT NULL,
    account_id TEXT, -- Zoho account ID for API calls
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id)
);

-- Enable RLS
ALTER TABLE public.zoho_tokens ENABLE ROW LEVEL SECURITY;

-- Users can only see/manage their own tokens
CREATE POLICY "Users can view own zoho tokens"
    ON public.zoho_tokens
    FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own zoho tokens"
    ON public.zoho_tokens
    FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own zoho tokens"
    ON public.zoho_tokens
    FOR UPDATE
    USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own zoho tokens"
    ON public.zoho_tokens
    FOR DELETE
    USING (auth.uid() = user_id);

-- Index for fast lookup
CREATE INDEX IF NOT EXISTS idx_zoho_tokens_user_id ON public.zoho_tokens(user_id);

-- Comment
COMMENT ON TABLE public.zoho_tokens IS 'Stores Zoho OAuth refresh tokens for mail integration';
