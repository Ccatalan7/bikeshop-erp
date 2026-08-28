import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import '../../modules/messaging/services/messaging_service.dart';
import '../../modules/sales/models/sales_models.dart';
import '../../modules/bikeshop/models/bikeshop_models.dart';
import '../services/tenant_service.dart';
import '../services/whatsapp_send_receipt.dart';
import '../widgets/whatsapp_web_viewer.dart';

export '../services/whatsapp_send_receipt.dart';

const Set<String> _compoundWhatsAppGivenNames = {
  'ana maria',
  'ana paula',
  'ana sofia',
  'carmen gloria',
  'francisco javier',
  'jorge luis',
  'jose antonio',
  'jose carlos',
  'jose francisco',
  'jose ignacio',
  'jose luis',
  'jose manuel',
  'jose maria',
  'jose miguel',
  'jose pablo',
  'juan antonio',
  'juan carlos',
  'juan francisco',
  'juan ignacio',
  'juan jose',
  'juan luis',
  'juan manuel',
  'juan miguel',
  'juan pablo',
  'juan sebastian',
  'luis alberto',
  'luis enrique',
  'luis felipe',
  'luis miguel',
  'luz maria',
  'marco antonio',
  'maria angelica',
  'maria carolina',
  'maria elena',
  'maria fernanda',
  'maria ignacia',
  'maria isabel',
  'maria jesus',
  'maria jose',
  'maria paz',
  'maria soledad',
  'maria teresa',
  'miguel angel',
  'pedro pablo',
  'rosa maria',
};

String _foldWhatsAppNameToken(String value) => value
    .toLowerCase()
    .replaceAll('á', 'a')
    .replaceAll('é', 'e')
    .replaceAll('í', 'i')
    .replaceAll('ó', 'o')
    .replaceAll('ú', 'u')
    .replaceAll('ü', 'u');

/// Cómo saludamos a alguien en una plantilla: por su nombre, no por su
/// nombre completo. La regla no es «la primera palabra» —conserva compuestos
/// como «José Luis»— y por eso vive en un solo lugar.
///
/// Dejó de ser sólo-para-pruebas el 2026-08-21: la previsualización del
/// asistente tiene que usar exactamente esta función, porque si la revisión
/// dice «Marcelo Silva» y el mensaje sale «Marcelo», la revisión no sirve.
String resolveWhatsAppTemplateGreetingName(String fullName) {
  final parts = fullName
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.length <= 1) return parts.isEmpty ? '' : parts.first;

  final firstPair = '${_foldWhatsAppNameToken(parts[0])} '
      '${_foldWhatsAppNameToken(parts[1])}';
  final preservesCompoundName =
      parts.length >= 3 && _compoundWhatsAppGivenNames.contains(firstPair);
  final hasTwoGivenNames = parts.length >= 4 &&
      !const {'de', 'del', 'la', 'las', 'los'}
          .contains(_foldWhatsAppNameToken(parts[1]));

  return preservesCompoundName || hasTwoGivenNames
      ? '${parts[0]} ${parts[1]}'
      : parts.first;
}

enum WhatsAppTemplatePurpose {
  firstContact,
  jobUpdate,
  readyForPickup,
  quoteFollowUp,
  supplierIntroduction,
  supplierGreeting,
  supplierResumeContact,
  supplierAskForNews,
  supplierPendingPurchase,
}

enum WhatsAppTemplateAudience { customer, supplier }

enum WhatsAppMessageCategory { utility, marketing, authentication }

enum WhatsAppTemplateParameterLayout {
  contactAndAgent,
  contactAndBusiness,
  contactOnly,
}

class WhatsAppTemplateOption {
  final WhatsAppTemplatePurpose purpose;
  final String key;
  final String label;
  final String description;
  final String defaultTemplateName;
  final String defaultLanguage;
  final String templateNameSettingKey;
  final String templateLanguageSettingKey;
  final IconData icon;
  final WhatsAppTemplateAudience audience;
  final WhatsAppMessageCategory category;
  final WhatsAppTemplateParameterLayout parameterLayout;
  final bool requiresAgentName;

  const WhatsAppTemplateOption({
    required this.purpose,
    required this.key,
    required this.label,
    required this.description,
    required this.defaultTemplateName,
    required this.defaultLanguage,
    required this.templateNameSettingKey,
    required this.templateLanguageSettingKey,
    required this.icon,
    required this.audience,
    required this.category,
    required this.parameterLayout,
    this.requiresAgentName = false,
  });

  bool get isSupplier => audience == WhatsAppTemplateAudience.supplier;

  /// El texto tiene que ser **literalmente** el cuerpo que Meta aprobó, en
  /// `supabase/functions/_shared/whatsapp_templates.ts`. No es una redacción
  /// nuestra: es la copia local de algo que ya está publicado.
  ///
  /// El 2026-08-21 estas tres llevaban tilde —«está lista», «actualización»,
  /// «aprobación»— y los cuerpos aprobados no la llevan. El cliente recibía una
  /// cosa y la bandeja del taller archivaba otra. Se comprobó con un envío real
  /// al teléfono del dueño: llegó sin tildes.
  String renderPreview({
    required String contactName,
    required String businessName,
    String? agentName,
  }) {
    final greetingName = resolveWhatsAppTemplateGreetingName(contactName);
    final normalizedSender =
        agentName == null ? '' : resolveWhatsAppTemplateGreetingName(agentName);
    final sender =
        normalizedSender.isNotEmpty ? normalizedSender : 'parte del equipo';

    return switch (purpose) {
      WhatsAppTemplatePurpose.firstContact =>
        'Hola $greetingName, hablas con $sender de Viñabike. Te escribo por el servicio de tu bicicleta.',
      WhatsAppTemplatePurpose.jobUpdate =>
        'Hola $greetingName, tenemos una actualización sobre tu bicicleta en $businessName. Responde este mensaje para continuar la conversación.',
      WhatsAppTemplatePurpose.readyForPickup =>
        'Hola $greetingName, tu bicicleta está lista para retiro en $businessName. Responde este mensaje si necesitas coordinar algo.',
      WhatsAppTemplatePurpose.quoteFollowUp =>
        'Hola $greetingName, necesitamos tu respuesta sobre un presupuesto o aprobación pendiente en $businessName. Responde este mensaje para continuar.',
      WhatsAppTemplatePurpose.supplierIntroduction =>
        'Hola $greetingName, buen día. Soy $sender, del equipo de Viñabike en Viña del Mar, razón social NEWEN SpA. Con nuestro equipo estamos usando este nuevo número para comunicarnos con nuestros proveedores, así que quería presentarme y confirmar que podemos coordinarnos por aquí para compras, cotizaciones, documentos y despachos.\n\nQuedo atento. Saludos.',
      WhatsAppTemplatePurpose.supplierGreeting =>
        'Hola $greetingName, buen día.',
      WhatsAppTemplatePurpose.supplierResumeContact =>
        'Hola $greetingName, buen día. Cuando puedas me hablas, porfa. Quedo atento. Saludos.',
      WhatsAppTemplatePurpose.supplierAskForNews =>
        'Hola $greetingName, buen día. Cuando puedas me cuentas si hay alguna novedad, porfa. Quedo atento. Saludos.',
      WhatsAppTemplatePurpose.supplierPendingPurchase =>
        'Hola $greetingName, buen día. Te escribo para seguir con el pedido que tenemos pendiente. Cuando puedas me hablas, porfa. Quedo atento, saludos.',
    };
  }

  List<String> bodyParameters({
    required String contactName,
    required String businessName,
    String? agentName,
  }) {
    final normalizedContact = resolveWhatsAppTemplateGreetingName(contactName);
    if (normalizedContact.isEmpty) {
      throw ArgumentError.value(
        contactName,
        'contactName',
        'El nombre del contacto no puede estar vacío',
      );
    }

    // Quien escribe se presenta como se presenta una persona: por su nombre.
    // Se usa la MISMA regla que para el cliente, que conserva compuestos como
    // «José Luis» y deja fuera el apellido.
    final normalizedAgent = agentName == null
        ? null
        : resolveWhatsAppTemplateGreetingName(agentName);
    if (requiresAgentName &&
        (normalizedAgent == null || normalizedAgent.isEmpty)) {
      throw ArgumentError.value(
        agentName,
        'agentName',
        'La plantilla requiere el nombre del usuario conectado',
      );
    }
    return switch (parameterLayout) {
      WhatsAppTemplateParameterLayout.contactAndAgent => [
          normalizedContact,
          normalizedAgent?.isNotEmpty == true
              ? normalizedAgent!
              : 'parte del equipo',
        ],
      WhatsAppTemplateParameterLayout.contactAndBusiness => [
          normalizedContact,
          businessName.trim(),
        ],
      WhatsAppTemplateParameterLayout.contactOnly => [normalizedContact],
    };
  }
}

class WhatsAppTemplateReviewStatus {
  final String status;
  final String? category;
  final String? rejectedReason;

  const WhatsAppTemplateReviewStatus({
    required this.status,
    this.category,
    this.rejectedReason,
  });

  bool get isApproved => status == 'APPROVED';

  factory WhatsAppTemplateReviewStatus.fromMap(Map<dynamic, dynamic> data) {
    String? normalized(String key) {
      final value = data[key]?.toString().trim();
      return value == null || value.isEmpty ? null : value.toUpperCase();
    }

    return WhatsAppTemplateReviewStatus(
      status: normalized('status') ?? 'UNKNOWN',
      category: normalized('category'),
      rejectedReason: normalized('rejected_reason'),
    );
  }
}

/// WhatsApp messaging service for customer communication
/// Sends through WhatsApp Cloud API and falls back to manual WhatsApp Web if needed.
class WhatsAppService {
  static final WhatsAppService _instance = WhatsAppService._internal();
  static const String firstContactTemplateName =
      'seguimiento_servicio_bicicleta';
  static const String firstContactTemplateLanguage = 'es_CL';
  static const String firstContactTemplateNameSettingKey =
      'whatsapp_first_contact_template_name';
  static const String firstContactTemplateLanguageSettingKey =
      'whatsapp_first_contact_template_language';
  static const List<WhatsAppTemplateOption> customerTemplateOptions = [
    WhatsAppTemplateOption(
      purpose: WhatsAppTemplatePurpose.firstContact,
      key: 'first_contact',
      label: 'Primer contacto',
      description: 'Abre una conversación nueva con el cliente.',
      defaultTemplateName: firstContactTemplateName,
      defaultLanguage: firstContactTemplateLanguage,
      templateNameSettingKey: firstContactTemplateNameSettingKey,
      templateLanguageSettingKey: firstContactTemplateLanguageSettingKey,
      icon: Icons.waving_hand_outlined,
      audience: WhatsAppTemplateAudience.customer,
      category: WhatsAppMessageCategory.utility,
      parameterLayout: WhatsAppTemplateParameterLayout.contactAndAgent,
    ),
    WhatsAppTemplateOption(
      purpose: WhatsAppTemplatePurpose.jobUpdate,
      key: 'job_update',
      label: 'Actualización de taller',
      description: 'Reabre una conversación por una actualización del trabajo.',
      defaultTemplateName: 'actualizacion_servicio_bicicleta',
      defaultLanguage: firstContactTemplateLanguage,
      templateNameSettingKey: 'whatsapp_job_update_template_name',
      templateLanguageSettingKey: 'whatsapp_job_update_template_language',
      icon: Icons.build_outlined,
      audience: WhatsAppTemplateAudience.customer,
      category: WhatsAppMessageCategory.utility,
      parameterLayout: WhatsAppTemplateParameterLayout.contactAndBusiness,
    ),
    WhatsAppTemplateOption(
      purpose: WhatsAppTemplatePurpose.readyForPickup,
      key: 'ready_for_pickup',
      label: 'Lista para retiro',
      description: 'Avisa que la bicicleta está lista o requiere coordinación.',
      defaultTemplateName: 'bicicleta_lista_retiro',
      defaultLanguage: firstContactTemplateLanguage,
      templateNameSettingKey: 'whatsapp_ready_pickup_template_name',
      templateLanguageSettingKey: 'whatsapp_ready_pickup_template_language',
      icon: Icons.task_alt_outlined,
      audience: WhatsAppTemplateAudience.customer,
      category: WhatsAppMessageCategory.utility,
      parameterLayout: WhatsAppTemplateParameterLayout.contactAndBusiness,
    ),
    WhatsAppTemplateOption(
      purpose: WhatsAppTemplatePurpose.quoteFollowUp,
      key: 'quote_follow_up',
      label: 'Presupuesto / aprobación',
      description: 'Pide respuesta sobre presupuesto, aprobación o pendiente.',
      defaultTemplateName: 'seguimiento_presupuesto_bicicleta',
      defaultLanguage: firstContactTemplateLanguage,
      templateNameSettingKey: 'whatsapp_quote_follow_up_template_name',
      templateLanguageSettingKey: 'whatsapp_quote_follow_up_template_language',
      icon: Icons.request_quote_outlined,
      audience: WhatsAppTemplateAudience.customer,
      category: WhatsAppMessageCategory.utility,
      parameterLayout: WhatsAppTemplateParameterLayout.contactAndBusiness,
    ),
  ];

  static const List<WhatsAppTemplateOption> supplierTemplateOptions = [
    WhatsAppTemplateOption(
      purpose: WhatsAppTemplatePurpose.supplierIntroduction,
      key: 'supplier_introduction',
      label: 'Presentación / nuevo número',
      description: 'Presenta este número y al usuario que inició sesión.',
      defaultTemplateName: 'proveedor_presentacion_nuevo_numero_v1',
      defaultLanguage: firstContactTemplateLanguage,
      templateNameSettingKey: 'whatsapp_supplier_introduction_template_name',
      templateLanguageSettingKey:
          'whatsapp_supplier_introduction_template_language',
      icon: Icons.waving_hand_outlined,
      audience: WhatsAppTemplateAudience.supplier,
      category: WhatsAppMessageCategory.marketing,
      parameterLayout: WhatsAppTemplateParameterLayout.contactAndAgent,
      requiresAgentName: true,
    ),
    WhatsAppTemplateOption(
      purpose: WhatsAppTemplatePurpose.supplierGreeting,
      key: 'supplier_greeting',
      label: 'Hola, buen día',
      description: 'Un saludo breve para volver a abrir la conversación.',
      defaultTemplateName: 'proveedor_saludo_v1',
      defaultLanguage: firstContactTemplateLanguage,
      templateNameSettingKey: 'whatsapp_supplier_greeting_template_name',
      templateLanguageSettingKey:
          'whatsapp_supplier_greeting_template_language',
      icon: Icons.chat_bubble_outline,
      audience: WhatsAppTemplateAudience.supplier,
      category: WhatsAppMessageCategory.marketing,
      parameterLayout: WhatsAppTemplateParameterLayout.contactOnly,
    ),
    WhatsAppTemplateOption(
      purpose: WhatsAppTemplatePurpose.supplierResumeContact,
      key: 'supplier_resume_contact',
      label: 'Retomar contacto',
      description: 'Pide que te escriban cuando puedan.',
      defaultTemplateName: 'proveedor_retomar_contacto_v1',
      defaultLanguage: firstContactTemplateLanguage,
      templateNameSettingKey: 'whatsapp_supplier_resume_template_name',
      templateLanguageSettingKey: 'whatsapp_supplier_resume_template_language',
      icon: Icons.forum_outlined,
      audience: WhatsAppTemplateAudience.supplier,
      category: WhatsAppMessageCategory.marketing,
      parameterLayout: WhatsAppTemplateParameterLayout.contactOnly,
    ),
    WhatsAppTemplateOption(
      purpose: WhatsAppTemplatePurpose.supplierAskForNews,
      key: 'supplier_ask_for_news',
      label: 'Consultar novedades',
      description: 'Pregunta de forma casual si hay alguna novedad.',
      defaultTemplateName: 'proveedor_consulta_novedades_v1',
      defaultLanguage: firstContactTemplateLanguage,
      templateNameSettingKey: 'whatsapp_supplier_news_template_name',
      templateLanguageSettingKey: 'whatsapp_supplier_news_template_language',
      icon: Icons.mark_chat_unread_outlined,
      audience: WhatsAppTemplateAudience.supplier,
      category: WhatsAppMessageCategory.marketing,
      parameterLayout: WhatsAppTemplateParameterLayout.contactOnly,
    ),
    WhatsAppTemplateOption(
      purpose: WhatsAppTemplatePurpose.supplierPendingPurchase,
      key: 'supplier_pending_purchase',
      label: 'Pedido pendiente',
      description: 'Retoma el pedido que sigue pendiente.',
      defaultTemplateName: 'proveedor_pedido_pendiente_v3',
      defaultLanguage: firstContactTemplateLanguage,
      templateNameSettingKey:
          'whatsapp_supplier_pending_purchase_template_name',
      templateLanguageSettingKey:
          'whatsapp_supplier_pending_purchase_template_language',
      icon: Icons.shopping_cart_outlined,
      audience: WhatsAppTemplateAudience.supplier,
      category: WhatsAppMessageCategory.utility,
      parameterLayout: WhatsAppTemplateParameterLayout.contactOnly,
    ),
  ];

  /// Backwards-compatible customer option list for existing call sites.
  static const List<WhatsAppTemplateOption> templateOptions =
      customerTemplateOptions;

  static List<WhatsAppTemplateOption> templateOptionsForConversation({
    required bool isSupplier,
  }) {
    return isSupplier ? supplierTemplateOptions : customerTemplateOptions;
  }

  factory WhatsAppService() => _instance;
  WhatsAppService._internal();

  final SupabaseClient _client = Supabase.instance.client;

  final _currencyFormat = NumberFormat.currency(
    symbol: '\$',
    decimalDigits: 0,
    locale: 'es_CL',
  );

  final _dateFormat = DateFormat('dd/MM/yyyy', 'es_CL');

  /// Corrige en Meta el texto de las plantillas cuyo cuerpo aprobado difiere
  /// del que el ERP considera correcto.
  ///
  /// `deploy_defaults` sólo crea lo que falta, así que un cuerpo mal escrito se
  /// queda para siempre: así llegó a producción un «tu bicicleta esta lista»
  /// sin tilde. Editar manda la plantilla de vuelta a revisión de Meta, y
  /// mientras esté pendiente el envío con ese nombre puede fallar.
  Future<
      ({
        List<String> editadas,
        List<String> sinCambios,
        List<String> faltan
      })> syncApprovedTemplateBodies() async {
    final response = await _client.functions.invoke(
      'whatsapp-template-manager',
      body: const {'action': 'sync_bodies'},
    );
    final data = response.data;
    if (data is! Map) {
      throw StateError('Meta no confirmó la sincronización de plantillas.');
    }
    List<String> names(String key) => (data[key] as List? ?? const [])
        .map((item) => item is Map ? '${item['name']}' : '$item')
        .toList(growable: false);
    return (
      editadas: names('edited'),
      sinCambios: names('unchanged'),
      faltan: names('missing'),
    );
  }

  Future<Map<String, WhatsAppTemplateReviewStatus>>
      getSupplierTemplateReviewStatuses() async {
    final response = await _client.functions.invoke(
      'whatsapp-template-manager',
      body: const {'action': 'list'},
    );
    if (response.status < 200 || response.status >= 300) {
      throw StateError(
        'Meta no pudo confirmar el estado de las plantillas de proveedores.',
      );
    }

    final data = response.data;
    if (data is! Map || data['templates'] is! List) {
      throw const FormatException(
        'La respuesta de Meta no contiene el listado de plantillas.',
      );
    }

    // Se devuelven las de proveedor Y las de cliente. Corregir un texto manda
    // la plantilla a revisión de Meta, y mientras esté pendiente el envío
    // falla con 132001: sin ver ese estado, el taller sólo sabe que «no se
    // pudo enviar» y no por qué ni hasta cuándo.
    final expectedNames = <String>{
      ...supplierTemplateOptions.map((option) => option.defaultTemplateName),
      ...customerTemplateOptions.map((option) => option.defaultTemplateName),
    };
    final statuses = <String, WhatsAppTemplateReviewStatus>{};
    for (final item in data['templates'] as List) {
      if (item is! Map) continue;
      final name = item['name']?.toString().trim();
      final language = item['language']?.toString().trim();
      if (name == null ||
          !expectedNames.contains(name) ||
          language != firstContactTemplateLanguage) {
        continue;
      }
      statuses[name] = WhatsAppTemplateReviewStatus.fromMap(item);
    }
    return statuses;
  }

  /// Format Chilean phone number (remove spaces, dashes, +56 prefix)
  String _formatPhoneNumber(String phone) {
    String cleaned = phone.replaceAll(RegExp(r'[^0-9]'), '');

    if (cleaned.startsWith('56') && cleaned.length > 9) {
      cleaned = cleaned.substring(2);
    }

    if (!cleaned.startsWith('9')) {
      cleaned = '9$cleaned';
    }

    return '56$cleaned';
  }

  /// Nombre, teléfono y negocio de un cliente, para previsualizar y enviar una
  /// plantilla desde el asistente. Vive acá y no en el asistente porque el
  /// teléfono es dato de contacto: el servidor nunca se lo manda al modelo,
  /// sólo le dice si existe.
  /// Incluye el nombre de quien tiene la sesión abierta: las plantillas de
  /// primer contacto se presentan por persona —«hablas con Claudio»— y ese
  /// dato es el segundo parámetro que recibe Meta, no el del negocio.
  Future<
      ({
        String name,
        String phone,
        String businessName,
        String? agentName,
      })?> customerContactForAssistant(String customerId) async {
    try {
      final row = await _client
          .from('customers')
          .select('name, phone')
          .eq('id', customerId)
          .maybeSingle();
      if (row == null) return null;
      final phone = (row['phone'] as String?)?.trim() ?? '';
      final name = (row['name'] as String?)?.trim() ?? '';
      if (phone.isEmpty || name.isEmpty) return null;
      return (
        name: name,
        phone: phone,
        businessName: await _resolveBusinessName(),
        agentName: await _resolveSignedInAgentName(),
      );
    } catch (error) {
      debugPrint('⚠️ No se pudo resolver el contacto del cliente: $error');
      return null;
    }
  }

  /// Nombre de quien tiene la sesión abierta, tal como lo muestra el ERP.
  Future<String?> _resolveSignedInAgentName() async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return null;
      // El nombre visible del operador lo resuelve el mismo servicio que usa
      // la ventana de conversación, para que la plantilla del asistente firme
      // igual que una enviada a mano.
      final info = await MessagingService().getSenderInfo(userId);
      final name = info?['name']?.toString().trim();
      return name == null || name.isEmpty ? null : name;
    } catch (error) {
      debugPrint('⚠️ No se pudo resolver el nombre del usuario: $error');
      return null;
    }
  }

  /// El nombre del negocio tal como aparecerá en la plantilla. Público porque
  /// la previsualización tiene que usar exactamente el mismo valor que el
  /// envío, y ese valor lo resuelve este servicio.
  Future<String> resolveBusinessNameForPreview() => _resolveBusinessName();

  Future<String> _resolveBusinessName() async {
    try {
      final tenant = await TenantService().getCurrentTenant();
      final shopName = tenant?['shop_name']?.toString().trim();
      if (shopName != null && shopName.isNotEmpty) {
        return shopName;
      }
    } catch (error) {
      debugPrint('⚠️ [WhatsAppService] Could not resolve tenant name: $error');
    }

    return 'Viñabike';
  }

  String buildTemplatePreviewText({
    required WhatsAppTemplateOption option,
    required String customerName,
    required String businessName,
    String? agentName,
  }) {
    return option.renderPreview(
      contactName: customerName,
      businessName: businessName,
      agentName: agentName,
    );
  }

  String? _extractExternalMessageId(dynamic data) {
    if (data is! Map<String, dynamic>) {
      return null;
    }

    final directId = data['external_message_id']?.toString().trim();
    if (directId != null && directId.isNotEmpty) {
      return directId;
    }

    final graphResult = data['graph_result'];
    if (graphResult is Map<String, dynamic>) {
      final messages = graphResult['messages'];
      if (messages is List && messages.isNotEmpty) {
        final firstMessage = messages.first;
        if (firstMessage is Map<String, dynamic>) {
          final id = firstMessage['id']?.toString().trim();
          if (id != null && id.isNotEmpty) {
            return id;
          }
        }
      }
    }

    return null;
  }

  String? _extractMessageId(dynamic data) {
    if (data is! Map) return null;
    final messageId = data['message_id']?.toString().trim();
    return messageId == null || messageId.isEmpty ? null : messageId;
  }

  int? _extractErrorCode(dynamic data) {
    if (data is Map<String, dynamic>) {
      final directDetails = data['details'];
      if (directDetails is Map<String, dynamic>) {
        final error = directDetails['error'];
        if (error is Map<String, dynamic>) {
          final code = error['code'];
          if (code is num) {
            return code.toInt();
          }
        }
      }

      final errors = data['errors'];
      if (errors is List && errors.isNotEmpty) {
        final first = errors.first;
        if (first is Map<String, dynamic>) {
          final code = first['code'];
          if (code is num) {
            return code.toInt();
          }
        }
      }
    }

    return null;
  }

  bool _extractUnsafeToFallback(dynamic data) {
    return isUnsafeWhatsAppManualFallback(data);
  }

  bool _shouldSkipManualFallback(WhatsAppSendReceipt receipt) {
    return receipt.errorRequiresServerFix || receipt.unsafeToFallback;
  }

  bool _isCustomerServiceWindowOpen(DateTime? lastInboundAt) {
    if (lastInboundAt == null) {
      return false;
    }

    return DateTime.now().toUtc().difference(lastInboundAt.toUtc()) <
        const Duration(hours: 24);
  }

  Future<({String templateName, String templateLanguage})>
      _loadFirstContactTemplateSettings() async {
    return _loadTemplateSettings(customerTemplateOptions.first);
  }

  Future<({String templateName, String templateLanguage})>
      _loadTemplateSettings(WhatsAppTemplateOption option) async {
    try {
      final tenantId = await TenantService().getTenantId();
      if (tenantId == null || tenantId.isEmpty) {
        return (
          templateName: option.defaultTemplateName,
          templateLanguage: option.defaultLanguage,
        );
      }

      final rows = await _client
          .from('company_settings')
          .select('key, value')
          .eq('tenant_id', tenantId)
          .inFilter('key', [
        option.templateNameSettingKey,
        option.templateLanguageSettingKey,
      ]);

      String templateName = option.defaultTemplateName;
      String templateLanguage = option.defaultLanguage;

      for (final row in rows) {
        final key = row['key']?.toString();
        final value = row['value']?.toString().trim();
        if (value == null || value.isEmpty) {
          continue;
        }

        if (key == option.templateNameSettingKey) {
          templateName = value;
        } else if (key == option.templateLanguageSettingKey) {
          templateLanguage = value;
        }
      }

      return (
        templateName: templateName,
        templateLanguage: templateLanguage,
      );
    } catch (error) {
      debugPrint(
        '⚠️ [WhatsAppService] Falling back to default WhatsApp template settings: $error',
      );
      return (
        templateName: option.defaultTemplateName,
        templateLanguage: option.defaultLanguage,
      );
    }
  }

  Future<WhatsAppSendReceipt> _sendViaCloud(
    Map<String, dynamic> body, {
    String? resolvedMessageText,
  }) async {
    final stopwatch = Stopwatch()..start();
    final metadata = body['metadata'];
    final clientMessageId =
        metadata is Map ? metadata['client_message_id']?.toString() : null;
    debugPrint(
      '⏱️ [WhatsAppService] cloud_invoke_start type=${body['type']} conversation=${body['conversationId']} client=$clientMessageId',
    );

    try {
      final response = await _client.functions.invoke(
        'whatsapp-send',
        body: body,
      );
      stopwatch.stop();

      final status = response.status;
      if (status >= 200 && status < 300) {
        if (!isDurableWhatsAppSendPayload(response.data)) {
          final externalMessageId = _extractExternalMessageId(response.data);
          debugPrint(
            '❌ [WhatsAppService] cloud_invoke_malformed_success status=$status elapsed=${stopwatch.elapsedMilliseconds}ms client=$clientMessageId data=${response.data}',
          );
          return WhatsAppSendReceipt(
            deliveryMethod: WhatsAppDeliveryMethod.failed,
            resolvedMessageText: resolvedMessageText,
            messageId: _extractMessageId(response.data),
            externalMessageId: externalMessageId,
            unsafeToFallback: true,
          );
        }
        final receipt = parseDurableWhatsAppSendReceipt(
          response.data,
          resolvedMessageText: resolvedMessageText,
        );
        debugPrint(
          '✅ [WhatsAppService] cloud_invoke_done status=$status elapsed=${stopwatch.elapsedMilliseconds}ms client=$clientMessageId external=${receipt.externalMessageId}',
        );
        return receipt;
      }

      final errorCode = _extractErrorCode(response.data);
      final externalMessageId = _extractExternalMessageId(response.data);
      final unsafeToFallback = _extractUnsafeToFallback(response.data);

      debugPrint(
        '❌ [WhatsAppService] cloud_invoke_failed status=$status elapsed=${stopwatch.elapsedMilliseconds}ms client=$clientMessageId error=$errorCode data=${response.data}',
      );
      return WhatsAppSendReceipt(
        deliveryMethod: WhatsAppDeliveryMethod.failed,
        errorCode: errorCode,
        resolvedMessageText: resolvedMessageText,
        messageId: _extractMessageId(response.data),
        externalMessageId: externalMessageId,
        unsafeToFallback: unsafeToFallback,
      );
    } on FunctionException catch (error) {
      stopwatch.stop();
      final data = error.details;
      final errorCode = _extractErrorCode(data);
      final externalMessageId = _extractExternalMessageId(data);
      final unsafeToFallback = _extractUnsafeToFallback(data);
      debugPrint(
        '❌ [WhatsAppService] cloud_invoke_failed status=${error.status} elapsed=${stopwatch.elapsedMilliseconds}ms client=$clientMessageId error=$errorCode',
      );
      return WhatsAppSendReceipt(
        deliveryMethod: WhatsAppDeliveryMethod.failed,
        errorCode: errorCode,
        resolvedMessageText: resolvedMessageText,
        messageId: _extractMessageId(data),
        externalMessageId: externalMessageId,
        unsafeToFallback: unsafeToFallback,
      );
    } catch (error) {
      stopwatch.stop();
      debugPrint(
        '❌ [WhatsAppService] cloud_invoke_error elapsed=${stopwatch.elapsedMilliseconds}ms client=$clientMessageId error=$error',
      );
      return WhatsAppSendReceipt(
        deliveryMethod: WhatsAppDeliveryMethod.failed,
        resolvedMessageText: resolvedMessageText,
        unsafeToFallback: true,
      );
    }
  }

  Future<WhatsAppSendReceipt> _sendWithFallback({
    BuildContext? context,
    required String phoneNumber,
    required String message,
    required Map<String, dynamic> cloudBody,
    bool allowManualFallback = true,
  }) async {
    final cloudReceipt = await _sendViaCloud(
      cloudBody,
      resolvedMessageText: message,
    );
    if (cloudReceipt.isSuccess) return cloudReceipt;

    if (!allowManualFallback || _shouldSkipManualFallback(cloudReceipt)) {
      return cloudReceipt;
    }

    if (context == null || !context.mounted) {
      return cloudReceipt;
    }
    final opened = await _openWhatsApp(context, phoneNumber, message);
    return cloudReceipt.copyWith(
      deliveryMethod: opened
          ? WhatsAppDeliveryMethod.manualFallback
          : WhatsAppDeliveryMethod.failed,
    );
  }

  /// Open WhatsApp with pre-filled message
  /// On desktop: Opens WhatsApp Web in WebView
  /// On mobile: Opens WhatsApp app
  Future<bool> _openWhatsApp(
    BuildContext context,
    String phoneNumber,
    String message,
  ) async {
    try {
      final formattedPhone = _formatPhoneNumber(phoneNumber);
      final encodedMessage = Uri.encodeComponent(message);
      final uri = Uri.parse(
        'https://wa.me/$formattedPhone?text=$encodedMessage',
      );

      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
        if (await canLaunchUrl(uri)) {
          return await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }

      // Open WhatsApp Web in WebView (desktop) or app (mobile)
      if (!context.mounted) return false;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => WhatsAppWebViewer(
            phoneNumber: formattedPhone,
            message: message,
          ),
        ),
      );

      return true;
    } catch (e) {
      debugPrint('❌ [WhatsAppService] Error opening WhatsApp WebView: $e');
      try {
        final formattedPhone = _formatPhoneNumber(phoneNumber);
        final encodedMessage = Uri.encodeComponent(message);
        final url = 'https://wa.me/$formattedPhone?text=$encodedMessage';

        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          return await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      } catch (fallbackError) {
        debugPrint('❌ [WhatsAppService] Fallback launch error: $fallbackError');
      }
      return false;
    }
  }

  /// Send invoice via WhatsApp
  Future<WhatsAppSendReceipt> sendInvoice({
    BuildContext? context,
    required String customerPhone,
    required String customerName,
    required Invoice invoice,
  }) async {
    final message = '''
Hola $customerName! 👋

Aquí está tu presupuesto de Viña Bike:

*Factura N° ${invoice.invoiceNumber}*
Fecha: ${_dateFormat.format(invoice.date)}

📦 *Productos/Servicios:*
${invoice.items.map((item) => '• ${item.productName ?? item.description}\n  Cantidad: ${item.quantity} × ${_currencyFormat.format(item.unitPrice)}\n  Subtotal: ${_currencyFormat.format(item.lineTotal)}').join('\n\n')}

💰 *Resumen:*
Subtotal: ${_currencyFormat.format(invoice.subtotal)}
${invoice.total - invoice.subtotal - invoice.ivaAmount > 0 ? 'Descuento: -${_currencyFormat.format(invoice.total - invoice.subtotal - invoice.ivaAmount)}\n' : ''}IVA (19%): ${_currencyFormat.format(invoice.ivaAmount)}
━━━━━━━━━━━━━━━
*TOTAL: ${_currencyFormat.format(invoice.total)}*

Por favor confirma para proceder con el trabajo. 🔧

¿Alguna duda? ¡Escríbenos! 📞
    ''';

    return _sendWithFallback(
      context: context,
      phoneNumber: customerPhone,
      message: message,
      cloudBody: {
        'phoneNumber': _formatPhoneNumber(customerPhone),
        'contactName': customerName,
        'contextType': 'invoice',
        'contextId': invoice.id,
        'type': 'text',
        'text': message,
        'metadata': {
          'source': 'flutter_erp',
          'invoiceId': invoice.id,
          'invoiceNumber': invoice.invoiceNumber,
        },
      },
    );
  }

  /// Send payment confirmation receipt
  Future<WhatsAppSendReceipt> sendPaymentReceipt({
    BuildContext? context,
    required String customerPhone,
    required String customerName,
    required Payment payment,
    required Invoice invoice,
    required String paymentMethodName,
  }) async {
    final message = '''
Hola $customerName! 👋

✅ *Pago Recibido - Viña Bike*

*Factura N° ${invoice.invoiceNumber}*
Fecha de pago: ${_dateFormat.format(payment.date)}

💵 *Detalles del Pago:*
Monto pagado: ${_currencyFormat.format(payment.amount)}
Método: $paymentMethodName
${payment.reference != null && payment.reference!.isNotEmpty ? 'Referencia: ${payment.reference}\n' : ''}
━━━━━━━━━━━━━━━

📊 *Estado de la Factura:*
Total factura: ${_currencyFormat.format(invoice.total)}
${invoice.paidAmount > 0 ? 'Pagado anteriormente: ${_currencyFormat.format(invoice.paidAmount - payment.amount)}\n' : ''}Pago actual: ${_currencyFormat.format(payment.amount)}
*Saldo restante: ${_currencyFormat.format(invoice.balance)}*

${invoice.balance <= 0 ? '🎉 ¡Factura pagada completamente!' : '⚠️ Saldo pendiente: ${_currencyFormat.format(invoice.balance)}'}

¡Gracias por tu confianza! 🚴‍♂️
    ''';

    return _sendWithFallback(
      context: context,
      phoneNumber: customerPhone,
      message: message,
      cloudBody: {
        'phoneNumber': _formatPhoneNumber(customerPhone),
        'contactName': customerName,
        'contextType': 'invoice',
        'contextId': invoice.id,
        'type': 'text',
        'text': message,
        'metadata': {
          'source': 'flutter_erp',
          'invoiceId': invoice.id,
          'invoiceNumber': invoice.invoiceNumber,
          'paymentId': payment.id,
        },
      },
    );
  }

  /// Send mechanic job status update
  Future<WhatsAppSendReceipt> sendJobStatusUpdate({
    BuildContext? context,
    required String customerPhone,
    required String customerName,
    required MechanicJob job,
    required String bikeBrand,
    required String? bikeModel,
  }) async {
    final statusEmoji = _getStatusEmoji(job.status);
    final statusText = job.status.displayName;

    final message = '''
Hola $customerName! 👋

$statusEmoji *Actualización de tu bicicleta*

🚴 Bici: $bikeBrand${bikeModel != null ? ' $bikeModel' : ''}
📋 Trabajo: ${job.clientRequest ?? job.diagnosis ?? 'Servicio'}
📅 Estado: *$statusText*

${_getStatusMessage(job.status)}

${job.deliveryDeadline != null ? '⏰ Fecha estimada: ${_dateFormat.format(job.deliveryDeadline!)}\n' : ''}${job.notes != null && job.notes!.isNotEmpty ? '📝 Notas: ${job.notes}\n' : ''}
¿Alguna duda? ¡Escríbenos! 📞

Viña Bike - Tu taller de confianza 🔧
    ''';

    return _sendWithFallback(
      context: context,
      phoneNumber: customerPhone,
      message: message,
      cloudBody: {
        'phoneNumber': _formatPhoneNumber(customerPhone),
        'contactName': customerName,
        'contextType': job.id != null ? 'job' : null,
        'contextId': job.id,
        'jobId': job.id,
        'type': 'text',
        'text': message,
        'metadata': {
          'source': 'flutter_erp',
          'jobId': job.id,
          'jobStatus': job.status.name,
        },
      },
    );
  }

  /// Send bike ready for pickup notification
  Future<WhatsAppSendReceipt> sendReadyForPickup({
    BuildContext? context,
    required String customerPhone,
    required String customerName,
    required MechanicJob job,
    required String bikeBrand,
    required String? bikeModel,
  }) async {
    final message = '''
Hola $customerName! 👋

🎉 *¡Tu bicicleta está lista!*

🚴 Bici: $bikeBrand${bikeModel != null ? ' $bikeModel' : ''}
📋 Trabajo realizado: ${job.clientRequest ?? job.diagnosis ?? 'Servicio'}

✅ El trabajo ha sido completado y tu bici está lista para retiro.

${job.invoiceId != null ? '💰 *Recuerda:* Debes pagar la factura antes de retirar.\n' : ''}
📍 *Ubicación:* Viña del Mar
⏰ *Horario:* Lunes a Viernes 9:00-18:00

🔧 *Garantía:* 1 semana de prueba incluida

¡Te esperamos! 🚴‍♂️

Viña Bike
    ''';

    return _sendWithFallback(
      context: context,
      phoneNumber: customerPhone,
      message: message,
      cloudBody: {
        'phoneNumber': _formatPhoneNumber(customerPhone),
        'contactName': customerName,
        'contextType': job.id != null ? 'job' : null,
        'contextId': job.id,
        'jobId': job.id,
        'type': 'interactive',
        'text': message,
        'caption': message,
        'actionType': 'confirm_delivery',
        'actionKind': 'job',
        'actionTargetId': job.id,
        'metadata': {
          'source': 'flutter_erp',
          'jobId': job.id,
          'jobStatus': job.status.name,
        },
      },
    );
  }

  /// Send generic message
  Future<WhatsAppSendReceipt> sendMessage({
    BuildContext? context,
    required String customerPhone,
    required String message,
    String? contactName,
    String? templateContactName,
    bool isSupplierConversation = false,
    String? conversationId,
    String? contextType,
    String? contextId,
    DateTime? lastInboundAt,
    String? clientMessageId,
    Map<String, dynamic>? metadata,
  }) async {
    final normalizedTemplateContact = templateContactName?.trim();
    final normalizedBindingContact = contactName?.trim();
    final customerDisplayName = isSupplierConversation
        ? normalizedTemplateContact ?? ''
        : normalizedTemplateContact?.isNotEmpty == true
            ? normalizedTemplateContact!
            : normalizedBindingContact?.isNotEmpty == true
                ? normalizedBindingContact!
                : 'cliente';

    if (!_isCustomerServiceWindowOpen(lastInboundAt)) {
      return isSupplierConversation
          ? sendSupplierReengagementTemplate(
              customerPhone: customerPhone,
              supplierContactName: customerDisplayName,
              bindingContactName: contactName,
              conversationId: conversationId,
              contextType: contextType,
              contextId: contextId,
              clientMessageId: clientMessageId,
            )
          : sendFirstContactTemplate(
              customerPhone: customerPhone,
              customerName: customerDisplayName,
              conversationId: conversationId,
              contextType: contextType,
              contextId: contextId,
              clientMessageId: clientMessageId,
            );
    }

    final cloudBody = {
      'conversationId': conversationId,
      'phoneNumber': _formatPhoneNumber(customerPhone),
      'contactName': contactName,
      'contextType': contextType,
      'contextId': contextId,
      'type': 'text',
      'text': message,
      'metadata': {
        'source': 'flutter_erp',
        ...?metadata,
        if (clientMessageId != null) 'client_message_id': clientMessageId,
      },
    };

    final cloudReceipt = await _sendViaCloud(
      cloudBody,
      resolvedMessageText: message,
    );
    if (cloudReceipt.isSuccess) return cloudReceipt;
    var failureReceipt = cloudReceipt;

    if (cloudReceipt.errorRequiresCustomerReply) {
      final templateReceipt = isSupplierConversation
          ? await sendSupplierReengagementTemplate(
              customerPhone: customerPhone,
              supplierContactName: customerDisplayName,
              bindingContactName: contactName,
              conversationId: conversationId,
              contextType: contextType,
              contextId: contextId,
              clientMessageId: clientMessageId,
            )
          : await sendFirstContactTemplate(
              customerPhone: customerPhone,
              customerName: customerDisplayName,
              conversationId: conversationId,
              contextType: contextType,
              contextId: contextId,
              clientMessageId: clientMessageId,
            );

      if (templateReceipt.isSuccess) return templateReceipt;
      failureReceipt = templateReceipt;
    }

    if (_shouldSkipManualFallback(failureReceipt)) {
      return failureReceipt;
    }

    if (context == null || !context.mounted) return failureReceipt;
    final opened = await _openWhatsApp(context, customerPhone, message);
    return failureReceipt.copyWith(
      deliveryMethod: opened
          ? WhatsAppDeliveryMethod.manualFallback
          : WhatsAppDeliveryMethod.failed,
    );
  }

  Future<WhatsAppSendReceipt> sendFirstContactTemplate({
    required String customerPhone,
    required String customerName,
    String? agentName,
    String? conversationId,
    String? contextType,
    String? contextId,
    String? clientMessageId,
  }) async {
    return sendTemplateMessage(
      option: customerTemplateOptions.first,
      customerPhone: customerPhone,
      customerName: customerName,
      agentName: agentName,
      conversationId: conversationId,
      contextType: contextType,
      contextId: contextId,
      clientMessageId: clientMessageId,
    );
  }

  Future<WhatsAppSendReceipt> sendSupplierReengagementTemplate({
    required String customerPhone,
    required String supplierContactName,
    String? bindingContactName,
    String? conversationId,
    String? contextType,
    String? contextId,
    String? clientMessageId,
  }) async {
    final receipt = await sendTemplateMessage(
      option: supplierTemplateOptions[2],
      customerPhone: customerPhone,
      customerName: supplierContactName,
      bindingContactName: bindingContactName,
      conversationId: conversationId,
      contextType: contextType,
      contextId: contextId,
      clientMessageId: clientMessageId,
    );
    return receipt.copyWith(usedFirstContactTemplate: receipt.isSuccess);
  }

  Future<WhatsAppSendReceipt> sendTemplateMessage({
    required WhatsAppTemplateOption option,
    required String customerPhone,
    required String customerName,
    String? agentName,
    String? bindingContactName,
    String? conversationId,
    String? contextType,
    String? contextId,
    String? clientMessageId,
  }) async {
    final templateSettings =
        option.purpose == WhatsAppTemplatePurpose.firstContact
            ? await _loadFirstContactTemplateSettings()
            : await _loadTemplateSettings(option);
    final businessName = await _resolveBusinessName();
    final renderedMessage = buildTemplatePreviewText(
      option: option,
      customerName: customerName,
      businessName: businessName,
      agentName: agentName,
    );
    final bodyParameters = option.bodyParameters(
      contactName: customerName,
      businessName: businessName,
      agentName: agentName,
    );

    final receipt = await _sendViaCloud({
      'conversationId': conversationId,
      'phoneNumber': _formatPhoneNumber(customerPhone),
      'contactName': bindingContactName ?? customerName,
      'contextType': contextType,
      'contextId': contextId,
      'type': 'template',
      'templateName': templateSettings.templateName,
      'templateLanguage': templateSettings.templateLanguage,
      if (option.category == WhatsAppMessageCategory.utility)
        'deliveryStrategy': 'direct_send_utility',
      'caption': renderedMessage,
      'templateComponents': [
        {
          'type': 'body',
          'parameters': bodyParameters
              .map(
                (value) => {
                  'type': 'text',
                  'text': value,
                },
              )
              .toList(growable: false),
        },
      ],
      'metadata': {
        'source': 'flutter_erp',
        if (clientMessageId != null) 'client_message_id': clientMessageId,
        'template_purpose': option.key,
        'template_name': templateSettings.templateName,
        'template_language': templateSettings.templateLanguage,
        'message_category': option.category.name,
      },
    }, resolvedMessageText: renderedMessage);

    return receipt.copyWith(
      usedFirstContactTemplate: receipt.isSuccess &&
          option.purpose == WhatsAppTemplatePurpose.firstContact,
    );
  }

  Future<WhatsAppSendReceipt> sendAttachment({
    BuildContext? context,
    required String customerPhone,
    required String attachmentId,
    required String filename,
    required String messageType,
    String? caption,
    String? contactName,
    String? conversationId,
    String? customerId,
    String? contextType,
    String? contextId,
    String? clientMessageId,
    Map<String, dynamic>? metadata,
  }) async {
    final isImage = messageType == 'image';
    final resolvedCaption = caption?.trim();
    final contentType = metadata?['contentType']?.toString() ??
        metadata?['content_type']?.toString();
    final fallbackMessage =
        resolvedCaption != null && resolvedCaption.isNotEmpty
            ? resolvedCaption
            : 'Te compartimos $filename.';

    return _sendWithFallback(
      context: context,
      phoneNumber: customerPhone,
      message: fallbackMessage,
      allowManualFallback: false,
      cloudBody: {
        'conversationId': conversationId,
        'customerId': customerId,
        'phoneNumber': _formatPhoneNumber(customerPhone),
        'contactName': contactName,
        'contextType': contextType,
        'contextId': contextId,
        'type': isImage ? 'image' : 'document',
        'attachmentId': attachmentId,
        if (!isImage) 'documentFilename': filename,
        if (contentType != null && contentType.isNotEmpty)
          'contentType': contentType,
        if (resolvedCaption != null && resolvedCaption.isNotEmpty)
          'caption': resolvedCaption,
        'metadata': {
          'source': 'flutter_erp',
          'filename': filename,
          if (clientMessageId != null) 'client_message_id': clientMessageId,
          ...?metadata,
        },
      },
    );
  }

  Future<WhatsAppSendReceipt> sendInteractiveAction({
    BuildContext? context,
    required String customerPhone,
    required String customerName,
    required String conversationId,
    required String actionType,
    required String actionKind,
    required String actionTargetId,
    required String message,
    String? customerId,
    String? contextType,
    String? contextId,
    String? jobId,
    double? amount,
    bool markQuoteSent = false,
    Map<String, dynamic>? metadata,
    String? documentUrl,
    String? documentFilename,
  }) async {
    return _sendWithFallback(
      context: context,
      phoneNumber: customerPhone,
      message: message,
      cloudBody: {
        'conversationId': conversationId,
        'customerId': customerId,
        'phoneNumber': _formatPhoneNumber(customerPhone),
        'contactName': customerName,
        'contextType': contextType,
        'contextId': contextId,
        'jobId': jobId,
        'type': 'interactive',
        'text': message,
        'caption': message,
        'actionType': actionType,
        'actionKind': actionKind,
        'actionTargetId': actionTargetId,
        'amount': amount,
        'markQuoteSent': markQuoteSent,
        if (documentUrl != null) 'documentUrl': documentUrl,
        if (documentFilename != null) 'documentFilename': documentFilename,
        'metadata': {
          'source': 'flutter_erp',
          ...?metadata,
        },
      },
    );
  }

  // Helper methods for status formatting
  String _getStatusEmoji(JobStatus status) {
    switch (status) {
      case JobStatus.pendiente:
        return '⏳';
      case JobStatus.diagnostico:
        return '🔍';
      case JobStatus.esperandoAprobacion:
        return '⏰';
      case JobStatus.esperandoRepuestos:
        return '📦';
      case JobStatus.enCurso:
        return '🔧';
      case JobStatus.finalizado:
        return '✅';
      case JobStatus.entregado:
        return '🎉';
      case JobStatus.cancelado:
        return '❌';
    }
  }

  String _getStatusMessage(JobStatus status) {
    switch (status) {
      case JobStatus.pendiente:
        return 'Estamos revisando los detalles de tu solicitud.';
      case JobStatus.diagnostico:
        return 'Estamos realizando el diagnóstico de tu bicicleta.';
      case JobStatus.esperandoAprobacion:
        return 'El diagnóstico está completo. Esperamos tu aprobación para continuar.';
      case JobStatus.esperandoRepuestos:
        return 'Estamos esperando que lleguen los repuestos necesarios.';
      case JobStatus.enCurso:
        return 'El trabajo está en progreso. Te avisaremos cuando esté listo.';
      case JobStatus.finalizado:
        return 'El trabajo ha sido completado. Estamos realizando las pruebas finales.';
      case JobStatus.entregado:
        return '¡Gracias por confiar en nosotros! Recuerda: tienes 1 semana de garantía para probar tu bici.';
      case JobStatus.cancelado:
        return 'El trabajo ha sido cancelado.';
    }
  }
}
