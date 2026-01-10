-- Email Push Subscriptions
-- Store push subscription state per user/provider for instant email notifications

CREATE TABLE IF NOT EXISTS email_push_subscriptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE NOT NULL,
  provider TEXT NOT NULL CHECK (provider IN ('gmail', 'zoho')),
  
  -- Gmail specific: historyId for incremental sync
  gmail_history_id TEXT,
  gmail_expiration TIMESTAMP WITH TIME ZONE,
  
  -- Zoho specific  
  zoho_webhook_id TEXT,
  
  -- Notification trigger: update this to trigger realtime to app
  new_mail_notification BOOLEAN DEFAULT false,
  notification_data JSONB,
  
  -- Status
  is_active BOOLEAN DEFAULT true,
  last_notification_at TIMESTAMP WITH TIME ZONE,
  error_message TEXT,
  
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  
  UNIQUE(user_id, provider)
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_email_push_user ON email_push_subscriptions(user_id);
CREATE INDEX IF NOT EXISTS idx_email_push_provider ON email_push_subscriptions(provider);

-- RLS
ALTER TABLE email_push_subscriptions ENABLE ROW LEVEL SECURITY;

-- Users can only see their own subscriptions
CREATE POLICY "users_view_own_push_subscriptions" ON email_push_subscriptions
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "users_manage_own_push_subscriptions" ON email_push_subscriptions
  FOR ALL USING (auth.uid() = user_id);

-- Enable realtime for push notifications to app
ALTER PUBLICATION supabase_realtime ADD TABLE email_push_subscriptions;

-- Function to trigger notification (called by Edge Function)
CREATE OR REPLACE FUNCTION notify_new_email(
  p_user_id UUID,
  p_provider TEXT,
  p_history_id TEXT DEFAULT NULL,
  p_notification_data JSONB DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Update the subscription to trigger realtime notification
  UPDATE email_push_subscriptions
  SET 
    new_mail_notification = true,
    notification_data = p_notification_data,
    gmail_history_id = COALESCE(p_history_id, gmail_history_id),
    last_notification_at = now(),
    updated_at = now()
  WHERE user_id = p_user_id AND provider = p_provider;
  
  -- If no subscription exists, create one
  IF NOT FOUND THEN
    INSERT INTO email_push_subscriptions (user_id, tenant_id, provider, gmail_history_id, new_mail_notification, notification_data, last_notification_at)
    SELECT 
      p_user_id,
      up.tenant_id,
      p_provider,
      p_history_id,
      true,
      p_notification_data,
      now()
    FROM user_profiles up
    WHERE up.user_id = p_user_id
    LIMIT 1;
  END IF;
END;
$$;

-- Grant execute to service role (for Edge Functions)
GRANT EXECUTE ON FUNCTION notify_new_email(UUID, TEXT, TEXT, JSONB) TO service_role;
