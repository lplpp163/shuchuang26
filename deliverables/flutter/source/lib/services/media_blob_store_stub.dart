import 'media_blob_store_base.dart';

MediaBlobStore createMediaBlobStore() => _PassthroughMediaBlobStore();

class _PassthroughMediaBlobStore implements MediaBlobStore {
  @override
  Future<String> persistBlobUrl(
    String blobUrl, {
    required String mediaId,
    required String mimeType,
  }) async =>
      blobUrl;

  @override
  Future<String?> resolve(String mediaReference) async => mediaReference;

  @override
  Future<void> delete(String mediaReference) async {}

  @override
  Future<void> clear() async {}

  @override
  Future<void> close() async {}
}
