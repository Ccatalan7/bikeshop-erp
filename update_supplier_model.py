import re

with open('lib/shared/models/supplier.dart', 'r') as f:
    content = f.read()

fields = """  final String? imageUrl;
  final String? portalUsername;
  final String? portalPassword;
  final String? salesRepName;
  final String? salesRepPhone;
  final String? salesRepEmail;
  final String? purchaseInstructions;"""

content = re.sub(r'  final String\? notes;', f"{fields}\n  final String? notes;", content)

constructor_fields = """    this.imageUrl,
    this.portalUsername,
    this.portalPassword,
    this.salesRepName,
    this.salesRepPhone,
    this.salesRepEmail,
    this.purchaseInstructions,"""

content = re.sub(r'    this\.notes,', f"{constructor_fields}\n    this.notes,", content)

json_fields = """      imageUrl: json['image_url'] as String?,
      portalUsername: json['portal_username'] as String?,
      portalPassword: json['portal_password'] as String?,
      salesRepName: json['sales_rep_name'] as String?,
      salesRepPhone: json['sales_rep_phone'] as String?,
      salesRepEmail: json['sales_rep_email'] as String?,
      purchaseInstructions: json['purchase_instructions'] as String?,"""

content = re.sub(r"      notes: json\['notes'\] as String\?,", f"{json_fields}\n      notes: json['notes'] as String?,", content)

to_json_fields = """      'image_url': imageUrl,
      'portal_username': portalUsername,
      'portal_password': portalPassword,
      'sales_rep_name': salesRepName,
      'sales_rep_phone': salesRepPhone,
      'sales_rep_email': salesRepEmail,
      'purchase_instructions': purchaseInstructions,"""

content = re.sub(r"      'notes': notes,", f"{to_json_fields}\n      'notes': notes,", content)

copy_with_args = """    String? imageUrl,
    String? portalUsername,
    String? portalPassword,
    String? salesRepName,
    String? salesRepPhone,
    String? salesRepEmail,
    String? purchaseInstructions,"""

content = re.sub(r"    String\? notes,", f"{copy_with_args}\n    String? notes,", content)

copy_with_fields = """      imageUrl: imageUrl ?? this.imageUrl,
      portalUsername: portalUsername ?? this.portalUsername,
      portalPassword: portalPassword ?? this.portalPassword,
      salesRepName: salesRepName ?? this.salesRepName,
      salesRepPhone: salesRepPhone ?? this.salesRepPhone,
      salesRepEmail: salesRepEmail ?? this.salesRepEmail,
      purchaseInstructions: purchaseInstructions ?? this.purchaseInstructions,"""

content = re.sub(r"      notes: notes \?\? this\.notes,", f"{copy_with_fields}\n      notes: notes ?? this.notes,", content)

with open('lib/shared/models/supplier.dart', 'w') as f:
    f.write(content)
