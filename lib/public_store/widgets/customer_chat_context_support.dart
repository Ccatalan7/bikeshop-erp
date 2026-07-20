/// Customer account context readers are intentionally narrower than employee
/// readers. A type must not be advertised until it has a customer-authorized,
/// read-only projection.
abstract final class CustomerChatContextSupport {
  static const supportedTypes = <String>{'job', 'invoice'};

  static bool supports(String? rawType) {
    final type = rawType?.trim().toLowerCase();
    return type != null && supportedTypes.contains(type);
  }
}
