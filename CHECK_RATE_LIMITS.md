# Supabase Rate Limit - 429 Too Many Requests

## What Happened
You're getting `429 (Too Many Requests)` when trying to sign up. This is Supabase's **authentication rate limiting** protection, not a database error.

## Default Supabase Rate Limits (Free Tier)
- **Email signups**: 30 requests per hour per IP
- **SMS/Phone**: 5 requests per hour per IP
- **Email/Password login**: 60 requests per hour per IP

## Solutions

### Option 1: Wait (Easiest)
Rate limits reset after **1 hour**. Just wait and try again.

### Option 2: Use Different Email
Try signing up with a completely different email address (not `ccatalan.us@gmail.com`).

Example:
- `test1@example.com`
- `vinabike.test@gmail.com`
- `demo.bikeshop@proton.me`

### Option 3: Increase Rate Limits (Recommended for Development)
1. Go to Supabase Dashboard: https://supabase.com/dashboard/project/xzdvtzdqjeyqxnkqprtf
2. Navigate to: **Authentication → Rate Limits**
3. Increase limits for development:
   - Email signups: **100 requests/hour** (up from 30)
   - Email logins: **150 requests/hour** (up from 60)
4. Click **Save**

### Option 4: Clear Rate Limit (Supabase Dashboard)
1. Go to: **Authentication → Users**
2. Find the IP address in rate limit logs
3. Clear the rate limit counter (if available)

### Option 5: Use Different IP/Network
- Use mobile hotspot
- Use VPN
- Use different device/browser

## Testing Best Practices

To avoid rate limits during development:

1. **Reuse test accounts** - Don't create new users repeatedly
2. **Delete old test users** before creating new ones
3. **Use email confirmations disabled** (for development only)
4. **Increase dev limits** in Supabase dashboard

## Verify Database is OK

The database deployment is likely **successful**! The 429 error is AFTER database connection, during auth signup.

To verify database is deployed correctly:
```sql
-- Run in Supabase SQL Editor
SELECT COUNT(*) FROM user_profiles; -- Should exist
SELECT COUNT(*) FROM reserved_subdomains; -- Should have 15 rows
SELECT policy_name FROM pg_policies WHERE tablename = 'user_profiles'; -- Should show RLS policies
```

## Next Steps

1. ✅ Wait 30-60 minutes
2. ✅ OR use different email: `test-vinabike@example.com`
3. ✅ Try signup again
4. ✅ Test that tenant creation works
