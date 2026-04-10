enum SyncResult {
  uploaded,
  downloaded,
  noAction,
  error,
  offline,
  notConfigured,
}

class SyncMeta {
  final DateTime? lastModified;
  final bool exists;

  SyncMeta({this.lastModified, required this.exists});

  factory SyncMeta.fromJson(Map<String, dynamic> json) {
    return SyncMeta(
      lastModified: json['last_modified'] != null
          ? DateTime.parse(json['last_modified'])
          : null,
      exists: json['exists'] ?? false,
    );
  }
}
