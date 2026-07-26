# 📱 Customer Mobile App - Complete Implementation Plan

> [!WARNING]
> **Historical product context; not UI authority.** Feature intent may remain
> useful, but every wireframe, visual, navigation, component, color, spacing,
> card/badge, modal/dialog/snackbar, responsive, and platform recipe below is
> superseded by [`GUI_DESIGN_PRINCIPLES.md`](GUI_DESIGN_PRINCIPLES.md) and
> [`GUI_MOBILE_DESIGN_PRINCIPLES.md`](GUI_MOBILE_DESIGN_PRINCIPLES.md). Do not
> copy the historical mockups or palette. Inspect current iOS and Android hosts
> and choose inline, in-block, pane, popover, sheet, blocking surface, or full
> route from task evidence; none is an automatic app-wide pattern.

**Date**: November 8, 2025  
**Project**: Viña Bike ERP - Customer Companion App  
**Purpose**: Replace WhatsApp for customer communication with professional mobile app

---

## 🎯 App Overview

**Name**: Viña Bike (Customer App)  
**Platforms**: iOS & Android  
**Tech Stack**: Flutter (shared codebase with ERP)  
**Backend**: Supabase (same database, multi-tenant ready)  
**Push Notifications**: Firebase Cloud Messaging (FCM)  
**Authentication**: Supabase Auth (phone/email with OTP)

---

## 📊 Core Features

### 1. Customer Portal
- View service history (all mechanic jobs)
- Track current job status in real-time
- View invoices and payment history
- View bikes registered in shop
- Download invoice PDFs

### 2. Push Notifications (Automated)
- Job status changes → "Your bike is in diagnosis"
- Job completed → "Your bike is ready for pickup!"
- New invoice → "Invoice #123 available - $50,000"
- Payment received → "Payment confirmed - Thank you!"
- Reminders → "Your bike has been ready for 3 days"

### 3. Online Payments (Phase 2)
- Pay invoices via credit/debit card
- Chilean payment gateways (Transbank, Flow, Mercado Pago)
- Payment confirmation receipts

### 4. Direct Communication
- "Contact Shop" button (call or WhatsApp fallback)
- View shop hours and location
- Appointment requests (future)

---

## 🏗️ App Architecture

### **Folder Structure**

The topology below is historical planning context, not a requirement to create
parallel screens or presentation-only components. Reuse current canonical
owners and shared components after inspecting the live repository.

```
customer_app/
├── lib/
│   ├── main.dart
│   ├── models/           # Shared with ERP (symlink or package)
│   │   ├── bike.dart
│   │   ├── mechanic_job.dart
│   │   ├── invoice.dart
│   │   └── customer.dart
│   ├── services/
│   │   ├── auth_service.dart
│   │   ├── job_service.dart
│   │   ├── invoice_service.dart
│   │   ├── notification_service.dart (FCM)
│   │   └── supabase_service.dart
│   ├── screens/
│   │   ├── auth/
│   │   │   ├── login_screen.dart
│   │   │   └── otp_verification_screen.dart
│   │   ├── home/
│   │   │   └── home_screen.dart (dashboard)
│   │   ├── jobs/
│   │   │   ├── jobs_list_screen.dart
│   │   │   └── job_detail_screen.dart
│   │   ├── invoices/
│   │   │   ├── invoices_list_screen.dart
│   │   │   └── invoice_detail_screen.dart
│   │   └── bikes/
│   │       └── bikes_list_screen.dart
│   └── widgets/          # Reuse current shared components where appropriate
```

---

## 🔐 Authentication Flow

### **Phase 1: Phone Number + OTP**
1. Customer enters phone number
2. Supabase sends OTP via SMS (Twilio integration)
3. Customer enters OTP
4. App queries `customers` table to find customer by phone
5. If found → Login success
6. If not found → Show "Contact shop to register" message

### **Phase 2: Email + Password (Optional)**
- Allow email/password login for customers who prefer it
- Link to phone number in database

### **Database Changes Needed**
```sql
-- Add authentication columns to customers table
alter table customers add column if not exists auth_user_id uuid references auth.users(id);
alter table customers add column if not exists fcm_token text; -- For push notifications

-- RLS policies for customer data access
create policy "customers_own_data" on customers for select
  using (auth_user_id = auth.uid());

create policy "customers_own_bikes" on bikes for select
  using (customer_id in (select id from customers where auth_user_id = auth.uid()));

create policy "customers_own_jobs" on mechanic_jobs for select
  using (customer_id in (select id from customers where auth_user_id = auth.uid()));

create policy "customers_own_invoices" on sales_invoices for select
  using (customer_id in (select id from customers where auth_user_id = auth.uid()));
```

---

## 📱 Historical screen information requirements

These are content requirements, not layouts:

- **Home:** identify the customer, active work, pending financial exception,
  registered bicycles, and the most relevant next actions without turning each
  value into a decorative metric card.
- **Job detail:** identify the job and bicycle, expose current state and useful
  history, description, estimate, related invoice, and contact action.
- **Invoice detail:** expose identity, issue/due dates, state, line detail,
  subtotal, IVA, total, document access, and payment action when allowed.

Compose these requirements for the current phone/tablet host according to both
canonical guides. Preserve exact origin and list state when entering and
returning from related work.

---

## 🔔 Push Notifications Implementation

### **Backend (ERP) - Trigger Functions**

```dart
// In ERP: lib/modules/bikeshop/services/bikeshop_service.dart

Future<void> updateJobStatus(String jobId, JobStatus newStatus) async {
  // Update job in database
  await _db.update('mechanic_jobs', {
    'id': jobId,
    'status': newStatus.dbValue,
  });
  
  // Send push notification to customer
  await _notificationService.sendJobStatusNotification(
    jobId: jobId,
    newStatus: newStatus,
  );
}
```

### **Notification Service (ERP)**

```dart
// New file: lib/shared/services/push_notification_service.dart

import 'package:http/http.dart' as http;
import 'dart:convert';

class PushNotificationService {
  final String _fcmServerKey = 'YOUR_FCM_SERVER_KEY'; // From Firebase Console
  
  Future<void> sendJobStatusNotification({
    required String jobId,
    required JobStatus newStatus,
  }) async {
    // 1. Get job details
    final job = await _getJob(jobId);
    
    // 2. Get customer FCM token
    final customer = await _getCustomer(job.customerId);
    if (customer.fcmToken == null) return; // Customer doesn't have app installed
    
    // 3. Send FCM notification
    await _sendFCM(
      token: customer.fcmToken!,
      title: '🚴 Estado de tu bicicleta',
      body: _getStatusMessage(newStatus),
      data: {
        'type': 'job_update',
        'job_id': jobId,
        'status': newStatus.name,
      },
    );
  }
  
  Future<void> _sendFCM({
    required String token,
    required String title,
    required String body,
    required Map<String, dynamic> data,
  }) async {
    final url = Uri.parse('https://fcm.googleapis.com/fcm/send');
    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'key=$_fcmServerKey',
      },
      body: jsonEncode({
        'to': token,
        'notification': {
          'title': title,
          'body': body,
          'sound': 'default',
        },
        'data': data,
        'priority': 'high',
      }),
    );
    
    if (response.statusCode != 200) {
      print('❌ FCM Error: ${response.body}');
    }
  }
  
  String _getStatusMessage(JobStatus status) {
    switch (status) {
      case JobStatus.diagnostico:
        return 'Estamos revisando tu bicicleta';
      case JobStatus.esperandoRepuestos:
        return 'Esperando repuestos necesarios';
      case JobStatus.enCurso:
        return 'Tu bicicleta está en reparación';
      case JobStatus.finalizado:
        return '¡Tu bicicleta está lista para retiro!';
      case JobStatus.entregado:
        return 'Gracias por confiar en nosotros. ¡Disfruta tu bici!';
      default:
        return 'Estado actualizado';
    }
  }
}
```

### **Customer App - FCM Setup**

```dart
// customer_app/lib/services/notification_service.dart

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  
  Future<void> initialize() async {
    // Request permission
    await _fcm.requestPermission();
    
    // Get FCM token
    final token = await _fcm.getToken();
    print('📱 FCM Token: $token');
    
    // Save token to customer record in database
    await _saveTokenToDatabase(token);
    
    // Handle foreground messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    
    // Handle background messages
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);
  }
  
  Future<void> _saveTokenToDatabase(String? token) async {
    if (token == null) return;
    
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    
    await Supabase.instance.client
        .from('customers')
        .update({'fcm_token': token})
        .eq('auth_user_id', userId);
  }
  
  void _handleForegroundMessage(RemoteMessage message) {
    print('📩 Notification: ${message.notification?.title}');
    
    // Show local notification
    _localNotifications.show(
      message.hashCode,
      message.notification?.title,
      message.notification?.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'vinabike_channel',
          'Viña Bike',
          importance: Importance.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }
  
  void _handleNotificationTap(RemoteMessage message) {
    // Navigate to specific screen based on notification type
    final type = message.data['type'];
    
    if (type == 'job_update') {
      final jobId = message.data['job_id'];
      // Navigate to job detail screen
      navigatorKey.currentState?.pushNamed('/job/$jobId');
    } else if (type == 'invoice') {
      final invoiceId = message.data['invoice_id'];
      // Navigate to invoice detail screen
      navigatorKey.currentState?.pushNamed('/invoice/$invoiceId');
    }
  }
}
```

---

## 📋 Implementation Timeline

### **Week 1: Foundation**
- [ ] Create Flutter customer app project
- [ ] Setup Firebase FCM
- [ ] Configure Supabase connection
- [ ] Implement authentication (phone OTP)
- [ ] Add `auth_user_id` and `fcm_token` to customers table

### **Week 2: Core Features**
- [ ] Build home screen (dashboard)
- [ ] Build jobs list and detail screens
- [ ] Build invoices list and detail screens
- [ ] Build bikes list screen
- [ ] Implement real-time job status updates

### **Week 3: Notifications**
- [ ] Integrate FCM in customer app
- [ ] Create PushNotificationService in ERP
- [ ] Add notification triggers to job status changes
- [ ] Add notification triggers to invoice creation
- [ ] Add notification triggers to payment confirmation

### **Week 4: Polish & Testing**
- [ ] Test with real customers
- [ ] Fix bugs
- [ ] Optimize performance
- [ ] Prepare for App Store/Play Store submission
- [ ] Create app screenshots and descriptions

### **Week 5: Launch**
- [ ] Submit to Apple App Store
- [ ] Submit to Google Play Store
- [ ] Create QR code for easy download
- [ ] Train shop staff on how to invite customers

---

## 💰 Cost Breakdown

### **One-Time Costs**
- Apple Developer Account: $99/year
- Google Play Developer Account: $25 one-time

### **Monthly Costs**
- Firebase FCM: **FREE** (unlimited notifications)
- Supabase: Current plan (already paying)
- Twilio SMS (OTP): ~$0.01/SMS × 100 customers/month = **$1/month**

**Total Monthly: ~$1-2 USD** (almost free!)

---

## 🎯 Success Metrics

After 3 months of launch, measure:
- **App Downloads**: Target 50% of active customers
- **Active Users**: Target 30% weekly active
- **Notification Open Rate**: Target 40%+
- **Customer Satisfaction**: Survey NPS score
- **Support Load Reduction**: Measure calls/messages decrease

---

## 🚀 Marketing Strategy

### **Launch Campaign**
1. **QR Code Stickers**: Print QR codes, place in shop
2. **Invoice Footer**: "Track your bike! Download our app: [QR Code]"
3. **WhatsApp Broadcast**: "Hola! Now you can track your bike repairs from your phone! Download our app: [link]"
4. **Instagram Post**: "🎉 New! Track your bike repairs in real-time"
5. **Customer Referral**: Free service ($10K) for referring 5 friends who download app

### **Customer Onboarding**
1. Customer downloads app
2. Enters phone number
3. Receives OTP
4. Logs in
5. Sees all their bikes and jobs automatically
6. Receives welcome notification: "Welcome to Viña Bike! Your bike repairs at your fingertips 🚴"

---

## 🔧 Technical Requirements

### **ERP Changes Needed**
1. Add `auth_user_id` and `fcm_token` columns to `customers` table
2. Create `PushNotificationService` in ERP
3. Integrate FCM API calls
4. Add RLS policies for customer data access
5. Add notification triggers to job/invoice updates

### **Customer App Requirements**
1. Flutter SDK 3.0+
2. Firebase account (free plan)
3. Twilio account for SMS OTP (pay-as-you-go)
4. Apple Developer account (for iOS)
5. Google Play Developer account (for Android)

---

## 📱 App Store Listing

### **App Name**
Viña Bike - Taller de Bicicletas

### **Description (Spanish)**
```
Viña Bike te permite seguir el estado de tus reparaciones en tiempo real.

✨ Características:
• 📋 Ver estado de tus trabajos en tiempo real
• 💰 Consultar y pagar facturas
• 🚴 Historial completo de tus bicicletas
• 🔔 Notificaciones automáticas cuando tu bici esté lista
• 📞 Contacto directo con el taller

Viña Bike - Tu taller de confianza en Viña del Mar 🔧
```

### **Screenshots Needed**
1. Home screen with active jobs
2. Job detail with useful status/history context
3. Invoice list
4. Bike history
5. Push notification example

---

## 🎨 Branding

### **App Icon**
- Use Viña Bike logo
- Adapt the asset to current iOS and Android icon requirements without
  prescribing a decorative shape or legacy palette here.

### **Visual system**

Use the current theme-owned brand, interaction, surface, and semantic roles
defined by the canonical GUI guide. Professional must not be interpreted as
monochrome or lifeless, and brand expression must not become a bright
multi-color control palette.

---

## 🔐 Security Considerations

1. **Authentication**: Use Supabase Auth (industry standard)
2. **RLS Policies**: Customers can ONLY see their own data
3. **API Keys**: Store in environment variables, never in code
4. **FCM Tokens**: Encrypted in database
5. **Payment Gateway**: Use PCI-compliant providers (Transbank)

---

## 📞 Customer Support

### **In-App Help**
- "How to track my bike?" tutorial
- "How to pay invoices?" guide
- FAQ section

### **Contact Options**
- Call shop button (direct phone call)
- WhatsApp button (fallback for complex issues)
- Email support form

---

## 🎉 Future Enhancements (Phase 2)

1. **Online Appointment Booking**: Schedule repairs from app
2. **Loyalty Program**: Points for each service
3. **Bike Maintenance Reminders**: "Your bike needs service every 6 months"
4. **Chat Support**: In-app messaging with shop
5. **Parts Catalog**: Browse and order parts
6. **Service Packages**: Buy multi-service packages at discount

---

**Ready to build?** This is a professional, scalable solution that will set Viña Bike apart from competitors! 🚀
