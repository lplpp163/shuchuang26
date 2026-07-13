import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hometongue_tags/services/device_speech_service.dart';

class _FakeTtsDriver implements TextToSpeechDriver {
  List<List<Map<String, String>>> voiceResponses = const [];
  final List<Completer<List<Map<String, String>>>> voiceCompleters = [];
  final Map<int, Object> voiceErrors = {};
  final List<String> spoken = [];
  final List<String> languages = [];
  final List<Map<String, String>> selectedVoices = [];
  final List<double> rates = [];
  final Completer<void> speechStarted = Completer<void>();

  Object? languageResult = 1;
  Object? voiceResult = 1;
  bool hangSpeech = false;
  int voiceReads = 0;
  int stopCount = 0;

  @override
  Future<void> awaitSpeakCompletion(bool enabled) async {}

  @override
  Future<List<Map<String, String>>> getVoices() async {
    final index = voiceReads++;
    final error = voiceErrors[index];
    if (error != null) throw error;
    if (index < voiceCompleters.length) return voiceCompleters[index].future;
    if (voiceResponses.isEmpty) return const [];
    return voiceResponses[index.clamp(0, voiceResponses.length - 1)];
  }

  @override
  Future<Object?> setLanguage(String languageTag) async {
    languages.add(languageTag);
    return languageResult;
  }

  @override
  Future<void> setSpeechRate(double rate) async {
    rates.add(rate);
  }

  @override
  Future<Object?> setVoice(Map<String, String> voice) async {
    selectedVoices.add(voice);
    return voiceResult;
  }

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<Object?> speak(String text) {
    spoken.add(text);
    if (!speechStarted.isCompleted) speechStarted.complete();
    if (hangSpeech) return Completer<Object?>().future;
    return Future<Object?>.value(1);
  }

  @override
  Future<void> stop() async {
    stopCount += 1;
  }
}

void main() {
  test('normalizes BCP-47 tags without guessing an unknown language', () {
    expect(normalizeSpeechLanguageTag(' VI_vn '), 'vi-VN');
    expect(normalizeSpeechLanguageTag('zh_hant_tw'), 'zh-Hant-TW');
    expect(normalizeSpeechLanguageTag(''), 'und');
  });

  test('voice selection requires the requested locale and prefers quality', () {
    final selected = selectSpeechVoice(
      const [
        {'name': 'English', 'locale': 'en-US'},
        {'name': 'Basic Vietnamese', 'locale': 'vi_VN'},
        {
          'name': 'Enhanced Vietnamese',
          'locale': 'vi-VN',
          'quality': 'enhanced',
          'identifier': 'voice.vi.enhanced',
        },
      ],
      'vi-VN',
    );

    expect(selected?['name'], 'Enhanced Vietnamese');
    expect(selected?['identifier'], 'voice.vi.enhanced');
    expect(
      selectSpeechVoice(
        const [
          {'name': 'Brazilian Portuguese', 'locale': 'pt-BR'},
        ],
        'pt-PT',
      ),
      isNull,
    );
  });

  test('calibrates web speech rate instead of using an extremely slow raw rate',
      () {
    expect(calibratedSpeechRate(.42, webRateScale: true), .84);
    expect(calibratedSpeechRate(.28, webRateScale: true), .65);
    expect(calibratedSpeechRate(.42, webRateScale: false), .42);
  });

  test('waits for delayed browser voices, locks vi-VN, then speaks', () async {
    final driver = _FakeTtsDriver()
      ..voiceResponses = const [
        [],
        [],
        [
          {'name': 'HoaiMy', 'locale': 'vi_VN'},
        ],
      ];
    final waits = <Duration>[];
    final service = DeviceSpeechService(
      driver: driver,
      webRateScale: true,
      delay: (duration) async => waits.add(duration),
    );

    await service.speak(
      'Cháu về rồi ạ.',
      languageTag: 'vi_vn',
      rate: .42,
    );

    expect(driver.voiceReads, 3);
    expect(waits, const [
      Duration(milliseconds: 100),
      Duration(milliseconds: 250),
    ]);
    expect(driver.languages, ['vi-VN']);
    expect(driver.selectedVoices.single['name'], 'HoaiMy');
    expect(driver.rates, [.84]);
    expect(driver.spoken, ['Cháu về rồi ạ.']);
  });

  test('retries a transient browser voice lookup error', () async {
    final driver = _FakeTtsDriver()
      ..voiceErrors[0] = StateError('voices are still loading')
      ..voiceResponses = const [
        [
          {'name': 'HoaiMy', 'locale': 'vi-VN'},
        ],
      ];
    final service = DeviceSpeechService(
      driver: driver,
      webRateScale: true,
      delay: (_) async {},
    );

    await service.speak(
      'Cháu chào bà ạ.',
      languageTag: 'vi-VN',
      rate: .42,
    );

    expect(driver.voiceReads, 2);
    expect(driver.spoken, ['Cháu chào bà ạ.']);
  });

  test('fails closed when the device has no matching Vietnamese voice',
      () async {
    final driver = _FakeTtsDriver()
      ..voiceResponses = const [
        [
          {'name': 'Chinese', 'locale': 'zh-TW'},
          {'name': 'English', 'locale': 'en-US'},
        ],
      ];
    final service = DeviceSpeechService(
      driver: driver,
      webRateScale: true,
      delay: (_) async {},
    );

    await expectLater(
      service.speak('Ngon quá ạ!', languageTag: 'vi-VN', rate: .42),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('沒有可用的越南語語音'),
        ),
      ),
    );
    expect(driver.spoken, isEmpty);
    expect(driver.selectedVoices, isEmpty);
  });

  test('does not speak when the platform rejects setLanguage', () async {
    final driver = _FakeTtsDriver()
      ..voiceResponses = const [
        [
          {'name': 'Vietnamese', 'locale': 'vi-VN'},
        ],
      ]
      ..languageResult = 0;
    final service = DeviceSpeechService(
      driver: driver,
      webRateScale: false,
      delay: (_) async {},
    );

    await expectLater(
      service.speak('Đây là nhà.', languageTag: 'vi-VN', rate: .42),
      throwsStateError,
    );
    expect(driver.spoken, isEmpty);
  });

  test(
      'stop releases a caller even if the plugin cancel future never completes',
      () async {
    final driver = _FakeTtsDriver()
      ..voiceResponses = const [
        [
          {'name': 'Vietnamese', 'locale': 'vi-VN'},
        ],
      ]
      ..hangSpeech = true;
    final service = DeviceSpeechService(
      driver: driver,
      webRateScale: true,
      delay: (_) async {},
    );

    final speaking = service.speak(
      'Cháu chào bà ạ.',
      languageTag: 'vi-VN',
      rate: .42,
    );
    await driver.speechStarted.future;
    await service.stop();
    await speaking.timeout(const Duration(seconds: 1));

    expect(driver.stopCount, greaterThanOrEqualTo(2));
  });

  test('latest request wins while an older voice lookup is still pending',
      () async {
    final delayedVoices = Completer<List<Map<String, String>>>();
    final driver = _FakeTtsDriver()
      ..voiceCompleters.add(delayedVoices)
      ..voiceResponses = const [
        [
          {'name': 'Vietnamese', 'locale': 'vi-VN'},
        ],
      ];
    final service = DeviceSpeechService(
      driver: driver,
      webRateScale: true,
      delay: (_) async {},
    );

    final oldRequest = service.speak(
      '舊的內容',
      languageTag: 'vi-VN',
      rate: .42,
    );
    await Future<void>.delayed(Duration.zero);
    final latestRequest = service.speak(
      'Cháu về rồi ạ.',
      languageTag: 'vi-VN',
      rate: .42,
    );
    delayedVoices.complete(const [
      {'name': 'Vietnamese', 'locale': 'vi-VN'},
    ]);

    await Future.wait([oldRequest, latestRequest]);
    expect(driver.spoken, ['Cháu về rồi ạ.']);
  });

  test('unknown language is never guessed from the device default voice',
      () async {
    final driver = _FakeTtsDriver();
    final service = DeviceSpeechService(
      driver: driver,
      webRateScale: true,
      delay: (_) async {},
    );

    await expectLater(
      service.speak('unknown', languageTag: 'und', rate: .42),
      throwsStateError,
    );
    expect(driver.voiceReads, 0);
    expect(driver.spoken, isEmpty);
  });
}
