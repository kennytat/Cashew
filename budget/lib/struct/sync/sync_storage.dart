import 'package:budget/struct/sync/sync_crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SyncSecureStorage {
  static const _passphraseKey = 'cashew_sync_passphrase';
  static final _storage = FlutterSecureStorage(
    mOptions: MacOsOptions(useDataProtectionKeyChain: false),
  );

  // In-memory cache (never persisted in plaintext).
  static String? _cachedBackupId;

  static Future<void> savePassphrase(String passphrase) async {
    await _storage.write(key: _passphraseKey, value: passphrase);
    _cachedBackupId = SyncCrypto.deriveBackupId(passphrase);
  }

  static Future<String?> loadPassphrase() async {
    return await _storage.read(key: _passphraseKey);
  }

  static Future<String?> getBackupId() async {
    if (_cachedBackupId != null) return _cachedBackupId;
    final passphrase = await loadPassphrase();
    if (passphrase == null) return null;
    _cachedBackupId = SyncCrypto.deriveBackupId(passphrase);
    return _cachedBackupId;
  }

  static Future<String?> getPassphraseForCrypto() async {
    return await loadPassphrase();
  }

  static Future<void> clearAll() async {
    await _storage.delete(key: _passphraseKey);
    _cachedBackupId = null;
  }
}
