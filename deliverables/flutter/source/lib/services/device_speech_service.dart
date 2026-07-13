import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Small testable boundary around the platform TTS plugin.
abstract interface class TextToSpeechDriver {
  Future<void> stop();
  Future<void> awaitSpeakCompletion(bool enabled);
  Future<Object?> setLanguage(String languageTag);
  Future<Object?> setVoice(Map<String, String> voice);
  Future<void> setSpeechRate(double rate);
  Future<void> setVolume(double volume);
  Future<List<Map<String, String>>> getVoices();
  Future<Object?> speak(String text);
}

class FlutterTextToSpeechDriver implements TextToSpeechDriver {
  FlutterTextToSpeechDriver([FlutterTts? tts]) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;

  @override
  Future<void> stop() async {
    await _tts.stop();
  }

  @override
  Future<void> awaitSpeakCompletion(bool enabled) async {
    await _tts.awaitSpeakCompletion(enabled);
  }

  @override
  Future<Object?> setLanguage(String languageTag) =>
      _tts.setLanguage(languageTag);

  @override
  Future<Object?> setVoice(Map<String, String> voice) => _tts.setVoice(voice);

  @override
  Future<void> setSpeechRate(double rate) async {
    await _tts.setSpeechRate(rate);
  }

  @override
  Future<void> setVolume(double volume) async {
    await _tts.setVolume(volume);
  }

  @override
  Future<List<Map<String, String>>> getVoices() async {
    final rawVoices = await _tts.getVoices;
    if (rawVoices is! Iterable) return const [];
    return rawVoices.whereType<Map>().map((rawVoice) {
      final voice = <String, String>{};
      for (final entry in rawVoice.entries) {
        final key = entry.key;
        final value = entry.value;
        if (key is String && value != null) voice[key] = value.toString();
      }
      return voice;
    }).toList(growable: false);
  }

  @override
  Future<Object?> speak(String text) => _tts.speak(text);
}

/// Selects an actual matching voice before speaking and never lets a default
/// Chinese/English voice guess how target-language text should sound.
class DeviceSpeechService {
  DeviceSpeechService({
    TextToSpeechDriver? driver,
    bool? webRateScale,
    Future<void> Function(Duration duration)? delay,
  })  : _driver = driver ?? FlutterTextToSpeechDriver(),
        _webRateScale = webRateScale ?? kIsWeb,
        _delay = delay ?? Future<void>.delayed;

  final TextToSpeechDriver _driver;
  final bool _webRateScale;
  final Future<void> Function(Duration duration) _delay;
  final Map<String, Map<String, String>> _voiceCache = {};

  Future<void> _configurationTail = Future<void>.value();
  _ActiveSpeech? _activeSpeech;
  int _generation = 0;

  Future<void> speak(
    String text, {
    required String languageTag,
    required double rate,
  }) async {
    final value = text.trim();
    if (value.isEmpty) return;
    final normalizedTag = normalizeSpeechLanguageTag(languageTag);
    if (normalizedTag == 'und') {
      throw StateError('這張卡還沒有設定語言，為了避免錯誤發音，請先請家人選擇語言。');
    }

    final request = ++_generation;
    _cancelActiveSpeech();
    await _driver.stop();
    if (request != _generation) return;

    final active = await _withConfigurationLock<_ActiveSpeech?>(() async {
      if (request != _generation) return null;
      await _driver.awaitSpeakCompletion(true);
      if (request != _generation) return null;

      final voice = await _voiceFor(normalizedTag);
      if (request != _generation) return null;
      if (voice == null) {
        throw StateError(
          '這台裝置沒有可用的${speechLanguageLabel(normalizedTag)}語音。'
          '請在系統語音設定下載 $normalizedTag，或改聽家人錄音。',
        );
      }

      final languageResult = await _driver.setLanguage(normalizedTag);
      if (_explicitFailure(languageResult)) {
        throw StateError(
          '這台裝置無法啟用${speechLanguageLabel(normalizedTag)}語音，'
          '請先下載 $normalizedTag 語音。',
        );
      }
      if (request != _generation) return null;

      final voiceResult = await _driver.setVoice(voice);
      if (_explicitFailure(voiceResult)) {
        throw StateError('這台裝置無法選用已找到的 $normalizedTag 語音。');
      }
      if (request != _generation) return null;

      await _driver.setSpeechRate(
        calibratedSpeechRate(rate, webRateScale: _webRateScale),
      );
      if (request != _generation) return null;
      await _driver.setVolume(1);
      if (request != _generation) return null;

      final started = _ActiveSpeech();
      _activeSpeech = started;
      _driver.speak(value).then<void>(
            (_) => started.complete(),
            onError: started.completeError,
          );
      return started;
    });

    if (active == null) return;
    try {
      await active.future.timeout(_speechTimeout(value));
    } on TimeoutException {
      if (_activeSpeech == active) {
        _generation += 1;
        _activeSpeech = null;
        active.cancel();
        await _driver.stop();
      }
      throw StateError('語音播放逾時，已停止這一次朗讀，請再試一次。');
    } finally {
      if (_activeSpeech == active) _activeSpeech = null;
    }
  }

  Future<void> stop() async {
    _generation += 1;
    _cancelActiveSpeech();
    await _driver.stop();
  }

  Future<Map<String, String>?> _voiceFor(String languageTag) async {
    final cached = _voiceCache[languageTag];
    if (cached != null) return cached;

    const waits = <Duration>[
      Duration.zero,
      Duration(milliseconds: 100),
      Duration(milliseconds: 250),
      Duration(milliseconds: 500),
    ];
    for (final wait in waits) {
      if (wait > Duration.zero) await _delay(wait);
      List<Map<String, String>> voices;
      try {
        voices = await _driver.getVoices();
      } on Object {
        // Browser voices may still be initialising, and some platform plugins
        // throw during that short window. Retry before showing the same clear
        // fail-closed message used for an empty/missing language voice.
        continue;
      }
      final selected = selectSpeechVoice(voices, languageTag);
      if (selected != null) {
        _voiceCache[languageTag] = selected;
        return selected;
      }
    }
    return null;
  }

  Future<T> _withConfigurationLock<T>(Future<T> Function() action) async {
    final previous = _configurationTail;
    final release = Completer<void>();
    _configurationTail = release.future;
    await previous;
    try {
      return await action();
    } finally {
      release.complete();
    }
  }

  void _cancelActiveSpeech() {
    final active = _activeSpeech;
    _activeSpeech = null;
    active?.cancel();
  }

  static bool _explicitFailure(Object? result) =>
      result == false || (result is num && result == 0);

  static Duration _speechTimeout(String text) {
    final estimatedSeconds = 7 + (text.runes.length / 4).ceil();
    return Duration(seconds: estimatedSeconds.clamp(8, 30));
  }
}

class _ActiveSpeech {
  _ActiveSpeech();

  final Completer<void> _completion = Completer<void>();

  Future<void> get future => _completion.future;

  void complete() {
    if (!_completion.isCompleted) _completion.complete();
  }

  void completeError(Object error, StackTrace stackTrace) {
    if (!_completion.isCompleted) _completion.completeError(error, stackTrace);
  }

  void cancel() => complete();
}

@visibleForTesting
String normalizeSpeechLanguageTag(String value) {
  final parts = value
      .trim()
      .replaceAll('_', '-')
      .split('-')
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) return 'und';
  return [
    parts.first.toLowerCase(),
    for (final part in parts.skip(1))
      if (part.length == 2 || RegExp(r'^\d{3}$').hasMatch(part))
        part.toUpperCase()
      else if (part.length == 4)
        '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}'
      else
        part.toLowerCase(),
  ].join('-');
}

@visibleForTesting
Map<String, String>? selectSpeechVoice(
  List<Map<String, String>> voices,
  String requestedLanguageTag,
) {
  final requested = normalizeSpeechLanguageTag(requestedLanguageTag);
  final exact = voices.where(
    (voice) => normalizeSpeechLanguageTag(voice['locale'] ?? '') == requested,
  );
  final candidates = exact.isNotEmpty
      ? exact
      : requested.contains('-')
          ? const Iterable<Map<String, String>>.empty()
          : voices.where(
              (voice) =>
                  normalizeSpeechLanguageTag(voice['locale'] ?? '')
                      .split('-')
                      .first ==
                  requested,
            );
  if (candidates.isEmpty) return null;
  final ranked = candidates.toList(growable: false)
    ..sort(
        (left, right) => _voiceQuality(right).compareTo(_voiceQuality(left)));
  final selected = ranked.first;
  return {
    if (selected['name'] case final name?) 'name': name,
    if (selected['locale'] case final locale?) 'locale': locale,
    if (selected['identifier'] case final identifier?) 'identifier': identifier,
  };
}

int _voiceQuality(Map<String, String> voice) {
  final quality = voice['quality']?.toLowerCase() ?? '';
  if (quality.contains('premium')) return 3;
  if (quality.contains('enhanced')) return 2;
  return 1;
}

@visibleForTesting
double calibratedSpeechRate(double requestedRate,
    {required bool webRateScale}) {
  final safe = requestedRate.clamp(.2, .65).toDouble();
  if (!webRateScale) return safe;
  // flutter_tts maps the same value differently per platform. Android treats
  // .5 as normal, while Web Speech treats 1.0 as normal.
  return (safe * 2).clamp(.65, 1.15).toDouble();
}

String speechLanguageLabel(String languageTag) =>
    switch (normalizeSpeechLanguageTag(languageTag).split('-').first) {
      'vi' => '越南語',
      'nan' => '台語',
      'hak' => '客語',
      'zh' => '中文',
      _ => '$languageTag ',
    };
