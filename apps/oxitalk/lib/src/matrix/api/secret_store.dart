/// Where the session and the store passphrase are kept: the platform's secure storage in the
/// app, memory in tests.
abstract interface class SecretStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}
