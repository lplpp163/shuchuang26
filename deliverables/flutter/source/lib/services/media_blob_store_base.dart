abstract interface class MediaBlobStore {
  Future<String> persistBlobUrl(
    String blobUrl, {
    required String mediaId,
    required String mimeType,
  });

  Future<String?> resolve(String mediaReference);

  Future<void> delete(String mediaReference);

  Future<void> clear();

  Future<void> close();
}
