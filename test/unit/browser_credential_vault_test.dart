import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/browser_credential_vault.dart';

void main() {
  test('vault stores credentials by ERP user and exact HTTPS origin', () async {
    final store = _MemorySecureStore();
    final vault = BrowserCredentialVault(store: store);

    await vault.save(
      userId: 'erp-user-a',
      origin: 'https://supplier.example/login?ignored=yes',
      username: 'buyer@example.com',
      password: 'secret-a',
    );

    final saved = await vault.load(
      userId: 'erp-user-a',
      origin: 'https://supplier.example/another-page',
    );
    expect(saved?.origin, 'https://supplier.example');
    expect(saved?.username, 'buyer@example.com');
    expect(saved?.password, 'secret-a');
    expect(
      await vault.load(
        userId: 'erp-user-b',
        origin: 'https://supplier.example',
      ),
      isNull,
    );
    expect(
      await vault.load(
        userId: 'erp-user-a',
        origin: 'https://other.example',
      ),
      isNull,
    );
    expect(store.values.keys.join(' '), isNot(contains('secret-a')));
    expect(store.values.keys.join(' '), isNot(contains('buyer@example.com')));
  });

  test('vault refuses insecure, anonymous, or empty credentials', () async {
    final store = _MemorySecureStore();
    final vault = BrowserCredentialVault(store: store);

    await vault.save(
      userId: 'erp-user',
      origin: 'http://supplier.example',
      username: 'buyer',
      password: 'secret',
    );
    await vault.save(
      userId: 'anonymous',
      origin: 'https://supplier.example',
      username: 'buyer',
      password: 'secret',
    );
    await vault.save(
      userId: 'erp-user',
      origin: 'https://supplier.example',
      username: '',
      password: 'secret',
    );

    expect(store.values, isEmpty);
  });

  test('delete and clear stay scoped to the active ERP user', () async {
    final store = _MemorySecureStore();
    final vault = BrowserCredentialVault(store: store);

    for (final origin in [
      'https://one.example',
      'https://two.example',
    ]) {
      await vault.save(
        userId: 'erp-user-a',
        origin: origin,
        username: 'buyer-a',
        password: 'secret-a',
      );
    }
    await vault.save(
      userId: 'erp-user-b',
      origin: 'https://one.example',
      username: 'buyer-b',
      password: 'secret-b',
    );

    await vault.delete(
      userId: 'erp-user-a',
      origin: 'https://one.example',
    );
    expect(
      await vault.load(
        userId: 'erp-user-a',
        origin: 'https://one.example',
      ),
      isNull,
    );
    expect(
      await vault.load(
        userId: 'erp-user-a',
        origin: 'https://two.example',
      ),
      isNotNull,
    );

    await vault.clearUser('erp-user-a');
    expect(
      await vault.load(
        userId: 'erp-user-a',
        origin: 'https://two.example',
      ),
      isNull,
    );
    expect(
      (await vault.load(
        userId: 'erp-user-b',
        origin: 'https://one.example',
      ))
          ?.username,
      'buyer-b',
    );
  });
}

class _MemorySecureStore implements BrowserCredentialSecureStore {
  final Map<String, String> values = {};

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}
