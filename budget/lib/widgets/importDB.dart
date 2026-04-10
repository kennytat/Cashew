import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/struct/sync/sync_crypto.dart';
import 'package:budget/widgets/globalSnackbar.dart';
import 'package:budget/widgets/openPopup.dart';
import 'package:budget/widgets/openSnackbar.dart';
import 'package:budget/widgets/settingsContainers.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';

Future<String?> importDBFileFromDevice(BuildContext context) async {
  // Avoid using a file filter: PlatformException(FilePicker, Unsupported filter....
  FilePickerResult? result = await FilePicker.platform.pickFiles();
  if (result == null) {
    openSnackbar(SnackbarMessage(
      title: "error-importing".tr(),
      description: "no-file-selected".tr(),
      icon: appStateSettings["outlinedIcons"]
          ? Icons.warning_outlined
          : Icons.warning_rounded,
    ));
    return null;
  }

  String fileName = result.files.single.name;

  // Read file bytes.
  Uint8List fileBytes;
  if (kIsWeb) {
    fileBytes = result.files.single.bytes!;
  } else {
    File file = File(result.files.single.path ?? "");
    fileBytes = await file.readAsBytes();
  }

  // Prompt for optional passphrase to decrypt.
  String? passphrase = await _askForPassphrase(context, fileName);
  // null means user cancelled the dialog.
  if (passphrase == null) return null;

  if (passphrase.isNotEmpty) {
    // Decrypt the file before restoring.
    try {
      fileBytes = SyncCrypto.decryptAndDecompress(fileBytes, passphrase);
    } catch (e) {
      openSnackbar(SnackbarMessage(
        title: "Decryption failed",
        description: "Wrong passphrase or file is not encrypted",
        icon: appStateSettings["outlinedIcons"]
            ? Icons.error_outlined
            : Icons.error_rounded,
      ));
      return null;
    }
  } else {
    // No passphrase — warn if file doesn't look like a plain SQLite/SQL file.
    if (!fileName.endsWith('.sql') && !fileName.endsWith('.sqlite')) {
      openSnackbar(SnackbarMessage(
        title: "import-warning".tr(),
        description: "import-warning-description".tr(),
        icon: appStateSettings["outlinedIcons"]
            ? Icons.warning_outlined
            : Icons.warning_rounded,
      ));
    }
  }

  await overwriteDefaultDB(fileBytes);
  await resetLanguageToSystem(context);
  await updateSettings("databaseJustImported", true,
      pagesNeedingRefresh: [], updateGlobalState: false);
  return fileName;
}

/// Shows a dialog asking for an optional passphrase.
/// Returns empty string if user skips, the passphrase if entered, or null if cancelled.
Future<String?> _askForPassphrase(
    BuildContext context, String fileName) async {
  final controller = TextEditingController();
  bool obscure = true;

  final result = await openPopup(
    context,
    icon: fileName.endsWith('.enc')
        ? Icons.lock_rounded
        : Icons.file_open_rounded,
    title: "Restore backup",
    descriptionWidget: Material(
      color: Colors.transparent,
      child: StatefulBuilder(
      builder: (context, setState) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              fileName.endsWith('.enc')
                  ? "This file appears to be encrypted. Enter the passphrase to decrypt it."
                  : "If this file is encrypted, enter the passphrase below. Leave blank for plain backups.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withOpacity(0.7),
              ),
            ),
            SizedBox(height: 14),
            TextField(
              controller: controller,
              obscureText: obscure,
              autofocus: fileName.endsWith('.enc'),
              decoration: InputDecoration(
                labelText: "Passphrase (optional)",
                prefixIcon: Icon(Icons.key_rounded),
                suffixIcon: IconButton(
                  icon: Icon(
                      obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                  onPressed: () => setState(() => obscure = !obscure),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        );
      },
    )),
    onSubmitLabel: "Restore",
    onCancelLabel: "cancel".tr(),
    onSubmit: () {
      popRoute(context, "restore");
    },
    onCancel: () {
      popRoute(context, null);
    },
  );

  if (result == "restore") {
    return controller.text.trim();
  }
  return null; // cancelled
}

Future importDB(BuildContext context, {ignoreOverwriteWarning = false}) async {
  dynamic result = ignoreOverwriteWarning == true
      ? true
      : await openPopup(
          context,
          icon: appStateSettings["outlinedIcons"]
              ? Icons.warning_outlined
              : Icons.warning_rounded,
          title: "data-overwrite-warning".tr(),
          description: "data-overwrite-warning-description".tr(),
          onCancel: () {
            popRoute(context, false);
          },
          onCancelLabel: "cancel".tr(),
          onSubmit: () {
            popRoute(context, true);
          },
          onSubmitLabel: "ok".tr(),
        );
  if (result == true) {
    await openLoadingPopupTryCatch(
      () async {
        return await importDBFileFromDevice(context);
      },
      onSuccess: (result) {
        if (result != null)
          restartAppPopup(
            context,
            description: kIsWeb
                ? "refresh-required-to-load-backup".tr()
                : "restart-required-to-load-backup".tr(),
          );
      },
    );
  }
}

class ImportDB extends StatelessWidget {
  const ImportDB({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsContainer(
      onTap: () async {
        await importDB(context);
      },
      title: "import-data-file".tr(),
      icon: appStateSettings["outlinedIcons"]
          ? Icons.download_outlined
          : Icons.download_rounded,
    );
  }
}
