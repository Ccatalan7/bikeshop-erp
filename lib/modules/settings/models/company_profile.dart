import '../../../shared/utils/chilean_utils.dart';

class CompanyProfile {
  final String? id;
  final String? tenantId;
  final String name;
  final String legalName;
  final String fantasyName;
  final String taxId;
  final String businessActivity;
  final String address;
  final String comuna;
  final String city;
  final String region;
  final String postalCode;
  final String country;
  final String phone;
  final String whatsappPhone;
  final String whatsappApiPhone;
  final String supportPhone;
  final String email;
  final String billingEmail;
  final String publicEmail;
  final String websiteUrl;
  final bool isDefault;
  final Map<String, dynamic> metadata;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const CompanyProfile({
    this.id,
    this.tenantId,
    required this.name,
    required this.legalName,
    required this.fantasyName,
    required this.taxId,
    required this.businessActivity,
    required this.address,
    required this.comuna,
    required this.city,
    required this.region,
    required this.postalCode,
    required this.country,
    required this.phone,
    required this.whatsappPhone,
    required this.whatsappApiPhone,
    required this.supportPhone,
    required this.email,
    required this.billingEmail,
    required this.publicEmail,
    required this.websiteUrl,
    this.isDefault = true,
    this.metadata = const {},
    this.createdAt,
    this.updatedAt,
  });

  factory CompanyProfile.vinabikeDefault({
    String? tenantId,
    String email = 'vinabikechile@gmail.com',
  }) {
    return CompanyProfile(
      tenantId: tenantId,
      name: 'Viñabike',
      legalName: 'NEWEN SpA',
      fantasyName: 'Viñabike',
      taxId: '77.541.999-7',
      businessActivity:
          'Venta al por menor de bicicletas y sus repuestos en comercios especializados',
      address: '',
      comuna: '',
      city: '',
      region: '',
      postalCode: '',
      country: 'Chile',
      phone: '+56 9 9835 7797',
      whatsappPhone: '+56 9 9835 7797',
      whatsappApiPhone: '+56 9 4188 4520',
      supportPhone: '',
      email: email,
      billingEmail: email,
      publicEmail: email,
      websiteUrl: '',
      isDefault: true,
    );
  }

  factory CompanyProfile.fromMap(Map<String, dynamic> map) {
    return CompanyProfile(
      id: map['id'] as String?,
      tenantId: map['tenant_id'] as String?,
      name: _readString(map['name']),
      legalName: _readString(map['legal_name']),
      fantasyName: _readString(map['fantasy_name']),
      taxId: _readString(map['tax_id'], fallback: _readString(map['rut'])),
      businessActivity: _readString(map['business_activity']),
      address: _readString(map['address']),
      comuna: _readString(map['comuna']),
      city: _readString(map['city']),
      region: _readString(map['region']),
      postalCode: _readString(map['postal_code']),
      country: _readString(map['country'], fallback: 'Chile'),
      phone: _readString(map['phone']),
      whatsappPhone: _readString(map['whatsapp_phone']),
      whatsappApiPhone: _readString(map['whatsapp_api_phone']),
      supportPhone: _readString(map['support_phone']),
      email: _readString(map['email']),
      billingEmail: _readString(map['billing_email']),
      publicEmail: _readString(map['public_email']),
      websiteUrl: _readString(map['website_url']),
      isDefault: map['is_default'] == true,
      metadata: _readMetadata(map['metadata']),
      createdAt: _readDate(map['created_at']),
      updatedAt: _readDate(map['updated_at']),
    );
  }

  Map<String, dynamic> toDatabaseMap({required String tenantId}) {
    return {
      'tenant_id': tenantId,
      'name': name.trim(),
      'legal_name': legalName.trim(),
      'fantasy_name': fantasyName.trim(),
      'tax_id': taxId.trim(),
      'rut': taxId.trim(),
      'business_activity': businessActivity.trim(),
      'address': address.trim(),
      'comuna': comuna.trim(),
      'city': city.trim(),
      'region': region.trim(),
      'postal_code': postalCode.trim(),
      'country': country.trim().isEmpty ? 'Chile' : country.trim(),
      'phone': phone.trim(),
      'whatsapp_phone': whatsappPhone.trim(),
      'whatsapp_api_phone': whatsappApiPhone.trim(),
      'support_phone': supportPhone.trim(),
      'email': email.trim(),
      'billing_email': billingEmail.trim(),
      'public_email': publicEmail.trim(),
      'website_url': websiteUrl.trim(),
      'is_default': isDefault,
      'metadata': metadata,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  CompanyProfile copyWith({
    String? id,
    String? tenantId,
    String? name,
    String? legalName,
    String? fantasyName,
    String? taxId,
    String? businessActivity,
    String? address,
    String? comuna,
    String? city,
    String? region,
    String? postalCode,
    String? country,
    String? phone,
    String? whatsappPhone,
    String? whatsappApiPhone,
    String? supportPhone,
    String? email,
    String? billingEmail,
    String? publicEmail,
    String? websiteUrl,
    bool? isDefault,
    Map<String, dynamic>? metadata,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CompanyProfile(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      name: name ?? this.name,
      legalName: legalName ?? this.legalName,
      fantasyName: fantasyName ?? this.fantasyName,
      taxId: taxId ?? this.taxId,
      businessActivity: businessActivity ?? this.businessActivity,
      address: address ?? this.address,
      comuna: comuna ?? this.comuna,
      city: city ?? this.city,
      region: region ?? this.region,
      postalCode: postalCode ?? this.postalCode,
      country: country ?? this.country,
      phone: phone ?? this.phone,
      whatsappPhone: whatsappPhone ?? this.whatsappPhone,
      whatsappApiPhone: whatsappApiPhone ?? this.whatsappApiPhone,
      supportPhone: supportPhone ?? this.supportPhone,
      email: email ?? this.email,
      billingEmail: billingEmail ?? this.billingEmail,
      publicEmail: publicEmail ?? this.publicEmail,
      websiteUrl: websiteUrl ?? this.websiteUrl,
      isDefault: isDefault ?? this.isDefault,
      metadata: metadata ?? this.metadata,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  String get displayName {
    final fantasy = fantasyName.trim();
    if (fantasy.isNotEmpty) return fantasy;
    final publicName = name.trim();
    if (publicName.isNotEmpty) return publicName;
    return legalName.trim();
  }

  String get formattedTaxId {
    final value = taxId.trim();
    if (value.isEmpty) return '';
    return ChileanUtils.formatRut(value).toUpperCase();
  }

  String get primaryEmail {
    if (publicEmail.trim().isNotEmpty) return publicEmail.trim();
    if (email.trim().isNotEmpty) return email.trim();
    return billingEmail.trim();
  }

  String get primaryPhone {
    if (phone.trim().isNotEmpty) return phone.trim();
    if (whatsappPhone.trim().isNotEmpty) return whatsappPhone.trim();
    return supportPhone.trim();
  }

  String get fullAddress {
    final parts = [
      address,
      comuna,
      city,
      region,
      country,
    ].map((part) => part.trim()).where((part) => part.isNotEmpty).toList();
    return parts.join(', ');
  }

  static String _readString(dynamic value, {String fallback = ''}) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return fallback;
    return text;
  }

  static Map<String, dynamic> _readMetadata(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, data) => MapEntry(key.toString(), data));
    }
    return const {};
  }

  static DateTime? _readDate(dynamic value) {
    final text = value?.toString();
    if (text == null || text.isEmpty) return null;
    return DateTime.tryParse(text);
  }
}

class CompanyBankAccount {
  static const List<String> accountTypes = [
    'Cuenta corriente',
    'Cuenta vista',
    'Cuenta de ahorro',
    'Cuenta RUT',
    'Otro',
  ];

  static const List<String> chileanBanks = [
    'Banco de Chile',
    'BancoEstado',
    'Santander',
    'BCI',
    'Itaú',
    'Scotiabank',
    'BICE',
    'Security',
    'Banco Falabella',
    'Banco Ripley',
    'Consorcio',
    'Banco Internacional',
    'Otro',
  ];

  final String? id;
  final String? tenantId;
  final String? companyId;
  final String label;
  final String bankName;
  final String accountType;
  final String accountNumber;
  final String holderName;
  final String holderRut;
  final String contactEmail;
  final String currency;
  final bool isDefault;
  final bool isActive;
  final String notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const CompanyBankAccount({
    this.id,
    this.tenantId,
    this.companyId,
    required this.label,
    required this.bankName,
    required this.accountType,
    required this.accountNumber,
    required this.holderName,
    required this.holderRut,
    required this.contactEmail,
    this.currency = 'CLP',
    this.isDefault = false,
    this.isActive = true,
    this.notes = '',
    this.createdAt,
    this.updatedAt,
  });

  factory CompanyBankAccount.empty({
    String? tenantId,
    String? companyId,
    required int index,
    required CompanyProfile company,
    bool isDefault = false,
  }) {
    return CompanyBankAccount(
      tenantId: tenantId,
      companyId: companyId,
      label: index == 1 ? 'Cuenta principal' : 'Cuenta $index',
      bankName: 'Banco de Chile',
      accountType: 'Cuenta corriente',
      accountNumber: '',
      holderName:
          company.legalName.isNotEmpty ? company.legalName : company.name,
      holderRut: company.formattedTaxId,
      contactEmail: company.billingEmail.isNotEmpty
          ? company.billingEmail
          : company.primaryEmail,
      isDefault: isDefault,
    );
  }

  factory CompanyBankAccount.fromMap(Map<String, dynamic> map) {
    return CompanyBankAccount(
      id: map['id'] as String?,
      tenantId: map['tenant_id'] as String?,
      companyId: map['company_id'] as String?,
      label: _readString(map['label']),
      bankName: _readString(map['bank_name']),
      accountType: _readString(
        map['account_type'],
        fallback: 'Cuenta corriente',
      ),
      accountNumber: _readString(map['account_number']),
      holderName: _readString(map['account_holder_name']),
      holderRut: _readString(map['account_holder_rut']),
      contactEmail: _readString(map['contact_email']),
      currency: _readString(map['currency'], fallback: 'CLP'),
      isDefault: map['is_default'] == true,
      isActive: map['is_active'] != false,
      notes: _readString(map['notes']),
      createdAt: _readDate(map['created_at']),
      updatedAt: _readDate(map['updated_at']),
    );
  }

  Map<String, dynamic> toDatabaseMap({
    required String tenantId,
    required String companyId,
  }) {
    return {
      'tenant_id': tenantId,
      'company_id': companyId,
      'label': label.trim(),
      'bank_name': bankName.trim(),
      'account_type': accountType.trim(),
      'account_number': accountNumber.trim(),
      'account_holder_name': holderName.trim(),
      'account_holder_rut': holderRut.trim(),
      'contact_email': contactEmail.trim(),
      'currency': currency.trim().isEmpty ? 'CLP' : currency.trim(),
      'is_default': isDefault,
      'is_active': isActive,
      'notes': notes.trim(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  CompanyBankAccount copyWith({
    String? id,
    String? tenantId,
    String? companyId,
    String? label,
    String? bankName,
    String? accountType,
    String? accountNumber,
    String? holderName,
    String? holderRut,
    String? contactEmail,
    String? currency,
    bool? isDefault,
    bool? isActive,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CompanyBankAccount(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      companyId: companyId ?? this.companyId,
      label: label ?? this.label,
      bankName: bankName ?? this.bankName,
      accountType: accountType ?? this.accountType,
      accountNumber: accountNumber ?? this.accountNumber,
      holderName: holderName ?? this.holderName,
      holderRut: holderRut ?? this.holderRut,
      contactEmail: contactEmail ?? this.contactEmail,
      currency: currency ?? this.currency,
      isDefault: isDefault ?? this.isDefault,
      isActive: isActive ?? this.isActive,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  String get displayLabel {
    final trimmedLabel = label.trim();
    if (trimmedLabel.isNotEmpty) return trimmedLabel;
    final trimmedBank = bankName.trim();
    if (trimmedBank.isNotEmpty) return trimmedBank;
    return 'Cuenta bancaria';
  }

  String get maskedAccountNumber {
    final digits = accountNumber.replaceAll(RegExp(r'\s+'), '');
    if (digits.length <= 4) return accountNumber;
    return '•••• ${digits.substring(digits.length - 4)}';
  }

  static String _readString(dynamic value, {String fallback = ''}) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return fallback;
    return text;
  }

  static DateTime? _readDate(dynamic value) {
    final text = value?.toString();
    if (text == null || text.isEmpty) return null;
    return DateTime.tryParse(text);
  }
}
