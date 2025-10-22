import 'package:intl/intl.dart';

class ChileanUtils {
  // Chilean Peso formatting
  static final NumberFormat _clpFormat = NumberFormat.currency(
    locale: 'es_CL',
    symbol: '\$',
    decimalDigits: 0,
  );

  // Date formatting for Chile (DD/MM/YYYY)
  static final DateFormat _dateFormat = DateFormat('dd/MM/yyyy');
  static final DateFormat _dateTimeFormat = DateFormat('dd/MM/yyyy HH:mm');

  // Public getters for formatters
  static DateFormat get dateFormat => _dateFormat;
  static NumberFormat get currencyFormat => _clpFormat;

  // IVA (VAT) rate for Chile
  static const double ivaRate = 0.19; // 19%

  // Format currency in Chilean Pesos
  static String formatCurrency(double amount) {
    return _clpFormat.format(amount);
  }

  // Format date in Chilean format
  static String formatDate(DateTime date) {
    return _dateFormat.format(date);
  }

  // Format datetime in Chilean format
  static String formatDateTime(DateTime dateTime) {
    return _dateTimeFormat.format(dateTime);
  }

  // Parse Chilean date format
  static DateTime? parseDate(String dateString) {
    try {
      return _dateFormat.parse(dateString);
    } catch (e) {
      return null;
    }
  }

  // Calculate IVA amount
  static double calculateIva(double netAmount) {
    return netAmount * ivaRate;
  }

  // Calculate total with IVA
  static double calculateTotalWithIva(double netAmount) {
    return netAmount * (1 + ivaRate);
  }

  // Calculate net amount from total (remove IVA)
  static double calculateNetFromTotal(double totalAmount) {
    return totalAmount / (1 + ivaRate);
  }

  // Validate Chilean RUT (accepts nullable String)
  static bool isValidRut(String? rut) {
    if (rut == null || rut.isEmpty) return false;

    // Remove dots and hyphens
    String cleanRut = rut.replaceAll(RegExp(r'[.-]'), '');

    if (cleanRut.length < 8 || cleanRut.length > 9) return false;

    // Extract number and check digit
    String rutNumber = cleanRut.substring(0, cleanRut.length - 1);
    String checkDigit = cleanRut.substring(cleanRut.length - 1).toLowerCase();

    // Validate that number part contains only digits
    if (!RegExp(r'^\d+$').hasMatch(rutNumber)) return false;

    // Calculate check digit
    String calculatedCheckDigit = _calculateRutCheckDigit(rutNumber);

    return checkDigit == calculatedCheckDigit;
  }

  // Calculate RUT check digit
  static String _calculateRutCheckDigit(String rutNumber) {
    int sum = 0;
    int multiplier = 2;

    for (int i = rutNumber.length - 1; i >= 0; i--) {
      sum += int.parse(rutNumber[i]) * multiplier;
      multiplier = multiplier == 7 ? 2 : multiplier + 1;
    }

    int remainder = 11 - (sum % 11);

    if (remainder == 11) return '0';
    if (remainder == 10) return 'k';
    return remainder.toString();
  }

  // Format RUT for display (accepts nullable String)
  static String formatRut(String? rut) {
    if (rut == null || rut.isEmpty) return '';

    // Remove existing formatting
    String cleanRut = rut.replaceAll(RegExp(r'[.-]'), '');

    if (cleanRut.length < 8) return rut;

    // Insert dots and hyphen
    String number = cleanRut.substring(0, cleanRut.length - 1);
    String checkDigit = cleanRut.substring(cleanRut.length - 1);

    // Add dots every 3 digits from right
    String formattedNumber = '';
    for (int i = 0; i < number.length; i++) {
      if (i > 0 && (number.length - i) % 3 == 0) {
        formattedNumber += '.';
      }
      formattedNumber += number[i];
    }

    return '$formattedNumber-$checkDigit';
  }

  // Account types for accounting classification
  static Map<String, String> getAccountTypes() {
    return {
      'asset': 'Activo',
      'liability': 'Pasivo',
      'equity': 'Patrimonio',
      'income': 'Ingresos',
      'expense': 'Gastos',
      'tax': 'Impuestos',
    };
  }

  // Chilean regions for address selection
  static List<String> getChileanRegions() {
    return [
      'Arica y Parinacota',
      'Tarapacá',
      'Antofagasta',
      'Atacama',
      'Coquimbo',
      'Valparaíso',
      'Metropolitana de Santiago',
      'Libertador General Bernardo O\'Higgins',
      'Maule',
      'Ñuble',
      'Biobío',
      'La Araucanía',
      'Los Ríos',
      'Los Lagos',
      'Aysén del General Carlos Ibáñez del Campo',
      'Magallanes y de la Antártica Chilena',
    ];
  }

  // Email validation
  static bool isValidEmail(String email) {
    final emailRegex =
        RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
    return emailRegex.hasMatch(email);
  }

  // Chilean phone number validation
  static bool isValidChileanPhone(String phone) {
    // Remove spaces, hyphens, and parentheses
    final cleanPhone = phone.replaceAll(RegExp(r'[\s\-\(\)]'), '');

    // Chilean mobile: +569 XXXX XXXX or 9 XXXX XXXX
    // Chilean landline: +56 2 XXXX XXXX or 2 XXXX XXXX
    final mobileRegex = RegExp(r'^(\+569|9)[0-9]{8}$');
    final landlineRegex = RegExp(r'^(\+562|2)[0-9]{8}$');

    return mobileRegex.hasMatch(cleanPhone) ||
        landlineRegex.hasMatch(cleanPhone);
  }
}
