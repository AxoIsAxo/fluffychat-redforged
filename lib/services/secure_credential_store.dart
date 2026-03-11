import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:matrix/matrix.dart';

/// Centralized service for securely storing and retrieving
/// login credentials and recovery keys on the device.
class SecureCredentialStore {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  // Key prefixes
  static const String _recoveryKeyPrefix = 'ssss_recovery_key_';
  static const String _autoUnlockPrefix = 'auto_unlock_ssss_';

  // --- Recovery Key ---

  /// Store the recovery key for a given user.
  static Future<void> storeRecoveryKey(String userId, String key) async {
    await _storage.write(key: '$_recoveryKeyPrefix$userId', value: key);
  }

  /// Read the stored recovery key for a given user.
  static Future<String?> readRecoveryKey(String userId) async {
    return _storage.read(key: '$_recoveryKeyPrefix$userId');
  }

  /// Delete the stored recovery key for a given user.
  static Future<void> deleteRecoveryKey(String userId) async {
    await _storage.delete(key: '$_recoveryKeyPrefix$userId');
  }

  /// Check if a recovery key is stored for a given user.
  static Future<bool> hasRecoveryKey(String userId) async {
    final key = await _storage.read(key: '$_recoveryKeyPrefix$userId');
    return key != null && key.isNotEmpty;
  }

  // --- Auto-Unlock SSSS ---

  /// Set the auto-unlock SSSS preference for a given user.
  static Future<void> setAutoUnlockSsss(String userId, bool enabled) async {
    await _storage.write(
      key: '$_autoUnlockPrefix$userId',
      value: enabled.toString(),
    );
  }

  /// Check if auto-unlock SSSS is enabled for a given user.
  static Future<bool> isAutoUnlockSsssEnabled(String userId) async {
    final value = await _storage.read(key: '$_autoUnlockPrefix$userId');
    return value == 'true';
  }

  // --- Auto-Unlock Logic ---

  /// Try to auto-unlock SSSS using the stored recovery key.
  /// Returns true if successful, false otherwise.
  static Future<bool> tryAutoUnlockSsss(Client client) async {
    try {
      final userId = client.userID;
      if (userId == null) return false;
      if (client.encryption == null) return false;

      final autoUnlock = await isAutoUnlockSsssEnabled(userId);
      if (!autoUnlock) return false;

      final recoveryKey = await readRecoveryKey(userId);
      if (recoveryKey == null || recoveryKey.isEmpty) return false;

      // Check if key manager is already cached (already unlocked)
      if (await client.encryption!.keyManager.isCached()) {
        Logs().v('[SecureCredentialStore] SSSS already unlocked');
        return true;
      }

      // Check if SSSS has any keys configured before trying to open
      final ssss = client.encryption!.ssss;
      if (ssss.defaultKeyId == null) {
        Logs().v('[SecureCredentialStore] No default SSSS key, skipping');
        return false;
      }

      // Try to unlock with the stored recovery key
      Logs().i('[SecureCredentialStore] Attempting auto-unlock of SSSS...');
      final openSsss = ssss.open();
      await openSsss.unlock(keyOrPassphrase: recoveryKey);
      await openSsss.maybeCacheAll();

      // Try to self-sign with cross-signing
      if (client.encryption!.crossSigning.enabled) {
        try {
          await client.encryption!.crossSigning.selfSign(
            recoveryKey: recoveryKey,
          );
          Logs().i('[SecureCredentialStore] Cross-signing self-sign successful');
        } catch (e) {
          Logs().w('[SecureCredentialStore] Cross-signing self-sign failed', e);
        }
      }

      Logs().i('[SecureCredentialStore] Auto-unlock SSSS successful');
      return true;
    } catch (e, s) {
      Logs().w('[SecureCredentialStore] Auto-unlock SSSS failed', e, s);
      return false;
    }
  }

  // --- Cleanup ---

  /// Clear all stored credentials for a given user.
  static Future<void> clearAll(String userId) async {
    await deleteRecoveryKey(userId);
    await _storage.delete(key: '$_autoUnlockPrefix$userId');
  }
}
