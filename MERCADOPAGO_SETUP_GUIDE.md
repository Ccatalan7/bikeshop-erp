# 💳 MercadoPago Integration - Setup & Testing Guide

## ✅ What's Been Configured

### 1. Database Setup
- ✅ Added `mercadopago` payment method to `payment_methods` table
- ✅ Maps to account `1110` (Banco) for accounting entries
- ✅ Configured with `requires_reference = true` to store transaction IDs
- ✅ Updated `process_online_order()` function to:
  - Create sales invoice from online order
  - Automatically create payment record when `payment_status = 'paid'`
  - Link payment to MercadoPago using `payment_reference` field
  - Trigger accounting journal entries (Dr: Bank, Cr: Accounts Receivable)

### 2. Flutter Integration
- ✅ Created `MercadoPagoService` in `/lib/modules/website/services/mercadopago_service.dart`
- ✅ Updated checkout page to include MercadoPago as payment option
- ✅ Registered service in `main.dart` providers
- ✅ Configured to redirect customers to MercadoPago checkout

### 3. Payment Flow
```
Customer Checkout → Order Created (pending) → MercadoPago Redirect
                                                      ↓
                                                   Payment
                                                      ↓
                  Webhook/Callback ← MercadoPago Confirmation
                         ↓
              Update order.payment_status = 'paid'
                         ↓
              Call process_online_order(order_id)
                         ↓
       ┌─────────────────┴──────────────────┐
       ↓                                    ↓
Create Sales Invoice              Create Payment Record
(status: 'pagado')               (with MercadoPago reference)
       ↓                                    ↓
Reduce Inventory                  Create Journal Entry
                                 Dr: 1110 Banco
                                 Cr: 1201 Cuentas por Cobrar
```

---

## 🚧 What Still Needs to Be Done

### 1. Get MercadoPago Credentials

1. **Sign up for MercadoPago Developer Account:**
   - Go to https://www.mercadopago.cl/developers
   - Create account (or use existing business account)
   - Navigate to "Tus aplicaciones" → "Crear aplicación"

2. **Get Test Credentials:**
   - Public Key: `TEST-xxxxx...`
   - Access Token: `TEST-xxxxx...`
   - **DO NOT** use production credentials until fully tested!

3. **Save credentials in database:**
   ```sql
   INSERT INTO website_settings (key, value)
   VALUES 
     ('mercadopago_public_key', 'TEST-your-public-key'),
     ('mercadopago_access_token', 'TEST-your-access-token'),
     ('mercadopago_test_mode', 'true')
   ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
   ```

### 2. Create Supabase Edge Functions

You need to create 2 Edge Functions to keep credentials secure:

#### A. `mercadopago-create-preference`

**Path:** `supabase/functions/mercadopago-create-preference/index.ts`

```typescript
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    // Get MercadoPago credentials from database
    const { data: settings } = await supabase
      .from('website_settings')
      .select('key, value')
      .in('key', ['mercadopago_access_token', 'mercadopago_test_mode'])

    const accessToken = settings?.find(s => s.key === 'mercadopago_access_token')?.value
    const isTestMode = settings?.find(s => s.key === 'mercadopago_test_mode')?.value === 'true'

    if (!accessToken) {
      throw new Error('MercadoPago not configured')
    }

    // Parse request body
    const { order_id, order_number, total, items, payer, back_urls, notification_url } = await req.json()

    // Create preference in MercadoPago
    const mpResponse = await fetch('https://api.mercadopago.com/checkout/preferences', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${accessToken}`,
      },
      body: JSON.stringify({
        items: items.map((item: any) => ({
          title: item.title,
          quantity: item.quantity,
          unit_price: item.unit_price,
          currency_id: 'CLP',
        })),
        payer: {
          email: payer.email,
          name: payer.name,
        },
        back_urls: back_urls,
        auto_return: 'approved',
        notification_url: notification_url,
        external_reference: order_id,
        statement_descriptor: `Pedido ${order_number}`,
      }),
    })

    const preference = await mpResponse.json()

    if (!mpResponse.ok) {
      throw new Error(`MercadoPago error: ${JSON.stringify(preference)}`)
    }

    return new Response(
      JSON.stringify(preference),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (error) {
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
```

#### B. `mercadopago-webhook`

**Path:** `supabase/functions/mercadopago-webhook/index.ts`

```typescript
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

serve(async (req) => {
  try {
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    const { type, data } = await req.json()

    // Only process payment notifications
    if (type !== 'payment') {
      return new Response('ok', { status: 200 })
    }

    const paymentId = data.id

    // Get MercadoPago access token
    const { data: settings } = await supabase
      .from('website_settings')
      .select('value')
      .eq('key', 'mercadopago_access_token')
      .single()

    const accessToken = settings?.value

    // Fetch payment details from MercadoPago
    const mpResponse = await fetch(`https://api.mercadopago.com/v1/payments/${paymentId}`, {
      headers: {
        'Authorization': `Bearer ${accessToken}`,
      },
    })

    const payment = await mpResponse.json()

    // Update order based on payment status
    const orderId = payment.external_reference
    const status = payment.status // approved, pending, rejected, etc.

    let paymentStatus = 'pending'
    if (status === 'approved') {
      paymentStatus = 'paid'
    } else if (status === 'rejected' || status === 'cancelled') {
      paymentStatus = 'failed'
    }

    // Update online order
    await supabase
      .from('online_orders')
      .update({
        payment_status: paymentStatus,
        payment_method: 'mercadopago',
        payment_reference: paymentId.toString(),
        paid_at: status === 'approved' ? new Date().toISOString() : null,
      })
      .eq('id', orderId)

    // If approved, process the order (create invoice + payment)
    if (status === 'approved') {
      await supabase.rpc('process_online_order', { p_order_id: orderId })
    }

    return new Response('ok', { status: 200 })
  } catch (error) {
    console.error('Webhook error:', error)
    return new Response('error', { status: 500 })
  }
})
```

**Deploy Edge Functions:**
```bash
# From project root
supabase functions deploy mercadopago-create-preference
supabase functions deploy mercadopago-webhook
```

### 3. Update MercadoPagoService URLs

In `lib/modules/website/services/mercadopago_service.dart`, update:

```dart
String _getCallbackUrl(String status) {
  // Replace with your actual domain
  const baseUrl = 'https://your-actual-website.com';
  return '$baseUrl/tienda/pedido-callback?status=$status';
}

String _getWebhookUrl() {
  // Use your Supabase project URL
  return 'https://your-project-id.supabase.co/functions/v1/mercadopago-webhook';
}
```

### 4. Create Payment Callback Page (Optional)

If you want a dedicated callback page instead of going straight to order confirmation:

```dart
// lib/public_store/pages/payment_callback_page.dart
class PaymentCallbackPage extends StatefulWidget {
  final String? status;
  final String? paymentId;
  final String? orderId;

  const PaymentCallbackPage({
    super.key,
    this.status,
    this.paymentId,
    this.orderId,
  });

  @override
  State<PaymentCallbackPage> createState() => _PaymentCallbackPageState();
}

class _PaymentCallbackPageState extends State<PaymentCallbackPage> {
  @override
  void initState() {
    super.initState();
    _processCallback();
  }

  Future<void> _processCallback() async {
    if (widget.status == null || widget.orderId == null) {
      return;
    }

    final mercadopago = context.read<MercadoPagoService>();

    await mercadopago.processPaymentCallback(
      orderId: widget.orderId!,
      paymentId: widget.paymentId ?? '',
      status: widget.status!,
    );

    // Redirect to order confirmation
    if (mounted) {
      context.go('/tienda/pedido/${widget.orderId}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}
```

---

## 🧪 Testing Flow

### Test with MercadoPago Test Cards

**Approved Payment:**
- Card: `4509 9535 6623 3704`
- CVV: Any 3 digits
- Expiry: Any future date

**Rejected Payment:**
- Card: `4024 0071 5436 6608`
- CVV: Any 3 digits

### Testing Steps

1. **Deploy updated schema:**
   ```bash
   # Deploy core_schema.sql to Supabase
   psql -h db.your-project.supabase.co -U postgres -d postgres -f supabase/sql/core_schema.sql
   ```

2. **Add test credentials to database** (see SQL above)

3. **Run the app:**
   ```bash
   flutter run -d chrome --web-port 8080
   ```

4. **Navigate to public store:**
   - Go to http://localhost:8080/tienda
   - Add products to cart
   - Click "Finalizar Compra"

5. **Complete checkout:**
   - Fill in customer information
   - Select "MercadoPago" as payment method
   - Click "REALIZAR PEDIDO"

6. **MercadoPago checkout:**
   - You'll be redirected to MercadoPago sandbox
   - Use test card (see above)
   - Complete payment

7. **Verify in ERP:**
   - Check `Ventas → Pedidos Online` (order should show payment_status = 'paid')
   - Check `Ventas → Facturas` (invoice should be created with status 'pagado')
   - Check `Ventas → Pagos` (payment record should exist)
   - Check `Contabilidad → Diario` (journal entry should show Dr: Banco, Cr: CxC)

---

## 📊 What to Verify After Test Purchase

### 1. Online Orders Table
```sql
SELECT 
  order_number,
  customer_name,
  total,
  status,
  payment_status,
  payment_method,
  payment_reference,
  sales_invoice_id
FROM online_orders
WHERE payment_status = 'paid'
ORDER BY created_at DESC
LIMIT 5;
```

### 2. Sales Invoices Created
```sql
SELECT 
  invoice_number,
  customer_name,
  total,
  status,
  paid_amount,
  balance,
  reference
FROM sales_invoices
WHERE reference LIKE 'Pedido online%'
ORDER BY date DESC
LIMIT 5;
```

### 3. Payment Records
```sql
SELECT 
  sp.id,
  si.invoice_number,
  pm.name as payment_method,
  sp.amount,
  sp.reference as mercadopago_reference,
  sp.payment_date
FROM sales_payments sp
JOIN sales_invoices si ON si.id = sp.invoice_id
JOIN payment_methods pm ON pm.id = sp.payment_method_id
WHERE pm.code = 'mercadopago'
ORDER BY sp.payment_date DESC
LIMIT 5;
```

### 4. Accounting Entries
```sql
SELECT 
  je.id,
  je.reference,
  a.code,
  a.name as account_name,
  jel.debit,
  jel.credit,
  jel.description
FROM journal_entry_lines jel
JOIN journal_entries je ON je.id = jel.entry_id
JOIN accounts a ON a.id = jel.account_id
WHERE je.reference LIKE 'Pago%Pedido online%'
ORDER BY je.date DESC, jel.id
LIMIT 10;
```

**Expected Accounting Entry:**
```
Dr: 1110 Banco               CLP 119,000  (payment amount)
Cr: 1201 Cuentas por Cobrar              CLP 119,000
```

### 5. Inventory Reduction
```sql
SELECT 
  sm.product_id,
  p.name,
  sm.quantity,
  sm.type,
  sm.reference
FROM stock_movements sm
JOIN products p ON p.id = sm.product_id
WHERE sm.reference LIKE 'Factura%INV-%'
ORDER BY sm.created_at DESC
LIMIT 10;
```

---

## 🔐 Security Checklist

- ✅ Never expose Access Token in Flutter code (only in Edge Functions)
- ✅ Always validate webhook signatures in production
- ✅ Use HTTPS for all callbacks and webhooks
- ✅ Store credentials in database, not in code
- ✅ Test mode enabled until fully verified
- ⚠️ Enable RLS policies on `website_settings` table:
  ```sql
  -- Only authenticated users (ERP admins) can view/edit settings
  CREATE POLICY "Admin only access"
    ON website_settings
    FOR ALL
    USING (auth.role() = 'authenticated');
  ```

---

## 🎉 Success Criteria

After a successful test purchase, you should have:

1. ✅ Online order with `payment_status = 'paid'`
2. ✅ Sales invoice created with `status = 'pagado'`
3. ✅ Payment record with MercadoPago reference
4. ✅ Accounting entry: Dr: Banco, Cr: Cuentas por Cobrar
5. ✅ Inventory reduced for purchased products
6. ✅ Customer receives order confirmation email (if configured)

---

## 📞 Next Steps

1. Get MercadoPago test credentials
2. Create and deploy Edge Functions
3. Run a test purchase
4. Verify all database records and accounting entries
5. If all checks pass, request production credentials
6. Update to production mode and deploy to live website

**Deploy database changes NOW:**
```bash
psql -h db.your-project.supabase.co -U postgres -d postgres -f supabase/sql/core_schema.sql
```

Then follow the steps above to complete MercadoPago integration! 🚀
