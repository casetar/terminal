import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:math';

class KeyStorageService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static String _generateId() {
    final rng = Random.secure();
    return List.generate(12, (_) => rng.nextInt(36).toRadixString(36)).join();
  }

  /// Save SSH private key, returns generated key ID
  static Future<String> saveKey({
    required String label,
    required String privateKey,
    String? passphrase,
  }) async {
    final id = _generateId();
    await _storage.write(key: 'key_${id}_label', value: label);
    await _storage.write(key: 'key_${id}_pem', value: privateKey);
    if (passphrase != null && passphrase.isNotEmpty) {
      await _storage.write(key: 'key_${id}_pass', value: passphrase);
    }
    // Track key IDs
    final existing = await _storage.read(key: 'key_ids') ?? '';
    final ids = existing.isEmpty ? <String>[] : existing.split(',');
    ids.add(id);
    await _storage.write(key: 'key_ids', value: ids.join(','));
    return id;
  }

  /// Save password for a host
  static Future<void> savePassword(String hostId, String password) async {
    await _storage.write(key: 'pwd_$hostId', value: password);
  }

  static Future<String?> getPassword(String hostId) async {
    return _storage.read(key: 'pwd_$hostId');
  }

  static Future<String?> getKeyPem(String keyId) async {
    return _storage.read(key: 'key_${keyId}_pem');
  }

  static Future<String?> getKeyPassphrase(String keyId) async {
    return _storage.read(key: 'key_${keyId}_pass');
  }

  static Future<String?> getKeyLabel(String keyId) async {
    return _storage.read(key: 'key_${keyId}_label');
  }

  static Future<List<Map<String, String>>> getAllKeys() async {
    final idsStr = await _storage.read(key: 'key_ids') ?? '';
    if (idsStr.isEmpty) return [];
    final ids = idsStr.split(',');
    final result = <Map<String, String>>[];
    for (final id in ids) {
      final label = await _storage.read(key: 'key_${id}_label') ?? id;
      result.add({'id': id, 'label': label});
    }
    return result;
  }

  static Future<void> deleteKey(String keyId) async {
    await _storage.delete(key: 'key_${keyId}_label');
    await _storage.delete(key: 'key_${keyId}_pem');
    await _storage.delete(key: 'key_${keyId}_pass');
    final idsStr = await _storage.read(key: 'key_ids') ?? '';
    final ids = idsStr.split(',')..remove(keyId);
    await _storage.write(key: 'key_ids', value: ids.join(','));
  }

  static Future<void> seedDefaultKey() async {
    const defaultId = 'default_rsa_savun';
    final existingIdsStr = await _storage.read(key: 'key_ids') ?? '';
    final existingIds = existingIdsStr.isEmpty ? <String>[] : existingIdsStr.split(',');

    if (!existingIds.contains(defaultId)) {
      await _storage.write(key: 'key_${defaultId}_label', value: 'rsa_savun');
      await _storage.write(key: 'key_${defaultId}_pem', value: '''-----BEGIN RSA PRIVATE KEY-----
MIIEowIBAAKCAQEA4fF+tVvR6JvzUYIgn3j7Ppu2Fdhp+4SKa+JcGmsuPwsjMgjA
bMPRaK7sau4/DWzwI6onjlFI32oLL+xQ5bis3m8belmuWX4X/OphIww+RH+TAxXz
3pUPpOwZR177K0qNh8+Tb5F32W8gHyaENb0sD/JSUgrHZDy+4dsKWVbmcP1/IcNj
2JIQRNLq8yeypcoOs1xYjbPcJ4xu0yi3FXGPZqCqsbc+MVfhLpYLGAA0G8rk1hX5
6Kzsn1rkoepHkUHahnD5SiVYgsRlYBrIP88Prc0oMIBVDMpxjUBCHt29PPekdpE9
cGj5QHBFbOvq2BGbVwtUkjZLlJjYPZa1LZOrKQIDAQABAoIBAQDJhVCDR3soYfga
adrZAdntVIqKX3Tfva6MXN/TPGeKGU/x73ZZTCo5mVMKaKbaPaDN3pTbTcqWYgnK
W5cn3Zhp6GV0sgpcjaetkArFbMUY6URhSzIxA3hpm59MVf3l9d/YEx8oMnHYAFKB
FiRznd9v9azQugZvc/K4lVpcprJwcSva0ClWPk4YNv6byoR9AbMBi0JsoQUNPRUM
wpbLlJ425daVlKpuaP3Q+11QI+s0dr8znDjRXg2G0wmEZ2i0G8NeXjTUlrQ5pKov
AlOS6W303Owi9ZNk+5KDb6qdnf/m4nuGPTwt4CzYS0OxUHnyEdpmMPFpb4iuLHwp
BhP5XXuRAoGBAPUvFhkKxyAiYaHzmKcxDU/IM+eoptGgMY6dCpDxSMfMsNqTuvaV
1Um8G16PHkVG8mwlVjnmjhuzGW4zwnwdyaeNZs2aQDZYnywqcjxqoVsw3F+cq7fP
QAzS7GPfQoD/7KLgZO0N0Ps9l6huL/KaUImrJ8KqzblJzcyF80d17SMlAoGBAOvp
Ht8rXBtRwloh1TaY1mAEKO1hbwOOJ+jIbr59IzbRlEXpvYLsnAXaMP/PcghxCzS/
knM5CD6Caohrcd7fTBuTlGcWnI5F8XCjmw32XNa2lu+wDKmh1nFc5+XhfsCo/4Vo
taxtEXGbtxQtuNvqggOZgZ4qRZmV4EWssDnKguq1AoGAfqv0C74QwJ5iuKxEyuRB
z11My7vLa/QKhnbGFbpC8s7i9Bps9qbUigLAVSs15W7RImRr1wAxnUf7tH7TVRKC
s6kPWtv9ntZMbiID4QjqElX9FPy5jv5pRfbXIIYhMsqGNGQgYITJ2nOo3eEHrpxh
Ta76nM1n+fmSdL8jwGDBwm0CgYA+3jQ88vgry6EIlgWU9CwFEHa7tAB6qRKXpXpl
x0FwJW/nJcA8OMPnh1sRgP35o+6Bkx/7FtLMncK4MjH5W/aTTsP4qPz1qUwLYX47
vVDGY4hbvcXSGu/j7Adcqrg1rZPSwLHRjotchEvI09p0uM0HGoyBUvCTWm6XAss/
y2kSFQKBgH4EqvObL+NkZva7Ww8RljGR5uaJ9UJoqOb4rUGqVDJP4126ki6ODnvH
S2dgVo2HZJ6AQzZZcBKHqc9ilbIPYfrU+vtN4pPPzM0diGCza8pO9U7y9ERFYarC
IHA4WCVsozUbpP+sLX74dQ8wrVHrEWcoatATUmrsVjBl7g623Ufp
-----END RSA PRIVATE KEY-----''');
      existingIds.add(defaultId);
      await _storage.write(key: 'key_ids', value: existingIds.join(','));
    }
  }
}
