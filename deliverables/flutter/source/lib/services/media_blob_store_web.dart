import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:idb_shim/idb_browser.dart';
import 'package:web/web.dart' as web;

import 'media_blob_store_base.dart';

MediaBlobStore createMediaBlobStore() => _IndexedDbMediaBlobStore();

class _IndexedDbMediaBlobStore implements MediaBlobStore {
  static const _databaseName = 'our-family-voice-media-v1';
  static const _storeName = 'clips';
  static const _mediaPrefix = 'media://';

  Database? _database;

  Future<Database> _open() async {
    final existing = _database;
    if (existing != null) return existing;
    final database = await idbFactoryBrowser.open(
      _databaseName,
      version: 1,
      onUpgradeNeeded: (event) {
        final database = event.database;
        if (!database.objectStoreNames.contains(_storeName)) {
          database.createObjectStore(_storeName);
        }
      },
    );
    _database = database;
    return database;
  }

  @override
  Future<String> persistBlobUrl(
    String blobUrl, {
    required String mediaId,
    required String mimeType,
  }) async {
    try {
      final response = await http.get(Uri.parse(blobUrl));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('錄音暫存失敗，請再錄一次');
      }
      final database = await _open();
      final transaction = database.transaction(_storeName, idbModeReadWrite);
      await transaction.objectStore(_storeName).put(<String, Object?>{
        'bytes': Uint8List.fromList(response.bodyBytes),
        'mimeType': mimeType,
      }, mediaId);
      await transaction.completed;
      return '$_mediaPrefix$mediaId';
    } finally {
      web.URL.revokeObjectURL(blobUrl);
    }
  }

  @override
  Future<String?> resolve(String mediaReference) async {
    if (!mediaReference.startsWith(_mediaPrefix)) return mediaReference;
    final mediaId = mediaReference.substring(_mediaPrefix.length);
    final database = await _open();
    final transaction = database.transaction(_storeName, idbModeReadOnly);
    final raw = await transaction.objectStore(_storeName).getObject(mediaId);
    await transaction.completed;
    if (raw is! Map) return null;
    final value = Map<Object?, Object?>.from(raw);
    final storedBytes = value['bytes'];
    final bytes = switch (storedBytes) {
      final Uint8List data => data,
      final List<Object?> data => Uint8List.fromList(data.cast<int>()),
      _ => null,
    };
    if (bytes == null) return null;
    final mimeType = value['mimeType'] as String? ?? 'audio/webm';
    return 'data:$mimeType;base64,${base64Encode(bytes)}';
  }

  @override
  Future<void> delete(String mediaReference) async {
    if (!mediaReference.startsWith(_mediaPrefix)) return;
    final database = await _open();
    final transaction = database.transaction(_storeName, idbModeReadWrite);
    await transaction
        .objectStore(_storeName)
        .delete(mediaReference.substring(_mediaPrefix.length));
    await transaction.completed;
  }

  @override
  Future<void> clear() async {
    final database = await _open();
    final transaction = database.transaction(_storeName, idbModeReadWrite);
    await transaction.objectStore(_storeName).clear();
    await transaction.completed;
  }

  @override
  Future<void> close() async {
    _database?.close();
    _database = null;
  }
}
