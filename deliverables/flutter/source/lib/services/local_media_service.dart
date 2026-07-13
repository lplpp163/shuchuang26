import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'device_speech_service.dart';
import 'media_blob_store.dart';

class LocalMediaService {
  /// flutter_tts uses .5 as the native normal-speed anchor. Web is calibrated
  /// inside [DeviceSpeechService] so callers can use the same semantic values.
  static const double normalSpeechRate = .46;
  static const double slowSpeechRate = .36;
  static const double segmentSpeechRate = .40;
  static const double slowedRecordingSpeed = .85;

  LocalMediaService({
    AudioRecorder? recorder,
    ImagePicker? picker,
    AudioPlayer? player,
    DeviceSpeechService? speech,
    MediaBlobStore? mediaBlobStore,
  })  : _recorder = recorder ?? AudioRecorder(),
        _picker = picker ?? ImagePicker(),
        _player = player ?? AudioPlayer(),
        _speech = speech ?? DeviceSpeechService(),
        _mediaBlobStore = mediaBlobStore ?? createMediaBlobStore();

  final AudioRecorder _recorder;
  final ImagePicker _picker;
  final AudioPlayer _player;
  final DeviceSpeechService _speech;
  final MediaBlobStore _mediaBlobStore;

  bool _isRecording = false;
  String? _pendingMediaId;
  bool get isRecording => _isRecording;

  Stream<double> amplitudeDbSamples({
    Duration interval = const Duration(milliseconds: 120),
  }) =>
      _recorder.onAmplitudeChanged(interval).map((sample) => sample.current);

  Future<String> startRecording(String prefix) async {
    if (_isRecording) {
      throw StateError('已有錄音正在進行');
    }
    if (!await _recorder.hasPermission()) {
      throw StateError('需要麥克風權限才能錄音');
    }
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    _pendingMediaId = '${prefix}_$timestamp';
    final path = kIsWeb
        ? '${_pendingMediaId!}.webm'
        : '${(await _mediaDirectory()).path}${Platform.pathSeparator}'
            '${prefix}_$timestamp.m4a';
    await _recorder.start(
      RecordConfig(
        encoder: kIsWeb ? AudioEncoder.opus : AudioEncoder.aacLc,
        bitRate: 64000,
        sampleRate: 44100,
      ),
      path: path,
    );
    _isRecording = true;
    return path;
  }

  Future<String?> stopRecording() async {
    if (!_isRecording) return null;
    final path = await _recorder.stop();
    _isRecording = false;
    if (path == null) return null;
    if (!kIsWeb) return path;
    final mediaId = _pendingMediaId;
    _pendingMediaId = null;
    if (mediaId == null) throw StateError('找不到這段錄音，請再錄一次');
    return _mediaBlobStore.persistBlobUrl(
      path,
      mediaId: mediaId,
      mimeType: 'audio/webm;codecs=opus',
    );
  }

  Future<void> cancelRecording() async {
    if (!_isRecording) return;
    await _recorder.cancel();
    _isRecording = false;
    _pendingMediaId = null;
  }

  Future<String?> capturePhoto({bool useCamera = true}) async {
    final image = await _picker.pickImage(
      source: useCamera ? ImageSource.camera : ImageSource.gallery,
      imageQuality: 82,
      maxWidth: 1600,
    );
    if (image == null) return null;
    if (kIsWeb) return image.path;
    final directory = await _mediaDirectory();
    final extension = _extensionOf(image.path);
    final savedPath = '${directory.path}${Platform.pathSeparator}'
        'story_${DateTime.now().millisecondsSinceEpoch}$extension';
    await File(image.path).copy(savedPath);
    return savedPath;
  }

  Future<void> playLocal(
    String path, {
    double speed = 1,
    Duration? start,
    Duration? end,
  }) async {
    await _speech.stop();
    await _player.stop();
    if (path.startsWith('asset://')) {
      await _player.setAsset(path.substring('asset://'.length));
    } else if (kIsWeb) {
      final resolved = await _mediaBlobStore.resolve(path);
      if (resolved == null) {
        throw StateError('找不到這段錄音，可能已被瀏覽器清除');
      }
      await _player.setUrl(resolved);
    } else {
      final file = File(path);
      if (!await file.exists()) {
        throw StateError('找不到這段錄音，可能已被移除');
      }
      await _player.setFilePath(path);
    }
    await _player.setClip(start: start, end: end);
    await _player.setSpeed(speed);
    await _player.play();
  }

  Future<void> speakText(
    String text, {
    String languageTag = 'vi-VN',
    double rate = normalSpeechRate,
  }) async {
    final value = text.trim();
    if (value.isEmpty) return;
    await _player.stop();
    await _speech.speak(
      value,
      languageTag: languageTag,
      rate: rate,
    );
  }

  Future<void> stopPlayback() async {
    await _player.stop();
    await _speech.stop();
  }

  Future<void> deletePath(String? path) async {
    if (path == null || path.isEmpty) return;
    if (path.startsWith('asset://')) return;
    if (kIsWeb) {
      await _mediaBlobStore.delete(path);
      return;
    }
    final file = File(path);
    final media = await _mediaDirectory();
    final filePath = file.absolute.path.toLowerCase();
    final mediaPath = media.absolute.path.toLowerCase();
    if (filePath.startsWith(mediaPath) && await file.exists()) {
      await file.delete();
    }
  }

  Future<void> eraseAllMedia() async {
    await _player.stop();
    await cancelRecording();
    if (kIsWeb) {
      await _mediaBlobStore.clear();
      return;
    }
    final media = await _mediaDirectory();
    if (await media.exists()) {
      await for (final entity in media.list()) {
        if (entity is File) await entity.delete();
      }
    }
  }

  Future<Directory> _mediaDirectory() async {
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}hometongue_media',
    );
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  String _extensionOf(String path) {
    final index = path.lastIndexOf('.');
    if (index < 0) return '.jpg';
    final extension = path.substring(index).toLowerCase();
    return extension.length <= 5 ? extension : '.jpg';
  }

  Future<void> dispose() async {
    await _speech.stop();
    await _player.dispose();
    await _recorder.dispose();
    await _mediaBlobStore.close();
  }
}
