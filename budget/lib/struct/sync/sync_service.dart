import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:budget/database/tables.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/struct/sync/sync_client.dart';
import 'package:budget/struct/sync/sync_crypto.dart';
import 'package:budget/struct/sync/sync_models.dart';
import 'package:budget/struct/sync/sync_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class SyncService {
  static final SyncService instance = SyncService._();
  SyncService._();

  final SyncClient _client = SyncClient();
  bool _isSyncing = false;

  bool get isSyncing => _isSyncing;

  /// Whether sync is fully configured and enabled.
  bool get isConfigured {
    return appStateSettings["syncEnabled"] == true &&
        (appStateSettings["syncServerUrl"] ?? "").toString().isNotEmpty;
  }

  /// Get the local DB file's last modification time.
  Future<DateTime> _getLocalLastModified() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final dbFile = File(p.join(dbFolder.path, 'db.sqlite'));
    if (await dbFile.exists()) {
      return (await dbFile.stat()).modified.toUtc();
    }
    return DateTime.now().toUtc();
  }

  /// Read the raw DB file bytes.
  Future<Uint8List> _getDbBytes() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final dbFile = File(p.join(dbFolder.path, 'db.sqlite'));
    return await dbFile.readAsBytes();
  }

  /// Save a pre-sync backup before overwriting the DB.
  Future<void> _savePreSyncBackup() async {
    try {
      final dbFolder = await getApplicationDocumentsDirectory();
      final dbFile = File(p.join(dbFolder.path, 'db.sqlite'));
      final backupFile =
          File(p.join(dbFolder.path, 'db_pre_sync_backup.sqlite'));
      if (await dbFile.exists()) {
        await dbFile.copy(backupFile.path);
      }
    } catch (e) {
      print("Warning: could not save pre-sync backup: $e");
    }
  }

  /// Sync on app open: check server, download if remote newer, upload if local newer.
  Future<SyncResult> syncOnOpen() async {
    if (!isConfigured) return SyncResult.notConfigured;
    if (_isSyncing) return SyncResult.noAction;
    _isSyncing = true;

    try {
      final backupId = await SyncSecureStorage.getBackupId();
      final passphrase = await SyncSecureStorage.getPassphraseForCrypto();
      if (backupId == null || passphrase == null) {
        return SyncResult.notConfigured;
      }

      // If a previous sync-on-close failed, retry upload first.
      if (hasPendingUpload) {
        final localTime = await _getLocalLastModified();
        try {
          final result = await _doUpload(backupId, passphrase, localTime);
          if (result == SyncResult.uploaded) {
            return result;
          }
        } catch (_) {
          // Pending upload failed again — continue with normal sync flow.
        }
      }

      // Fetch remote metadata.
      SyncMeta meta;
      try {
        meta = await _client.fetchMeta(backupId);
      } on SocketException {
        return SyncResult.offline;
      } on TimeoutException {
        return SyncResult.offline;
      }

      final localLastModified = await _getLocalLastModified();

      // No remote backup exists — upload local.
      if (!meta.exists || meta.lastModified == null) {
        return await _doUpload(backupId, passphrase, localLastModified);
      }

      final remoteTime = meta.lastModified!;

      // Remote is newer — download.
      if (remoteTime.isAfter(localLastModified.add(Duration(seconds: 1)))) {
        return await _doDownload(backupId, passphrase);
      }

      // Local is newer — upload.
      if (localLastModified.isAfter(remoteTime.add(Duration(seconds: 1)))) {
        return await _doUpload(backupId, passphrase, localLastModified);
      }

      // Within 1 second tolerance — no action.
      return SyncResult.noAction;
    } on SyncException catch (e) {
      print("Sync error: $e");
      return SyncResult.error;
    } catch (e) {
      print("Sync unexpected error: $e");
      return SyncResult.error;
    } finally {
      _isSyncing = false;
    }
  }

  /// Sync on app close: always upload current DB.
  Future<SyncResult> syncOnClose() async {
    if (!isConfigured) return SyncResult.notConfigured;
    if (_isSyncing) return SyncResult.noAction;
    _isSyncing = true;

    try {
      final backupId = await SyncSecureStorage.getBackupId();
      final passphrase = await SyncSecureStorage.getPassphraseForCrypto();
      if (backupId == null || passphrase == null) {
        return SyncResult.notConfigured;
      }

      // Backup settings into DB before exporting.
      try {
        await backupSettings();
      } catch (e) {
        print("Warning: could not backup settings before sync: $e");
      }

      final localLastModified = await _getLocalLastModified();
      return await _doUpload(backupId, passphrase, localLastModified);
    } on SocketException {
      // Network unavailable on close — mark pending for next open.
      await _setPendingUpload(true);
      return SyncResult.offline;
    } on TimeoutException {
      await _setPendingUpload(true);
      return SyncResult.offline;
    } catch (e) {
      print("Sync close error: $e");
      await _setPendingUpload(true);
      return SyncResult.error;
    } finally {
      _isSyncing = false;
    }
  }

  Future<SyncResult> _doUpload(
      String backupId, String passphrase, DateTime timestamp) async {
    try {
      await backupSettings();
    } catch (_) {}

    final dbBytes = await _getDbBytes();
    final encrypted = SyncCrypto.compressAndEncrypt(dbBytes, passphrase);
    final accepted = await _client.upload(backupId, encrypted, timestamp);

    if (accepted) {
      await _setPendingUpload(false);
      return SyncResult.uploaded;
    }
    // 409 — server has newer. Could trigger download, but for simplicity
    // return noAction and let the next syncOnOpen handle it.
    return SyncResult.noAction;
  }

  Future<SyncResult> _doDownload(String backupId, String passphrase) async {
    final data = await _client.download(backupId);
    if (data == null) return SyncResult.noAction;

    // Decrypt and decompress.
    final dbBytes = SyncCrypto.decryptAndDecompress(data, passphrase);

    // Save pre-sync backup before overwriting.
    await _savePreSyncBackup();

    // Overwrite local database.
    await overwriteDefaultDB(dbBytes);

    // Mark that settings need to be restored from the imported DB.
    await updateSettings("databaseJustImported", true,
        pagesNeedingRefresh: [], updateGlobalState: false);

    return SyncResult.downloaded;
  }

  Future<void> _setPendingUpload(bool pending) async {
    await updateSettings("pendingSyncUpload", pending,
        pagesNeedingRefresh: [], updateGlobalState: false);
  }

  bool get hasPendingUpload =>
      appStateSettings["pendingSyncUpload"] == true;
}
