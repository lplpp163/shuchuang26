import 'media_blob_store_base.dart';
import 'media_blob_store_stub.dart'
    if (dart.library.js_interop) 'media_blob_store_web.dart' as implementation;

export 'media_blob_store_base.dart';

MediaBlobStore createMediaBlobStore() => implementation.createMediaBlobStore();
