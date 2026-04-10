import 'package:budget/functions.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/struct/sync/sync_client.dart';
import 'package:budget/struct/sync/sync_crypto.dart';
import 'package:budget/struct/sync/sync_models.dart';
import 'package:budget/struct/sync/sync_service.dart';
import 'package:budget/struct/sync/sync_storage.dart';
import 'package:budget/widgets/framework/pageFramework.dart';
import 'package:budget/widgets/openPopup.dart';
import 'package:budget/widgets/openSnackbar.dart';
import 'package:budget/widgets/globalSnackbar.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

class SyncSetupPage extends StatefulWidget {
  const SyncSetupPage({Key? key}) : super(key: key);

  @override
  State<SyncSetupPage> createState() => _SyncSetupPageState();
}

class _SyncSetupPageState extends State<SyncSetupPage> {
  final _passphraseController = TextEditingController();
  final _serverUrlController = TextEditingController();
  bool _obscurePassphrase = true;
  bool _isConnecting = false;
  bool _isSyncEnabled = false;
  String? _lastSyncedDisplay;

  @override
  void initState() {
    super.initState();
    _isSyncEnabled = appStateSettings["syncEnabled"] == true;
    _serverUrlController.text = appStateSettings["syncServerUrl"] ?? "";
    _loadState();
  }

  Future<void> _loadState() async {
    final passphrase = await SyncSecureStorage.loadPassphrase();
    if (passphrase != null && mounted) {
      setState(() {
        _passphraseController.text = passphrase;
      });
    }
    _updateLastSyncedDisplay();
  }

  void _updateLastSyncedDisplay() {
    final lastSynced = appStateSettings["lastSynced"];
    if (lastSynced != null && mounted) {
      try {
        final dt = DateTime.parse(lastSynced.toString());
        setState(() {
          _lastSyncedDisplay = getTimeAgo(dt);
        });
      } catch (_) {}
    }
  }

  Future<void> _connect() async {
    final passphrase = _passphraseController.text.trim();
    final serverUrl = _serverUrlController.text.trim();

    if (passphrase.isEmpty) {
      openSnackbar(SnackbarMessage(
        title: "Please enter a passphrase",
        icon: Icons.warning_rounded,
      ));
      return;
    }
    if (passphrase.length < 6) {
      openSnackbar(SnackbarMessage(
        title: "Passphrase too short",
        description: "Use at least 6 characters",
        icon: Icons.warning_rounded,
      ));
      return;
    }
    if (serverUrl.isEmpty) {
      openSnackbar(SnackbarMessage(
        title: "Please enter a server URL",
        icon: Icons.warning_rounded,
      ));
      return;
    }

    setState(() => _isConnecting = true);

    try {
      // Save server URL first so SyncClient can use it.
      await updateSettings("syncServerUrl", serverUrl,
          pagesNeedingRefresh: [], updateGlobalState: true);

      final backupId = SyncCrypto.deriveBackupId(passphrase);
      final client = SyncClient();
      final meta = await client.fetchMeta(backupId);

      // Save passphrase to secure storage.
      await SyncSecureStorage.savePassphrase(passphrase);

      if (meta.exists) {
        // Server has an existing backup — ask user what to do.
        if (!mounted) return;
        final choice = await openPopup(
          context,
          icon: Icons.cloud_download_rounded,
          title: "Backup found on server",
          description:
              "A backup already exists. Download it (replaces local data) or upload your current data (replaces server data)?",
          onSubmitLabel: "Download",
          onExtraLabel: "Upload",
          onCancelLabel: "cancel".tr(),
          onSubmit: () => popRoute(context, "download"),
          onExtra: () => popRoute(context, "upload"),
          onCancel: () => popRoute(context, null),
        );

        if (choice == "download") {
          await _enableSyncAndRun(doDownload: true);
        } else if (choice == "upload") {
          await _enableSyncAndRun(doDownload: false);
        }
        // If cancelled, credentials are saved but sync not enabled yet.
      } else {
        // No backup on server — upload current DB.
        await _enableSyncAndRun(doDownload: false);
      }
    } on SyncException catch (e) {
      openSnackbar(SnackbarMessage(
        title: "Connection failed",
        description: e.message,
        icon: Icons.error_rounded,
      ));
    } catch (e) {
      openSnackbar(SnackbarMessage(
        title: "Connection failed",
        description: e.toString(),
        icon: Icons.error_rounded,
      ));
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  Future<void> _enableSyncAndRun({required bool doDownload}) async {
    await updateSettings("syncEnabled", true,
        pagesNeedingRefresh: [], updateGlobalState: true);

    if (mounted) setState(() => _isSyncEnabled = true);

    final syncService = SyncService.instance;
    SyncResult result;
    if (doDownload) {
      // New device joining existing backup — reset initial sync flag so
      // syncOnOpen downloads the remote backup instead of uploading.
      await syncService.resetInitialSync();
      result = await syncService.syncOnOpen();
    } else {
      // Uploading local DB — mark initial sync as done immediately.
      await syncService.markInitialSyncCompleted();
      result = await syncService.syncOnClose();
    }

    if (result == SyncResult.downloaded && mounted) {
      restartAppPopup(context,
          description: "Database synced from server. Restart required.");
    } else if (result == SyncResult.uploaded) {
      openSnackbar(SnackbarMessage(
        title: "Sync enabled",
        description: "Database uploaded to server",
        icon: Icons.cloud_done_rounded,
      ));
    } else if (result == SyncResult.error) {
      openSnackbar(SnackbarMessage(
        title: "Sync error",
        description: "Could not complete sync",
        icon: Icons.error_rounded,
      ));
    }

    await updateSettings("lastSynced", DateTime.now().toString(),
        pagesNeedingRefresh: [], updateGlobalState: false);
    _updateLastSyncedDisplay();
  }

  Future<void> _disconnect() async {
    final confirmed = await openPopup(
      context,
      icon: Icons.link_off_rounded,
      title: "Disconnect sync?",
      description:
          "This will disable sync and remove stored credentials. Your local data will not be deleted.",
      onSubmitLabel: "Disconnect",
      onCancelLabel: "cancel".tr(),
      onSubmit: () => popRoute(context, true),
      onCancel: () => popRoute(context, false),
    );
    if (confirmed == true) {
      await SyncSecureStorage.clearAll();
      await SyncService.instance.resetInitialSync();
      await updateSettings("syncEnabled", false,
          pagesNeedingRefresh: [], updateGlobalState: true);
      await updateSettings("syncServerUrl", "",
          pagesNeedingRefresh: [], updateGlobalState: true);
      if (mounted) {
        setState(() {
          _isSyncEnabled = false;
          _passphraseController.clear();
          _serverUrlController.clear();
          _lastSyncedDisplay = null;
        });
      }
      openSnackbar(SnackbarMessage(
        title: "Sync disconnected",
        icon: Icons.cloud_off_rounded,
      ));
    }
  }

  Future<void> _syncNow() async {
    setState(() => _isConnecting = true);
    try {
      final result = await SyncService.instance.syncOnOpen();
      if (result == SyncResult.downloaded && mounted) {
        restartAppPopup(context,
            description: "Database synced from server. Restart required.");
      } else if (result == SyncResult.uploaded) {
        openSnackbar(SnackbarMessage(
          title: "Sync complete",
          description: "Database uploaded",
          icon: Icons.cloud_done_rounded,
        ));
      } else if (result == SyncResult.noAction) {
        openSnackbar(SnackbarMessage(
          title: "Already up to date",
          icon: Icons.check_circle_rounded,
        ));
      } else if (result == SyncResult.offline) {
        openSnackbar(SnackbarMessage(
          title: "No connection",
          description: "Sync will retry later",
          icon: Icons.wifi_off_rounded,
        ));
      }
      await updateSettings("lastSynced", DateTime.now().toString(),
          pagesNeedingRefresh: [], updateGlobalState: false);
      _updateLastSyncedDisplay();
    } catch (e) {
      openSnackbar(SnackbarMessage(
        title: "Sync failed",
        description: e.toString(),
        icon: Icons.error_rounded,
      ));
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  @override
  void dispose() {
    _passphraseController.dispose();
    _serverUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PageFramework(
      horizontalPaddingConstrained: true,
      dragDownToDismiss: true,
      title: "Cloud Sync",
      listWidgets: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          child: TextFont(
            text: _isSyncEnabled
                ? "Sync is enabled. Your data is encrypted end-to-end."
                : "Set up sync to backup your database to a server. Data is encrypted with your passphrase before leaving this device.",
            fontSize: 14,
            maxLines: 5,
            textColor: Theme.of(context)
                .colorScheme
                .onSurface
                .withOpacity(0.6),
          ),
        ),
        if (_isSyncEnabled && _lastSyncedDisplay != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
            child: TextFont(
              text: "Last synced: $_lastSyncedDisplay",
              fontSize: 13,
              textColor: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withOpacity(0.5),
            ),
          ),
        SizedBox(height: 8),

        // Server URL
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
          child: TextField(
            controller: _serverUrlController,
            enabled: !_isSyncEnabled,
            decoration: InputDecoration(
              labelText: "Server URL",
              hintText: "https://sync.example.com",
              prefixIcon: Icon(Icons.dns_rounded),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            keyboardType: TextInputType.url,
          ),
        ),

        // Passphrase
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
          child: TextField(
            controller: _passphraseController,
            enabled: !_isSyncEnabled,
            obscureText: _obscurePassphrase,
            decoration: InputDecoration(
              labelText: "Passphrase",
              hintText: "Enter a strong passphrase",
              prefixIcon: Icon(Icons.key_rounded),
              suffixIcon: IconButton(
                icon: Icon(_obscurePassphrase
                    ? Icons.visibility_rounded
                    : Icons.visibility_off_rounded),
                onPressed: () {
                  setState(
                      () => _obscurePassphrase = !_obscurePassphrase);
                },
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),

        SizedBox(height: 12),

        // Connect / Sync Now / Disconnect buttons
        if (!_isSyncEnabled)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
            child: ElevatedButton.icon(
              onPressed: _isConnecting ? null : _connect,
              icon: _isConnecting
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(Icons.cloud_rounded),
              label: Text(_isConnecting ? "Connecting..." : "Connect"),
              style: ElevatedButton.styleFrom(
                minimumSize: Size(double.infinity, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),

        if (_isSyncEnabled) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
            child: ElevatedButton.icon(
              onPressed: _isConnecting ? null : _syncNow,
              icon: _isConnecting
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(Icons.sync_rounded),
              label: Text(_isConnecting ? "Syncing..." : "Sync now"),
              style: ElevatedButton.styleFrom(
                minimumSize: Size(double.infinity, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
            child: OutlinedButton.icon(
              onPressed: _disconnect,
              icon: Icon(Icons.link_off_rounded),
              label: Text("Disconnect"),
              style: OutlinedButton.styleFrom(
                minimumSize: Size(double.infinity, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],

        SizedBox(height: 16),

        // Info section
        if (!_isSyncEnabled)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            child: Container(
              padding: EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .secondaryContainer
                    .withOpacity(0.4),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFont(
                    text: "How it works",
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    maxLines: 1,
                  ),
                  SizedBox(height: 6),
                  TextFont(
                    text:
                        "Your passphrase is used to derive an encryption key and a backup identifier. The server only stores encrypted data and cannot read your financial information.",
                    fontSize: 13,
                    maxLines: 10,
                    textColor: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.6),
                  ),
                  SizedBox(height: 6),
                  TextFont(
                    text:
                        "Sync happens automatically when the app opens and closes. Use the same passphrase on all devices to keep them in sync.",
                    fontSize: 13,
                    maxLines: 10,
                    textColor: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.6),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
