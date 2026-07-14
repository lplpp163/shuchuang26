import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../core/app_theme.dart';
import '../models/family_story.dart';
import '../models/family_relay.dart';
import '../models/learning_attempt.dart';
import '../models/lesson_content.dart';
import '../models/recording_metrics.dart';
import '../services/app_store.dart';
import '../services/local_media_service.dart';
import '../services/pronunciation_coach.dart';
import '../services/transcript_coach.dart';
import '../widgets/recording_control.dart';
import 'family_relay_reveal_screen.dart';

class StoryDetailScreen extends StatefulWidget {
  const StoryDetailScreen({
    required this.story,
    required this.store,
    required this.media,
    super.key,
  });

  final FamilyStory story;
  final AppStore store;
  final LocalMediaService media;

  @override
  State<StoryDetailScreen> createState() => _StoryDetailScreenState();
}

class _StoryDetailScreenState extends State<StoryDetailScreen> {
  final TextEditingController _childNote = TextEditingController();
  static const LocalPracticeCoach _coach = LocalPracticeCoach();
  static const TranscriptCoach _transcriptCoach = TranscriptCoach();
  final stt.SpeechToText _speech = stt.SpeechToText();
  String? _replyPath;
  RecordingMetrics? _metrics;
  PronunciationFeedback? _feedback;
  TranscriptFeedback? _transcriptFeedback;
  String? _speechMessage;
  bool _heard = false;
  bool _playing = false;
  bool _showReading = true;
  bool _showChinese = true;
  bool _submitting = false;
  bool _completed = false;
  bool _checkingSpeech = false;
  int _focusChunk = 0;
  FamilyRelay? _completedRelay;
  LearningAttempt? _completedAttempt;

  FamilyStory get _story =>
      widget.store.storyById(widget.story.id) ?? widget.story;

  @override
  void initState() {
    super.initState();
    // Every card can be heard: a family recording is preferred and device TTS
    // is the fallback. Keep the listen step visible even for generated cards.
    _heard = false;
  }

  @override
  void dispose() {
    _childNote.dispose();
    _speech.cancel();
    widget.media.stopPlayback();
    super.dispose();
  }

  Future<void> _playVoice({double speed = 1}) => _playAudio(
        path: _story.audioPath,
        fallbackText: _story.vietnamese,
        speed: speed,
        markFullSentenceHeard: true,
      );

  Future<void> _playSegment(
    LessonSegment segment, {
    double speed = 1,
  }) async {
    final audio = segment.audio;
    final hasRange = audio?.hasValidRange ?? false;
    final path = audio?.path ?? (hasRange ? _story.audioPath : null);
    await _playAudio(
      path: path,
      fallbackText: segment.text,
      speed: speed,
      start: hasRange ? Duration(milliseconds: audio!.startMs!) : null,
      end: hasRange ? Duration(milliseconds: audio!.endMs!) : null,
    );
  }

  Future<void> _playExample(LessonExample example) => _playAudio(
        path: example.audio?.path,
        fallbackText: example.targetText,
        start: example.audio?.hasValidRange == true
            ? Duration(milliseconds: example.audio!.startMs!)
            : null,
        end: example.audio?.hasValidRange == true
            ? Duration(milliseconds: example.audio!.endMs!)
            : null,
      );

  Future<void> _playAudio({
    required String? path,
    String? fallbackText,
    double speed = 1,
    Duration? start,
    Duration? end,
    bool markFullSentenceHeard = false,
  }) async {
    if ((path == null && (fallbackText == null || fallbackText.isEmpty)) ||
        _playing) {
      return;
    }
    setState(() => _playing = true);
    try {
      if (path != null) {
        await widget.media.playLocal(
          path,
          speed: speed,
          start: start,
          end: end,
        );
      } else {
        await widget.media.speakText(
          fallbackText!,
          languageTag: _story.effectiveLanguageTag,
          rate: (LocalMediaService.normalSpeechRate * speed)
              .clamp(LocalMediaService.slowSpeechRate, .60)
              .toDouble(),
        );
      }
      if (mounted && markFullSentenceHeard) setState(() => _heard = true);
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Bad state: ', '')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _playing = false);
    }
  }

  void _handleRecorded(String? path) {
    setState(() {
      _replyPath = path;
      if (path == null) {
        _metrics = null;
        _feedback = null;
      }
    });
  }

  void _handleMetrics(RecordingMetrics metrics) {
    setState(() {
      _metrics = metrics;
      _feedback = _coach.analyze(
        story: _story,
        metrics: metrics,
        focusText: _focusedSegment.text,
      );
    });
  }

  List<LessonSegment> get _segments {
    final structured = _story.lessonContent?.segments ?? const [];
    if (structured.isNotEmpty) return structured;
    return _story.effectivePracticeChunks
        .asMap()
        .entries
        .map(
          (entry) => LessonSegment(
            id: 'legacy-${entry.key}',
            text: entry.value,
            tokens: [entry.value],
            translationZh: '這張舊卡尚未補上分段解釋',
            romanization: entry.value,
            pronunciationTipsZh: const [
              '先聽完整家人錄音；補上人工切點後才能精準播放這一段。',
            ],
          ),
        )
        .toList(growable: false);
  }

  LessonSegment get _focusedSegment {
    final segments = _segments;
    return segments[math.min(_focusChunk, segments.length - 1)];
  }

  void _selectSegment(int index) {
    setState(() {
      _focusChunk = index;
      if (_metrics != null) {
        _feedback = _coach.analyze(
          story: _story,
          metrics: _metrics!,
          focusText: _segments[index].text,
        );
      }
      if (_transcriptFeedback != null) {
        _transcriptFeedback = _transcriptCoach.analyze(
          story: _story,
          transcript: _transcriptFeedback!.transcript,
          recognitionConfidence: _transcriptFeedback!.recognitionConfidence,
          focusText: _segments[index].text,
        );
      }
    });
  }

  Future<void> _toggleBrowserSpeechCheck() async {
    if (_checkingSpeech) {
      await _speech.stop();
      if (mounted) setState(() => _checkingSpeech = false);
      return;
    }
    if (!_story.lessonContent!.languageTag.toLowerCase().startsWith('vi')) {
      setState(() {
        _speechMessage = '目前免金鑰辨識只開放越南語示範；臺語仍需專用模型與家人確認。';
      });
      return;
    }

    await widget.media.stopPlayback();
    setState(() {
      _speechMessage = null;
      _transcriptFeedback = null;
    });
    try {
      var listenStarted = false;
      var receivedTranscript = false;
      final available = await _speech.initialize(
        onStatus: (status) {
          if (!mounted) return;
          if (listenStarted &&
              (status == stt.SpeechToText.doneStatus ||
                  status == stt.SpeechToText.notListeningStatus)) {
            setState(() {
              _checkingSpeech = false;
              if (!receivedTranscript && _transcriptFeedback == null) {
                _speechMessage = '系統這次沒有寫出文字。可能是瀏覽器、環境音或腔調差異，不代表你念錯。';
              }
            });
          }
        },
        onError: (error) {
          if (!mounted) return;
          final code = error.errorMsg.toLowerCase();
          setState(() {
            _checkingSpeech = false;
            _speechMessage = code.contains('not-allowed') ||
                    code.contains('not_allowed') ||
                    code.contains('permission')
                ? '麥克風權限尚未開啟；可以請大人調整瀏覽器權限。原本錄音與節奏提示仍會保留。'
                : '聽寫暫時無法使用；這是裝置或瀏覽器限制，不代表你念錯。原本錄音與節奏提示仍會保留。';
          });
        },
      );
      if (!available) {
        if (mounted) {
          setState(() => _speechMessage = '這個瀏覽器沒有提供免金鑰語音辨識。');
        }
        return;
      }
      final locales = await _speech.locales();
      final targetTag =
          _story.lessonContent!.languageTag.toLowerCase().replaceAll('_', '-');
      String? localeId;
      for (final locale in locales) {
        final normalized = locale.localeId.toLowerCase().replaceAll('_', '-');
        if (normalized == targetTag || normalized.startsWith('vi')) {
          localeId = locale.localeId;
          break;
        }
      }
      localeId ??= _story.lessonContent!.languageTag;
      listenStarted = true;
      setState(() => _checkingSpeech = true);
      await _speech.listen(
        onResult: (result) {
          if (!mounted) return;
          final transcript = result.recognizedWords;
          if (transcript.trim().isNotEmpty) receivedTranscript = true;
          setState(() {
            _transcriptFeedback = _transcriptCoach.analyze(
              story: _story,
              transcript: transcript,
              recognitionConfidence:
                  result.hasConfidenceRating ? result.confidence : null,
              focusText: _focusedSegment.text,
            );
            if (result.finalResult) _checkingSpeech = false;
          });
        },
        listenOptions: stt.SpeechListenOptions(
          localeId: localeId,
          listenFor: const Duration(seconds: 8),
          pauseFor: const Duration(seconds: 2),
          partialResults: true,
          cancelOnError: true,
          listenMode: stt.ListenMode.confirmation,
        ),
      );
    } on Object {
      if (!mounted) return;
      setState(() {
        _checkingSpeech = false;
        _speechMessage = '這次無法啟動辨識；請確認麥克風權限或改用 Edge／Chrome。';
      });
    }
  }

  Future<void> _submit() async {
    if (_replyPath == null && _childNote.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('先錄一句；麥克風不能用時，也可以寫下來。')),
      );
      return;
    }
    setState(() => _submitting = true);
    final attempt = await widget.store.submitAttempt(
      storyId: _story.id,
      audioPath: _replyPath,
      childNote: _childNote.text,
      recordingDurationMs: _metrics?.duration.inMilliseconds,
      averageAmplitudeDb: _metrics?.averageDb,
      coachSummary: _feedback?.storageSummary,
      coachMode: _feedback == null ? null : 'local-timing-v1',
    );
    final relay = await widget.store.completeChildRelay(
      storyId: _story.id,
      attemptId: attempt.id,
    );
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _completed = true;
      _completedRelay = relay;
      _completedAttempt = attempt;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_completed ? '短句挑戰完成' : '最後一關 · 跟著說'),
        centerTitle: true,
        actions: [
          if (!_completed)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.sunSoft,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: const Text(
                    '勇氣貼紙',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          child: _completed
              ? _completedRelay != null && _completedAttempt != null
                  ? FamilyRelayRevealView(
                      relay: _completedRelay!,
                      story: _story,
                      attempt: _completedAttempt!,
                      media: widget.media,
                      onDone: () => Navigator.pop(context),
                    )
                  : _CompletionView(
                      key: const ValueKey('completion'),
                      recorded: _replyPath != null,
                      onDone: () => Navigator.pop(context),
                    )
              : _buildActivity(context),
        ),
      ),
    );
  }

  Widget _buildActivity(BuildContext context) {
    final story = _story;
    final currentStep = !_heard
        ? 1
        : _replyPath == null && _childNote.text.trim().isEmpty
            ? 2
            : 3;
    final segments = _segments;
    final focusIndex = math.min(_focusChunk, segments.length - 1);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          key: const ValueKey('activity'),
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 38),
          children: [
            _StepRail(currentStep: currentStep),
            const SizedBox(height: 16),
            _SceneCard(story: story),
            const SizedBox(height: 14),
            _PhraseTutorCard(
              story: story,
              segments: segments,
              focusChunk: focusIndex,
              showReading: _showReading,
              showChinese: _showChinese,
              playing: _playing,
              heard: _heard,
              onChunkSelected: _selectSegment,
              onChunkPlay: (segment) => _playSegment(segment),
              onChunkSlowPlay: (segment) => _playSegment(
                segment,
                speed: LocalMediaService.slowedRecordingSpeed,
              ),
              onToggleReading: () =>
                  setState(() => _showReading = !_showReading),
              onToggleChinese: () =>
                  setState(() => _showChinese = !_showChinese),
              onPlay: () => _playVoice(),
              onSlowPlay: () => _playVoice(
                speed: LocalMediaService.slowedRecordingSpeed,
              ),
            ),
            if (_heard) ...[
              const SizedBox(height: 16),
              _TryItHeader(focus: segments[focusIndex].text),
              const SizedBox(height: 10),
              RecordingControl(
                media: widget.media,
                prefix: 'child_reply',
                label: '按一下，跟著${_referenceVoiceLabel(story)}說',
                playful: true,
                maxSeconds: 10,
                onRecorded: _handleRecorded,
                onMetrics: _handleMetrics,
              ),
              if (_feedback != null) ...[
                const SizedBox(height: 14),
                _CoachFeedbackCard(
                  feedback: _feedback!,
                  onReplayReference: () => _playVoice(),
                  speechCheckAvailable: story.lessonContent != null,
                  checkingSpeech: _checkingSpeech,
                  speechMessage: _speechMessage,
                  transcriptFeedback: _transcriptFeedback,
                  onToggleSpeechCheck: _toggleBrowserSpeechCheck,
                ),
              ],
              if (story.lessonContent?.patterns.isNotEmpty ?? false) ...[
                const SizedBox(height: 16),
                _PatternPracticeCard(
                  pattern: story.lessonContent!.patterns.first,
                  memoryTip: story.lessonContent!.memoryTipZh,
                  playing: _playing,
                  onPlayExample: _playExample,
                ),
              ],
              const SizedBox(height: 10),
              ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 4),
                title: const Text('麥克風不能用？'),
                subtitle: const Text('可以先寫下你想說的話'),
                childrenPadding: const EdgeInsets.only(bottom: 12),
                children: [
                  TextField(
                    controller: _childNote,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: '寫下自己想說的話',
                      hintText: story.vietnamese,
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const ValueKey('send-to-family'),
                onPressed:
                    (_replyPath == null && _childNote.text.trim().isEmpty) ||
                            _submitting
                        ? null
                        : _submit,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(58),
                  backgroundColor: AppColors.berry,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.send_rounded),
                label: Text(_submitting ? '正在保存…' : '存到這台裝置'),
              ),
              const SizedBox(height: 8),
              const Text(
                '節奏與聽寫結果只幫忙練習；家裡怎麼說，仍由家人親耳確認。',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StepRail extends StatelessWidget {
  const _StepRail({required this.currentStep});

  final int currentStep;

  @override
  Widget build(BuildContext context) {
    const steps = [
      (Icons.image_rounded, '看圖'),
      (Icons.hearing_rounded, '聽讀'),
      (Icons.mic_rounded, '跟說'),
      (Icons.stars_rounded, '拿星星'),
    ];
    return Row(
      children: [
        for (var index = 0; index < steps.length; index++) ...[
          if (index > 0)
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                height: 3,
                color: index <= currentStep ? AppColors.sun : AppColors.border,
              ),
            ),
          Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: index < currentStep
                      ? AppColors.jade
                      : index == currentStep
                          ? AppColors.sun
                          : Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: index <= currentStep
                        ? Colors.transparent
                        : AppColors.border,
                  ),
                ),
                child: Icon(
                  index < currentStep ? Icons.check_rounded : steps[index].$1,
                  color: index < currentStep ? Colors.white : AppColors.ink,
                  size: 19,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                steps[index].$2,
                style: TextStyle(
                  color: index == currentStep ? AppColors.ink : AppColors.muted,
                  fontSize: 11,
                  fontWeight:
                      index == currentStep ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _SceneCard extends StatelessWidget {
  const _SceneCard({required this.story});

  final FamilyStory story;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 225,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        color: AppColors.cream,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _LessonImage(story: story),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Color(0xAA182522)],
              ),
            ),
          ),
          Positioned(
            top: 14,
            left: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .92),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.auto_awesome_rounded,
                      color: AppColors.berry, size: 17),
                  const SizedBox(width: 5),
                  Text(
                    story.illustrationAsset == null ? '家庭情境圖' : '內建情境插圖',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 18,
            right: 18,
            bottom: 15,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  story.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 23,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '先看圖猜意思，不用一開始就只靠耳朵。',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .88),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LessonImage extends StatelessWidget {
  const _LessonImage({required this.story});

  final FamilyStory story;

  @override
  Widget build(BuildContext context) {
    final asset = story.illustrationAsset;
    if (asset != null) return Image.asset(asset, fit: BoxFit.cover);
    final photo = story.photoPath;
    if (photo != null) {
      if (kIsWeb) {
        return Image.network(
          photo,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const _SceneFallback(),
        );
      }
      if (File(photo).existsSync()) {
        return Image.file(File(photo), fit: BoxFit.cover);
      }
    }
    return const _SceneFallback();
  }
}

class _SceneFallback extends StatelessWidget {
  const _SceneFallback();

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFFF876C), Color(0xFFFFC857)],
          ),
        ),
        alignment: Alignment.center,
        child: const Icon(Icons.photo_camera_back_rounded,
            color: Colors.white, size: 72),
      );
}

class _PhraseTutorCard extends StatelessWidget {
  const _PhraseTutorCard({
    required this.story,
    required this.segments,
    required this.focusChunk,
    required this.showReading,
    required this.showChinese,
    required this.playing,
    required this.heard,
    required this.onChunkSelected,
    required this.onChunkPlay,
    required this.onChunkSlowPlay,
    required this.onToggleReading,
    required this.onToggleChinese,
    required this.onPlay,
    required this.onSlowPlay,
  });

  final FamilyStory story;
  final List<LessonSegment> segments;
  final int focusChunk;
  final bool showReading;
  final bool showChinese;
  final bool playing;
  final bool heard;
  final ValueChanged<int> onChunkSelected;
  final ValueChanged<LessonSegment> onChunkPlay;
  final ValueChanged<LessonSegment> onChunkSlowPlay;
  final VoidCallback onToggleReading;
  final VoidCallback onToggleChinese;
  final VoidCallback onPlay;
  final VoidCallback onSlowPlay;

  @override
  Widget build(BuildContext context) {
    final selectedSegment = segments[focusChunk];
    final referenceVoiceLabel = _referenceVoiceLabel(story);
    return Container(
      padding: const EdgeInsets.fromLTRB(19, 18, 19, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(
                  color: AppColors.berrySoft,
                  shape: BoxShape.circle,
                ),
                child:
                    const Icon(Icons.menu_book_rounded, color: AppColors.berry),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '今天只學這一句',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    Text(
                      '${story.languageName} · 初學輔助已開啟',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                key: const ValueKey('story-audio-source'),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: story.isSample || story.audioPath == null
                      ? AppColors.skySoft
                      : AppColors.jadeSoft,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  _audioSourceLabel(story),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 17),
          Text(
            story.vietnamese,
            key: const ValueKey('target-sentence'),
            style: const TextStyle(
              color: AppColors.ink,
              fontSize: 28,
              height: 1.25,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            child: showReading
                ? Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.berrySoft,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      '${story.pronunciationSystem}  ${story.pronunciationGuide ?? '這張舊卡尚未補上拼音'}',
                      key: const ValueKey('pronunciation-guide'),
                      style: const TextStyle(
                        color: AppColors.berry,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            child: showChinese
                ? Padding(
                    padding: const EdgeInsets.only(top: 9),
                    child: Text(
                      story.chinese,
                      key: const ValueKey('chinese-meaning'),
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 16,
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              FilterChip(
                selected: showReading,
                onSelected: (_) => onToggleReading(),
                avatar: const Icon(Icons.spellcheck_rounded, size: 17),
                label: Text(story.pronunciationSystem),
              ),
              FilterChip(
                selected: showChinese,
                onSelected: (_) => onToggleChinese(),
                avatar: const Icon(Icons.translate_rounded, size: 17),
                label: const Text('中文意思'),
              ),
            ],
          ),
          const Divider(height: 28),
          Row(
            children: [
              const Expanded(
                child: Text(
                  '點一小段：單獨聽，也看意思與發音提醒',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              if (story.lessonContent != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.jadeSoft,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: const Text(
                    '可分段播放',
                    style: TextStyle(
                      color: AppColors.jade,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var index = 0; index < segments.length; index++)
                ChoiceChip(
                  selected: focusChunk == index,
                  onSelected: (_) => onChunkSelected(index),
                  label: Text(segments[index].text),
                  avatar: CircleAvatar(
                    backgroundColor: focusChunk == index
                        ? AppColors.berry
                        : AppColors.berrySoft,
                    foregroundColor:
                        focusChunk == index ? Colors.white : AppColors.berry,
                    child: Text('${index + 1}'),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          _SegmentInspector(
            key: ValueKey('segment-${selectedSegment.id}'),
            segment: selectedSegment,
            coachIntro: story.lessonContent?.coachIntroZh,
            playing: playing,
            hasPreciseAudio: true,
            onPlay: () => onChunkPlay(selectedSegment),
            onSlowPlay: () => onChunkSlowPlay(selectedSegment),
          ),
          const Divider(height: 30),
          const Text(
            '再把兩段接回完整句',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  key: const ValueKey('play-family-voice'),
                  onPressed: playing ? null : onPlay,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.berry,
                    foregroundColor: Colors.white,
                  ),
                  icon: playing
                      ? const _SoundDots(active: true)
                      : Icon(
                          heard
                              ? Icons.replay_rounded
                              : Icons.play_arrow_rounded,
                        ),
                  label: Text(
                    playing
                        ? '正在播放…'
                        : heard
                            ? '再聽$referenceVoiceLabel'
                            : '聽$referenceVoiceLabel',
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: playing ? null : onSlowPlay,
                  icon: const Icon(Icons.slow_motion_video_rounded),
                  label: const Text('0.85× 較慢'),
                ),
              ),
            ],
          ),
          if (!heard) ...[
            const SizedBox(height: 9),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.touch_app_rounded, size: 17, color: AppColors.muted),
                SizedBox(width: 5),
                Text(
                  '短句、拼音與中文都可以先看，不必盲聽。',
                  style: TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

String _referenceVoiceLabel(FamilyStory story) {
  if (story.isSample) return '合成示範音';
  return story.audioPath == null ? '裝置示範音' : '家人原音';
}

String _audioSourceLabel(FamilyStory story) {
  if (story.isSample) return '合成示範音｜家庭版本未錄';
  return story.audioPath == null ? '家庭版本未錄｜裝置示範音' : '家人原音';
}

class _SegmentInspector extends StatelessWidget {
  const _SegmentInspector({
    required this.segment,
    required this.playing,
    required this.hasPreciseAudio,
    required this.onPlay,
    required this.onSlowPlay,
    this.coachIntro,
    super.key,
  });

  final LessonSegment segment;
  final bool playing;
  final bool hasPreciseAudio;
  final VoidCallback onPlay;
  final VoidCallback onSlowPlay;
  final String? coachIntro;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 230),
      child: Container(
        key: ValueKey(segment.id),
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFF4D8), Color(0xFFFFE9E4)],
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFFFD19A)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(
                  radius: 19,
                  backgroundColor: AppColors.coral,
                  foregroundColor: Colors.white,
                  child: Icon(Icons.auto_awesome_rounded, size: 19),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '短句拆解',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      Text(
                        '由教材預先整理',
                        style: TextStyle(color: AppColors.muted, fontSize: 10),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .8),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    segment.translationZh,
                    key: const ValueKey('segment-meaning'),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              segment.text,
              style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 3),
            Text(
              segment.romanization,
              style: const TextStyle(
                color: AppColors.berry,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (segment.wordBreakdownZh != null) ...[
              const SizedBox(height: 13),
              _LessonExplanationRow(
                icon: Icons.account_tree_rounded,
                title: '分詞解釋',
                body: segment.wordBreakdownZh!,
              ),
            ],
            if (segment.pronunciationTipsZh.isNotEmpty) ...[
              const SizedBox(height: 10),
              _LessonExplanationRow(
                icon: Icons.record_voice_over_rounded,
                title: '發音注意',
                body: segment.pronunciationTipsZh.join('\n'),
              ),
            ],
            if (coachIntro != null) ...[
              const SizedBox(height: 10),
              _LessonExplanationRow(
                icon: Icons.lightbulb_rounded,
                title: '怎麼記',
                body: coachIntro!,
              ),
            ],
            const SizedBox(height: 14),
            if (hasPreciseAudio)
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      key: ValueKey('play-segment-${segment.id}'),
                      onPressed: playing ? null : onPlay,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.coral,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.volume_up_rounded),
                      label: const Text('只聽這一段'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: playing ? null : onSlowPlay,
                    icon: const Icon(Icons.slow_motion_video_rounded),
                    label: const Text('慢速'),
                  ),
                ],
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .72),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline_rounded,
                        color: AppColors.muted, size: 18),
                    SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        '尚未由家人確認分段音檔；先播放完整句。',
                        style: TextStyle(color: AppColors.muted, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LessonExplanationRow extends StatelessWidget {
  const _LessonExplanationRow({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .74),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AppColors.berry, size: 20),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.berry,
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 3),
                  for (final line in body.split('\n'))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        body.contains('\n') ? '• $line' : line,
                        style: const TextStyle(height: 1.4),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _PatternPracticeCard extends StatelessWidget {
  const _PatternPracticeCard({
    required this.pattern,
    required this.playing,
    required this.onPlayExample,
    this.memoryTip,
  });

  final SentencePattern pattern;
  final String? memoryTip;
  final bool playing;
  final ValueChanged<LessonExample> onPlayExample;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 43,
                  height: 43,
                  decoration: BoxDecoration(
                    color: AppColors.jadeSoft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.extension_rounded,
                      color: AppColors.jade),
                ),
                const SizedBox(width: 11),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '常用句型變變變',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      Text(
                        '只換最後一格，就會多說三句',
                        style: TextStyle(color: AppColors.muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.auto_awesome_rounded, color: AppColors.jade),
              ],
            ),
            const SizedBox(height: 15),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.jadeSoft, AppColors.skySoft],
                ),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pattern.template,
                    key: const ValueKey('sentence-pattern'),
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(pattern.meaningZh),
                  if (pattern.usageTipZh != null) ...[
                    const SizedBox(height: 7),
                    Text(
                      pattern.usageTipZh!,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            for (var index = 0; index < pattern.examples.length; index++) ...[
              _PatternExampleRow(
                example: pattern.examples[index],
                playing: playing,
                onPlay: () => onPlayExample(pattern.examples[index]),
              ),
              if (index < pattern.examples.length - 1)
                const SizedBox(height: 8),
            ],
            if (memoryTip != null) ...[
              const SizedBox(height: 13),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.emoji_objects_rounded,
                      color: AppColors.sun, size: 21),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      memoryTip!,
                      style: const TextStyle(color: AppColors.muted),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      );
}

class _PatternExampleRow extends StatelessWidget {
  const _PatternExampleRow({
    required this.example,
    required this.playing,
    required this.onPlay,
  });

  final LessonExample example;
  final bool playing;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
        decoration: BoxDecoration(
          color: AppColors.paper,
          borderRadius: BorderRadius.circular(17),
        ),
        child: Row(
          children: [
            const CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.sunSoft,
              foregroundColor: AppColors.coral,
              child: Icon(Icons.chat_bubble_rounded, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    example.targetText,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  Text(
                    example.translationZh,
                    style:
                        const TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                  if (example.romanization != null)
                    Text(
                      example.romanization!,
                      style: const TextStyle(
                        color: AppColors.berry,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
            if (example.audio?.path != null)
              IconButton.filledTonal(
                tooltip: '播放例句',
                onPressed: playing ? null : onPlay,
                icon: const Icon(Icons.volume_up_rounded),
              ),
          ],
        ),
      );
}

class _TryItHeader extends StatelessWidget {
  const _TryItHeader({required this.focus});

  final String focus;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: AppColors.skySoft,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            const CircleAvatar(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.sky,
              child: Icon(Icons.record_voice_over_rounded),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '換你說一次',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  Text(
                    '先把「$focus」說清楚，再連成整句。',
                    style: const TextStyle(color: AppColors.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _CoachFeedbackCard extends StatelessWidget {
  const _CoachFeedbackCard({
    required this.feedback,
    required this.onReplayReference,
    required this.speechCheckAvailable,
    required this.checkingSpeech,
    required this.speechMessage,
    required this.transcriptFeedback,
    required this.onToggleSpeechCheck,
  });

  final PronunciationFeedback feedback;
  final VoidCallback onReplayReference;
  final bool speechCheckAvailable;
  final bool checkingSpeech;
  final String? speechMessage;
  final TranscriptFeedback? transcriptFeedback;
  final VoidCallback onToggleSpeechCheck;

  @override
  Widget build(BuildContext context) {
    final paceLabel = switch (feedback.pace) {
      PracticePace.tooFast => '稍快',
      PracticePace.steady => '接近示範',
      PracticePace.tooSlow => '稍慢',
      PracticePace.unavailable => '資料不足',
    };
    final understoodLabel = switch (transcriptFeedback?.level) {
      null => '可加測',
      TranscriptMatchLevel.understood => '找到整句文字',
      TranscriptMatchLevel.close => '找到大部分文字',
      TranscriptMatchLevel.partial => '只收到一部分',
      TranscriptMatchLevel.unavailable => '沒有聽寫文字',
    };
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFEEE8FF), Color(0xFFE4F2FF)],
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFFD6C9FF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 45,
                height: 45,
                decoration: const BoxDecoration(
                  color: AppColors.berry,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.psychology_alt_rounded,
                    color: Colors.white),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      '這次錄音的小提示',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    Text(
                      '只看節奏與收音，不打發音分數',
                      style: TextStyle(color: AppColors.muted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.auto_awesome_rounded, color: AppColors.berry),
            ],
          ),
          const SizedBox(height: 15),
          Text(
            feedback.headline,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _FeedbackMetric(
                  icon: Icons.speed_rounded,
                  label: '說話節奏',
                  value: paceLabel,
                  color: AppColors.jade,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: _FeedbackMetric(
                  icon: Icons.graphic_eq_rounded,
                  label: '收音狀態',
                  value: feedback.voiceLabel.startsWith('音量在建議範圍')
                      ? '音量適中'
                      : '可再調整',
                  color: AppColors.sky,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: _FeedbackMetric(
                  icon: Icons.hearing_rounded,
                  label: '系統聽到',
                  value: understoodLabel,
                  color: AppColors.coral,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .82),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '下一次只改一件事',
                  style: TextStyle(
                    color: AppColors.berry,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(feedback.nextTip),
                const SizedBox(height: 7),
                Text(
                  '${feedback.durationLabel} · ${feedback.voiceLabel}',
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 11),
          OutlinedButton.icon(
            onPressed: onReplayReference,
            icon: const Icon(Icons.compare_arrows_rounded),
            label: const Text('再聽示範，和我的錄音比較'),
          ),
          if (speechCheckAvailable) ...[
            const SizedBox(height: 9),
            FilledButton.icon(
              key: const ValueKey('browser-speech-check'),
              onPressed: onToggleSpeechCheck,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                backgroundColor:
                    checkingSpeech ? AppColors.coral : AppColors.berry,
                foregroundColor: Colors.white,
              ),
              icon: Icon(
                checkingSpeech ? Icons.stop_rounded : Icons.mic_rounded,
              ),
              label: Text(
                checkingSpeech ? '正在聽，說完可按停止' : '再說一次，看看系統聽成什麼',
              ),
            ),
            if (speechMessage != null) ...[
              const SizedBox(height: 9),
              Text(
                speechMessage!,
                style: const TextStyle(color: AppColors.coral, fontSize: 12),
              ),
            ],
            if (transcriptFeedback != null) ...[
              const SizedBox(height: 11),
              _TranscriptFeedbackView(feedback: transcriptFeedback!),
            ],
            const SizedBox(height: 8),
            const Text(
              '免 API 金鑰；Edge／Chrome 等裝置可能把這次語音送到瀏覽器供應商辨識。結果只表示「系統聽成什麼」，不是音素或聲調分數。',
              style:
                  TextStyle(color: AppColors.muted, fontSize: 10, height: 1.35),
            ),
          ],
          const SizedBox(height: 7),
          const Text(
            '節奏卡只檢查秒數與麥克風音量；免費聽寫只比對辨識文字。字音、聲調與家庭腔調仍由家人確認。',
            style: TextStyle(color: AppColors.muted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _TranscriptFeedbackView extends StatelessWidget {
  const _TranscriptFeedbackView({required this.feedback});

  final TranscriptFeedback feedback;

  @override
  Widget build(BuildContext context) {
    final color = switch (feedback.level) {
      TranscriptMatchLevel.understood => AppColors.jade,
      TranscriptMatchLevel.close => AppColors.sky,
      TranscriptMatchLevel.partial => AppColors.coral,
      TranscriptMatchLevel.unavailable => AppColors.muted,
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .88),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: color.withValues(alpha: .32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.chat_bubble_rounded, color: color, size: 20),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  feedback.headline,
                  style: TextStyle(color: color, fontWeight: FontWeight.w900),
                ),
              ),
              Icon(Icons.favorite_rounded, color: color, size: 19),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            feedback.transcript.isEmpty
                ? '系統沒有收到可辨識的文字'
                : '系統聽成：「${feedback.transcript}」',
            key: const ValueKey('speech-transcript'),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 5),
          Text(feedback.nextTip),
        ],
      ),
    );
  }
}

class _FeedbackMetric extends StatelessWidget {
  const _FeedbackMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 21),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.muted, fontSize: 9),
            ),
          ],
        ),
      );
}

class _CompletionView extends StatelessWidget {
  const _CompletionView({
    required this.recorded,
    required this.onDone,
    super.key,
  });

  final bool recorded;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFF0B7), AppColors.paper],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Wrap(
            spacing: 16,
            children: const [
              Icon(Icons.star_rounded, color: AppColors.sun, size: 34),
              Icon(Icons.circle, color: AppColors.sky, size: 13),
              Icon(Icons.star_rounded, color: AppColors.coral, size: 27),
            ],
          ),
          const SizedBox(height: 18),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: .65, end: 1),
            duration: const Duration(milliseconds: 650),
            curve: Curves.elasticOut,
            builder: (context, value, child) =>
                Transform.scale(scale: value, child: child),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 154,
                  height: 154,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppColors.berry, AppColors.sky],
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x337E57C2),
                        blurRadius: 28,
                        offset: Offset(0, 14),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.workspace_premium_rounded,
                    color: Colors.white, size: 78),
              ],
            ),
          ),
          const SizedBox(height: 26),
          Text(
            '短句挑戰完成！',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            recorded
                ? '你錄下的一句已保存在這台裝置。這是錄音紀錄，不會自動傳給家人。'
                : '你寫下的一句已保存在這台裝置。這次沒有錄音，所以只會顯示文字紀錄。',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 16,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.favorite_rounded, color: AppColors.coral),
                const SizedBox(width: 7),
                const Text('勇氣貼紙 +1',
                    style: TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(width: 12),
                const Icon(Icons.collections_bookmark_rounded,
                    color: AppColors.berry, size: 20),
                const SizedBox(width: 6),
                Text(
                  recorded ? '錄音紀錄 +1' : '文字紀錄 +1',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: onDone,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(58),
              backgroundColor: AppColors.jade,
            ),
            icon: const Icon(Icons.home_rounded),
            label: const Text('回到今天'),
          ),
        ],
      ),
    );
  }
}

class _SoundDots extends StatefulWidget {
  const _SoundDots({required this.active});

  final bool active;

  @override
  State<_SoundDots> createState() => _SoundDotsState();
}

class _SoundDotsState extends State<_SoundDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant _SoundDots oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _controller.repeat();
    } else if (!widget.active && oldWidget.active) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(5, (index) {
            final phase = _controller.value * math.pi * 2 + index * .8;
            final height = widget.active ? 7 + (math.sin(phase) + 1) * 5 : 6.0;
            return Container(
              width: 3,
              height: height,
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(99),
              ),
            );
          }),
        ),
      );
}
