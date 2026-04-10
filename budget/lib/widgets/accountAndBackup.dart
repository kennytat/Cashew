import 'package:budget/functions.dart';
import 'package:budget/pages/syncSetupPage.dart';
import 'package:budget/widgets/exportCSV.dart';
import 'package:budget/widgets/exportDB.dart';
import 'package:budget/widgets/importDB.dart';
import 'package:budget/widgets/moreIcons.dart';
import 'package:budget/widgets/settingsContainers.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

// 包装函数，用于导出到CSV
Future<void> exportToCSV(BuildContext context) async {
  final exportCSV = ExportCSV();
  await exportCSV.exportCSV(
    boxContext: context,
    dateTimeRange: null, // 导出所有时间范围
    selectedWalletPks: null, // 导出所有钱包
  );
}

class CloudSyncButton extends StatelessWidget {
  const CloudSyncButton({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsContainer(
      onTap: () {
        pushRoute(context, const SyncSetupPage());
      },
      title: "Cloud Sync",
      icon: Icons.cloud_sync_rounded,
    );
  }
}

class AccountAndBackup extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SettingsContainerOutlined(
          title: "Cloud Sync",
          icon: Icons.cloud_sync_rounded,
          isExpanded: false,
          onTap: () {
            pushRoute(context, const SyncSetupPage());
          },
        ),
        SettingsContainerOutlined(
          title: "local-backup".tr(),
          icon: Icons.download,
          isExpanded: false,
          onTap: () async {
            await exportDB(boxContext: context);
          },
        ),
        SettingsContainerOutlined(
          title: "restore-from-backup".tr(),
          icon: Icons.upload,
          isExpanded: false,
          onTap: () async {
            await importDB(context);
          },
        ),
        SettingsContainerOutlined(
          title: "export-to-csv".tr(),
          icon: Icons.file_download,
          isExpanded: false,
          onTap: () async {
            await exportToCSV(context);
          },
        ),
      ],
    );
  }
}
