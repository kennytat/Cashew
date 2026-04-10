import 'dart:typed_data';

import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/struct/sync/sync_crypto.dart';
import 'package:budget/widgets/exportCSV.dart';
import 'package:budget/widgets/openPopup.dart';
import 'package:budget/widgets/settingsContainers.dart';
import 'package:budget/widgets/util/saveFile.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'dart:async';

Future saveDBFileToDevice({
  required BuildContext boxContext,
  required String fileName,
  String? customDirectory,
  String? passphrase,
}) async {
  try {
    await backupSettings();
  } catch (e) {
    print("Error creating settings entry in the db: " + e.toString());
  }

  DBFileInfo currentDBFileInfo = await getCurrentDBFileInfo();

  List<int> dataStore = [];
  await for (var data in currentDBFileInfo.mediaStream) {
    dataStore.insertAll(dataStore.length, data);
  }

  // Encrypt if passphrase provided.
  if (passphrase != null && passphrase.isNotEmpty) {
    dataStore = SyncCrypto.compressAndEncrypt(
      Uint8List.fromList(dataStore),
      passphrase,
    ).toList();
  }

  return await saveFile(
    boxContext: boxContext,
    dataStore: dataStore,
    dataString: null,
    fileName: fileName,
    successMessage: "backup-saved-success".tr(),
    errorMessage: "error-saving".tr(),
  );
}

/// Ask for optional passphrase before export.
/// Returns the passphrase string (empty if skipped), or null if cancelled.
Future<String?> _askExportPassphrase(BuildContext context) async {
  final controller = TextEditingController();
  bool obscure = true;

  final result = await openPopup(
    context,
    icon: Icons.upload_rounded,
    title: "export-data-file".tr(),
    descriptionWidget: Material(
      color: Colors.transparent,
      child: StatefulBuilder(
      builder: (context, setState) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Enter a passphrase to encrypt the backup file. Leave blank to export without encryption.",
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
              decoration: InputDecoration(
                labelText: "Passphrase (optional)",
                prefixIcon: Icon(Icons.key_rounded),
                suffixIcon: IconButton(
                  icon: Icon(obscure
                      ? Icons.visibility_rounded
                      : Icons.visibility_off_rounded),
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
    onSubmitLabel: "Export",
    onCancelLabel: "cancel".tr(),
    onSubmit: () {
      popRoute(context, "export");
    },
    onCancel: () {
      popRoute(context, null);
    },
  );

  if (result == "export") {
    return controller.text.trim();
  }
  return null;
}

Future exportDB({required BuildContext boxContext}) async {
  final passphrase = await _askExportPassphrase(boxContext);
  if (passphrase == null) return; // cancelled

  await openLoadingPopupTryCatch(() async {
    final encrypted = passphrase.isNotEmpty;
    final ext = encrypted ? ".enc" : ".sql";
    String fileName =
        "cashew-" + cleanFileNameString(DateTime.now().toString()) + ext;
    await saveDBFileToDevice(
      boxContext: boxContext,
      fileName: fileName,
      passphrase: passphrase,
    );
  });
}

class ExportDB extends StatelessWidget {
  const ExportDB({super.key});

  @override
  Widget build(BuildContext context) {
    return Builder(builder: (boxContext) {
      return SettingsContainer(
        onTap: () async {
          await exportDB(boxContext: boxContext);
        },
        title: "export-data-file".tr(),
        icon: appStateSettings["outlinedIcons"]
            ? Icons.upload_outlined
            : Icons.upload_rounded,
      );
    });
  }
}
