import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;

class SyncCrypto {
  // Different salts so backupId (visible to server) cannot derive the key.
  static const _backupIdSalt = 'cashew_backup_salt_v1';
  static const _encryptionKeySalt = 'cashew_encryption_key_v1';

  /// Derive a 64-char hex backupId from the passphrase.
  static String deriveBackupId(String passphrase) {
    final bytes = utf8.encode(_backupIdSalt + passphrase);
    return sha256.convert(bytes).toString(); // 64 hex chars
  }

  /// Derive a 32-byte AES-256 encryption key from the passphrase.
  static Uint8List deriveEncryptionKey(String passphrase) {
    final bytes = utf8.encode(_encryptionKeySalt + passphrase);
    return Uint8List.fromList(sha256.convert(bytes).bytes);
  }

  /// Compress with gzip, then encrypt with AES-256-GCM.
  /// Output format: [12-byte IV][ciphertext+GCM tag]
  static Uint8List compressAndEncrypt(Uint8List plaintext, String passphrase) {
    final compressed = GZipCodec().encode(plaintext);
    final key = deriveEncryptionKey(passphrase);

    final iv = encrypt.IV.fromSecureRandom(12);
    final encrypter = encrypt.Encrypter(
      encrypt.AES(encrypt.Key(key), mode: encrypt.AESMode.gcm),
    );
    final encrypted = encrypter.encryptBytes(compressed, iv: iv);

    // Prepend IV to ciphertext.
    final result = Uint8List(12 + encrypted.bytes.length);
    result.setRange(0, 12, iv.bytes);
    result.setRange(12, result.length, encrypted.bytes);
    return result;
  }

  /// Decrypt with AES-256-GCM, then decompress gzip.
  static Uint8List decryptAndDecompress(Uint8List blob, String passphrase) {
    if (blob.length < 13) {
      throw FormatException('Encrypted blob too short');
    }

    final key = deriveEncryptionKey(passphrase);
    final iv = encrypt.IV(blob.sublist(0, 12));
    final ciphertext = blob.sublist(12);

    final encrypter = encrypt.Encrypter(
      encrypt.AES(encrypt.Key(key), mode: encrypt.AESMode.gcm),
    );
    final decrypted = encrypter.decryptBytes(
      encrypt.Encrypted(ciphertext),
      iv: iv,
    );

    return Uint8List.fromList(GZipCodec().decode(decrypted));
  }
}
