import 'dart:convert';
import 'dart:typed_data';

import 'package:budget/struct/settings.dart';
import 'package:budget/struct/sync/sync_models.dart';
import 'package:http/http.dart' as http;

class SyncClient {
  static const _metaTimeout = Duration(seconds: 30);
  static const _transferTimeout = Duration(seconds: 120);

  String get _baseUrl {
    String url = appStateSettings["syncServerUrl"] ?? "";
    // Strip trailing slash.
    if (url.endsWith("/")) url = url.substring(0, url.length - 1);
    return url;
  }

  /// Fetch metadata about a backup from the server.
  Future<SyncMeta> fetchMeta(String backupId) async {
    final response = await http
        .get(Uri.parse('$_baseUrl/meta/$backupId'))
        .timeout(_metaTimeout);

    if (response.statusCode != 200) {
      throw SyncException('Meta request failed: ${response.statusCode}');
    }
    return SyncMeta.fromJson(json.decode(response.body));
  }

  /// Upload encrypted backup data. Returns true if accepted, false if 409 conflict.
  Future<bool> upload(
      String backupId, Uint8List data, DateTime timestamp) async {
    final response = await http
        .post(
          Uri.parse('$_baseUrl/upload/$backupId'),
          headers: {
            'Content-Type': 'application/octet-stream',
            'X-Timestamp': timestamp.toUtc().toIso8601String(),
          },
          body: data,
        )
        .timeout(_transferTimeout);

    if (response.statusCode == 200) return true;
    if (response.statusCode == 409) return false; // server has newer
    throw SyncException('Upload failed: ${response.statusCode}');
  }

  /// Download encrypted backup data. Returns null if not found (404).
  Future<Uint8List?> download(String backupId) async {
    final response = await http
        .get(Uri.parse('$_baseUrl/download/$backupId'))
        .timeout(_transferTimeout);

    if (response.statusCode == 200) return response.bodyBytes;
    if (response.statusCode == 404) return null;
    throw SyncException('Download failed: ${response.statusCode}');
  }
}

class SyncException implements Exception {
  final String message;
  SyncException(this.message);
  @override
  String toString() => 'SyncException: $message';
}
