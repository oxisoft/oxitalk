import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../matrix/api/secret_store.dart';

/// Keychain (iOS, macOS), Keystore (Android), libsecret (Linux), DPAPI (Windows).
final class SecureSecretStore implements SecretStore {
  const SecureSecretStore();

  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}
