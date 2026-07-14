import 'dart:async';

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../core/app_theme.dart';
import '../models/conversation_episode.dart';
import '../models/family_circle.dart';
import '../models/family_culture_prompt.dart';
import '../services/local_media_service.dart';

enum ConversationSpeechStatus {
  heard,
  unsupported,
  permissionDenied,
  noSpeech,
  failed,
}

enum _ReplyFlowPhase { manual, speaking, autoWaiting, paused }

class ConversationSpeechResult {
  const ConversationSpeechResult({
    required this.status,
    this.transcript = '',
    this.confidence,
  });

  const ConversationSpeechResult.heard(
    String transcript, {
    double? confidence,
  }) : this(
          status: ConversationSpeechStatus.heard,
          transcript: transcript,
          confidence: confidence,
        );

  const ConversationSpeechResult.unavailable(
    ConversationSpeechStatus status,
  ) : this(status: status);

  final ConversationSpeechStatus status;
  final String transcript;
  final double? confidence;
}

abstract interface class ConversationSpeechRecognizer {
  Future<ConversationSpeechResult> listen({
    required String languageTag,
    required Duration listenFor,
  });

  Future<void> stop();

  Future<void> dispose();
}

/// Key-free speech-to-text supplied by the device/browser. The transcript is
/// searched only for reviewed option keywords; it is not a pronunciation
/// assessment.
class DeviceConversationSpeechRecognizer
    implements ConversationSpeechRecognizer {
  DeviceConversationSpeechRecognizer({stt.SpeechToText? speech})
      : _speech = speech ?? stt.SpeechToText();

  final stt.SpeechToText _speech;
  Completer<ConversationSpeechResult>? _active;
  String _latestTranscript = '';
  double? _latestConfidence;
  bool _initialized = false;
  bool _captureStarted = false;

  @override
  Future<ConversationSpeechResult> listen({
    required String languageTag,
    required Duration listenFor,
  }) async {
    if (_active != null) {
      return const ConversationSpeechResult.unavailable(
        ConversationSpeechStatus.failed,
      );
    }
    _latestTranscript = '';
    _latestConfidence = null;
    final completer = Completer<ConversationSpeechResult>();
    _active = completer;

    try {
      if (!_initialized) {
        _initialized = await _speech.initialize(
          onStatus: (status) {
            if (_captureStarted &&
                (status == stt.SpeechToText.doneStatus ||
                    status == stt.SpeechToText.notListeningStatus)) {
              _completeWithLatest();
            }
          },
          onError: (error) {
            final errorCode = error.errorMsg.toLowerCase();
            final permissionProblem = errorCode.contains('permission') ||
                errorCode.contains('not-allowed') ||
                errorCode.contains('not_allowed');
            _complete(
              ConversationSpeechResult.unavailable(
                permissionProblem
                    ? ConversationSpeechStatus.permissionDenied
                    : ConversationSpeechStatus.failed,
              ),
            );
          },
        );
      }
      if (!_initialized) {
        _complete(
          const ConversationSpeechResult.unavailable(
            ConversationSpeechStatus.unsupported,
          ),
        );
        return await completer.future;
      }

      final normalizedTarget = languageTag.toLowerCase().replaceAll('_', '-');
      final languagePrefix = normalizedTarget.split('-').first;
      String? localeId;
      for (final locale in await _speech.locales()) {
        final normalized = locale.localeId.toLowerCase().replaceAll('_', '-');
        if (normalized == normalizedTarget ||
            normalized.startsWith('$languagePrefix-')) {
          localeId = locale.localeId;
          break;
        }
      }
      localeId ??= languageTag;

      _captureStarted = true;
      await _speech.listen(
        onResult: (result) {
          _latestTranscript = result.recognizedWords.trim();
          // speech_to_text uses 0 when a platform does not expose confidence.
          // Treat it as unknown instead of a low pronunciation score.
          if (result.hasConfidenceRating && result.confidence > 0) {
            _latestConfidence = result.confidence;
          }
          if (result.finalResult) _completeWithLatest();
        },
        listenOptions: stt.SpeechListenOptions(
          localeId: localeId,
          listenFor: listenFor,
          pauseFor: const Duration(seconds: 2),
          partialResults: true,
          cancelOnError: true,
          listenMode: stt.ListenMode.confirmation,
        ),
      );

      return await completer.future.timeout(
        listenFor + const Duration(seconds: 4),
        onTimeout: () {
          unawaited(_speech.stop());
          return _latestResult();
        },
      );
    } on Object {
      return const ConversationSpeechResult.unavailable(
        ConversationSpeechStatus.failed,
      );
    } finally {
      _captureStarted = false;
      if (identical(_active, completer)) _active = null;
    }
  }

  ConversationSpeechResult _latestResult() {
    if (_latestTranscript.isEmpty) {
      return const ConversationSpeechResult.unavailable(
        ConversationSpeechStatus.noSpeech,
      );
    }
    return ConversationSpeechResult.heard(
      _latestTranscript,
      confidence: _latestConfidence,
    );
  }

  void _completeWithLatest() => _complete(_latestResult());

  void _complete(ConversationSpeechResult result) {
    final active = _active;
    if (active != null && !active.isCompleted) active.complete(result);
  }

  @override
  Future<void> stop() async {
    await _speech.stop();
    _completeWithLatest();
  }

  @override
  Future<void> dispose() async {
    await _speech.cancel();
    _complete(
      const ConversationSpeechResult.unavailable(
        ConversationSpeechStatus.failed,
      ),
    );
  }
}

class ConversationTheaterScreen extends StatefulWidget {
  const ConversationTheaterScreen({
    super.key,
    required this.episode,
    required this.media,
    this.onStoryCardCreated,
    this.speechRecognizer,
    this.familyEpisodeVoice,
    this.familyEpisodeVoices = const [],
    this.autoPlayElderVoice = true,
    this.autoAdvanceReplies = false,
  });

  final ConversationEpisode episode;
  final LocalMediaService media;
  final FutureOr<void> Function(ConversationStoryCard card)? onStoryCardCreated;
  final ConversationSpeechRecognizer? speechRecognizer;

  /// Legacy single opening override retained for callers created before
  /// per-prompt family voices. New integrations should pass the episode list.
  final FamilyEpisodeVoice? familyEpisodeVoice;
  final List<FamilyEpisodeVoice> familyEpisodeVoices;
  final bool autoPlayElderVoice;

  /// Keeps legacy/test callers manually paced unless the product shell opts in.
  final bool autoAdvanceReplies;

  @override
  State<ConversationTheaterScreen> createState() =>
      _ConversationTheaterScreenState();
}

class _ConversationTheaterScreenState extends State<ConversationTheaterScreen> {
  static const _replyAutoAdvanceDelay = Duration(milliseconds: 2200);

  final ScrollController _pageScrollController = ScrollController();
  late final ConversationSpeechRecognizer _recognizer;
  late final bool _ownsRecognizer;
  late ConversationPrompt _prompt;
  late ConversationSceneSnapshot _scene;
  ConversationChoice? _preparedChoice;
  ConversationChoice? _elderResponse;
  final List<ConversationStoryMoment> _moments = [];
  bool _listening = false;
  bool _speaking = false;
  bool _elderLinePlayed = false;
  int _speechEpoch = 0;
  bool _completed = false;
  bool _storyCardDelivered = false;
  String? _repairMessage;
  bool _speechSelfConfirmAvailable = false;
  String? _familyVoiceFallbackPromptId;
  String? _bundledAudioFallbackText;
  Timer? _replyAutoAdvanceTimer;
  int _replyEpoch = 0;
  bool _replyPauseRequested = false;
  _ReplyFlowPhase _replyFlowPhase = _ReplyFlowPhase.manual;
  bool _lastResponseWasSpoken = false;
  ConversationStoryCard? _storyCard;

  FamilyEpisodeVoice? get _currentPromptFamilyVoice {
    final wantedPromptId =
        _prompt.id == widget.episode.openingPromptId ? null : _prompt.id;
    for (final voice in [
      if (widget.familyEpisodeVoice case final legacy?) legacy,
      ...widget.familyEpisodeVoices,
    ]) {
      if (voice.episodeId == widget.episode.id &&
          voice.promptId == wantedPromptId) {
        return voice;
      }
    }
    return null;
  }

  ConversationLine get _currentPromptElderLine {
    final voice = _currentPromptFamilyVoice;
    if (voice == null) return _prompt.elderLine;
    return ConversationLine(
      targetText: voice.targetText,
      translationZh: voice.translationZh,
      romanization: voice.romanization,
      audioPath: voice.localRecordingReference,
    );
  }

  String get _currentLineSourceLabel {
    final visibleLine = _elderResponse?.elderReply ?? _currentPromptElderLine;
    if (_bundledAudioFallbackText == visibleLine.targetText) {
      return '預錄示範暫不可用 · 裝置朗讀';
    }
    if (_familyVoiceFallbackPromptId == _prompt.id && _elderResponse == null) {
      return '家人原音暫不可用 · 裝置朗讀';
    }
    if (_elderResponse != null) {
      return _elderResponse!.elderReply.audioPath == null ? '裝置朗讀' : '預錄示範';
    }
    final voice = _currentPromptFamilyVoice;
    if (voice?.hasFamilyRecording ?? false) return '家人原音';
    if (voice != null) return '裝置朗讀 · 家庭說法';
    return _prompt.elderLine.audioPath == null ? '裝置朗讀' : '預錄示範';
  }

  @override
  void initState() {
    super.initState();
    _prompt = widget.episode.promptById(widget.episode.openingPromptId);
    _scene = widget.episode.openingScene;
    _ownsRecognizer = widget.speechRecognizer == null;
    _recognizer =
        widget.speechRecognizer ?? DeviceConversationSpeechRecognizer();
    if (widget.autoPlayElderVoice) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_speakLine(_currentPromptElderLine));
      });
    }
  }

  @override
  void dispose() {
    _replyAutoAdvanceTimer?.cancel();
    _replyEpoch += 1;
    _speechEpoch += 1;
    unawaited(_ignoreFailure(widget.media.stopPlayback()));
    if (_ownsRecognizer) unawaited(_ignoreFailure(_recognizer.dispose()));
    _pageScrollController.dispose();
    super.dispose();
  }

  Future<void> _speakLine(ConversationLine line) async {
    final request = ++_speechEpoch;
    if (_speaking) await widget.media.stopPlayback();
    if (!mounted || request != _speechEpoch) return;
    final visibleSceneLine =
        _elderResponse?.elderReply ?? _currentPromptElderLine;
    final isVisibleSceneLine = line.targetText == visibleSceneLine.targetText &&
        line.translationZh == visibleSceneLine.translationZh &&
        line.audioPath == visibleSceneLine.audioPath;
    final isFamilyRecording = line.audioPath != null &&
        line.audioPath == _currentPromptFamilyVoice?.localRecordingReference;
    if (mounted) {
      setState(() {
        _speaking = true;
        if (isVisibleSceneLine) _elderLinePlayed = true;
        _bundledAudioFallbackText = null;
        if (isFamilyRecording) _familyVoiceFallbackPromptId = null;
      });
    }
    try {
      if (line.audioPath case final path?) {
        try {
          await widget.media.playLocal(path);
        } on Object {
          if (isFamilyRecording) {
            await widget.media.speakText(
              line.targetText,
              languageTag: widget.episode.languageTag,
              rate: LocalMediaService.normalSpeechRate,
            );
            if (mounted && request == _speechEpoch) {
              setState(() {
                _familyVoiceFallbackPromptId = _prompt.id;
                _repairMessage = '這台裝置找不到家人原音，已改用裝置朗讀家庭說法；可以請家人之後重新錄一次。';
              });
            }
          } else if (path.startsWith('asset://')) {
            await widget.media.speakText(
              line.targetText,
              languageTag: widget.episode.languageTag,
              rate: LocalMediaService.normalSpeechRate,
            );
            if (mounted && request == _speechEpoch) {
              setState(() {
                _bundledAudioFallbackText = line.targetText;
                _repairMessage = '這台裝置找不到預錄示範，已改用裝置朗讀；若仍無聲音，可以看中文意思並請家人陪你念一次。';
              });
            }
          } else {
            rethrow;
          }
        }
      } else {
        await widget.media.speakText(
          line.targetText,
          languageTag: widget.episode.languageTag,
          rate: LocalMediaService.normalSpeechRate,
        );
      }
    } on Object {
      if (mounted && request == _speechEpoch) {
        setState(() {
          _repairMessage = '這台裝置暫時播不出這句。可以看中文意思與分段，請家人先陪你念一次。';
        });
      }
    } finally {
      if (mounted && request == _speechEpoch) {
        setState(() => _speaking = false);
      }
    }
  }

  Future<void> _toggleListening() async {
    if (_preparedChoice == null && !_listening) {
      setState(() {
        _repairMessage = '先選一個你想表達的意思，聽過短句後再開口。';
      });
      return;
    }
    if (_listening) {
      await _recognizer.stop();
      return;
    }
    _speechEpoch += 1;
    await _ignoreFailure(widget.media.stopPlayback());
    setState(() {
      _speaking = false;
      _listening = true;
      _repairMessage = null;
      _speechSelfConfirmAvailable = false;
    });
    final result = await _recognizer.listen(
      languageTag: widget.episode.languageTag,
      listenFor: const Duration(seconds: 8),
    );
    if (!mounted) return;
    setState(() => _listening = false);
    _handleSpeechResult(result);
  }

  void _handleSpeechResult(ConversationSpeechResult result) {
    if (result.status != ConversationSpeechStatus.heard) {
      final message = switch (result.status) {
        ConversationSpeechStatus.unsupported =>
          '這台裝置現在不能聽寫，但故事不用卡住。沒有文字不代表你念錯。',
        ConversationSpeechStatus.permissionDenied =>
          '麥克風還沒打開。可以請大人開啟權限，也可以用你先選的意思繼續。',
        ConversationSpeechStatus.noSpeech => '系統這次沒有寫出文字。可能是收音或瀏覽器限制，不代表你念錯。',
        ConversationSpeechStatus.failed => '這次聽寫沒有完成。可以慢速再聽，也可以照你先選的意思繼續。',
        ConversationSpeechStatus.heard => '',
      };
      setState(() {
        _repairMessage = message;
        _speechSelfConfirmAvailable = _preparedChoice != null;
      });
      return;
    }

    final transcript = result.transcript.trim();
    final matches = _prompt.matchingChoicesForTranscript(transcript);
    final prepared = _preparedChoice;
    if (prepared != null &&
        matches.length == 1 &&
        matches.single.id == prepared.id) {
      // The child already selected the intended meaning. A unique reviewed
      // phrase match may continue the story, but it is never a pronunciation
      // score; vendor confidence varies by browser and is deliberately ignored.
      _chooseIntent(prepared, transcript: transcript);
      return;
    }
    if (prepared != null) {
      setState(() {
        _repairMessage = transcript.isEmpty
            ? '系統這次沒有寫出文字。可能是瀏覽器、環境音或腔調差異，不代表你念錯。'
            : matches.length > 1
                ? '系統寫成「$transcript」，裡面像有兩個意思。這不代表你念錯，故事仍照你自己確認的意思走。'
                : matches.length == 1
                    ? '系統寫成「$transcript」，和你先選的意思不一樣。這只是瀏覽器聽寫，不代表你念錯。'
                    : '系統寫成「$transcript」，但沒找到完整關鍵詞。這只是瀏覽器聽寫，不代表你念錯。';
        _speechSelfConfirmAvailable = true;
      });
      return;
    }

    setState(() {
      _repairMessage = '先選你想表達的意思；系統只幫忙把聲音寫成字，不會替你決定。';
      _speechSelfConfirmAvailable = false;
    });
  }

  void _prepareChoice(ConversationChoice choice) {
    if (_elderResponse != null || _completed) return;
    setState(() {
      _preparedChoice = choice;
      _repairMessage = null;
      _speechSelfConfirmAvailable = false;
    });
    unawaited(_speakLine(choice.line));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageScrollController.hasClients) return;
      unawaited(
        _pageScrollController.animateTo(
          _pageScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        ),
      );
    });
  }

  void _chooseIntent(ConversationChoice choice, {String? transcript}) {
    if (_elderResponse != null || _completed) return;
    _invalidateReplyFlow();
    _moments.add(
      ConversationStoryMoment(
        choiceId: choice.id,
        emoji: choice.emoji,
        childLine: choice.line.targetText,
        translationZh: choice.line.translationZh,
        storyBeatZh: choice.storyBeatZh,
        transcript: transcript,
      ),
    );
    setState(() {
      _elderResponse = choice;
      _lastResponseWasSpoken = transcript != null;
      _scene = choice.sceneAfter;
      _repairMessage = null;
      _speechSelfConfirmAvailable = false;
      _replyPauseRequested = false;
      _replyFlowPhase = widget.autoAdvanceReplies
          ? _ReplyFlowPhase.speaking
          : _ReplyFlowPhase.manual;
    });
    if (widget.autoAdvanceReplies) {
      final epoch = _replyEpoch;
      unawaited(_speakReplyAndArmContinue(choice, epoch));
    } else {
      unawaited(_speakLine(choice.elderReply));
    }
  }

  bool get _requiresManualPacing {
    final media = MediaQuery.maybeOf(context);
    return media?.disableAnimations == true ||
        media?.accessibleNavigation == true;
  }

  Future<void> _speakReplyAndArmContinue(
    ConversationChoice response,
    int epoch,
  ) async {
    await _speakLine(response.elderReply);
    if (!mounted || epoch != _replyEpoch || _elderResponse?.id != response.id) {
      return;
    }
    if (_replyPauseRequested ||
        _requiresManualPacing ||
        _repairMessage != null) {
      setState(() {
        _replyFlowPhase = _replyPauseRequested
            ? _ReplyFlowPhase.paused
            : _ReplyFlowPhase.manual;
      });
      return;
    }
    setState(() => _replyFlowPhase = _ReplyFlowPhase.autoWaiting);
    _replyAutoAdvanceTimer = Timer(_replyAutoAdvanceDelay, () {
      if (!mounted ||
          epoch != _replyEpoch ||
          _replyFlowPhase != _ReplyFlowPhase.autoWaiting ||
          _elderResponse?.id != response.id) {
        return;
      }
      _continueStory();
    });
  }

  void _invalidateReplyFlow() {
    _replyAutoAdvanceTimer?.cancel();
    _replyAutoAdvanceTimer = null;
    _replyEpoch += 1;
  }

  Future<void> _pauseReplyFlow() async {
    if (_elderResponse == null) return;
    _replyPauseRequested = true;
    _invalidateReplyFlow();
    if (mounted) setState(() => _replyFlowPhase = _ReplyFlowPhase.paused);
    _speechEpoch += 1;
    await _ignoreFailure(widget.media.stopPlayback());
    if (mounted) setState(() => _speaking = false);
  }

  Future<void> _replaySceneLine(ConversationLine line) async {
    if (_elderResponse != null && widget.autoAdvanceReplies) {
      _replyPauseRequested = true;
      _invalidateReplyFlow();
      if (mounted) setState(() => _replyFlowPhase = _ReplyFlowPhase.paused);
    }
    await _speakLine(line);
  }

  void _continueStory() {
    final response = _elderResponse;
    if (response == null || _speaking) return;
    _invalidateReplyFlow();
    final nextId = response.nextPromptId;
    if (nextId == null) {
      _finishEpisode(response);
      return;
    }
    setState(() {
      _prompt = widget.episode.promptById(nextId);
      _preparedChoice = null;
      _elderResponse = null;
      _repairMessage = null;
      _speechSelfConfirmAvailable = false;
      _elderLinePlayed = false;
      _replyPauseRequested = false;
      _replyFlowPhase = _ReplyFlowPhase.manual;
    });
    if (widget.autoPlayElderVoice) {
      unawaited(_speakLine(_currentPromptElderLine));
    }
  }

  void _finishEpisode(ConversationChoice ending) {
    if (_completed) return;
    final now = DateTime.now();
    final card = ConversationStoryCard(
      id: '${widget.episode.id}-${now.microsecondsSinceEpoch}',
      episodeId: widget.episode.id,
      title: widget.episode.title,
      elderName: widget.episode.elderName,
      completedAt: now,
      endingTitleZh: ending.sceneAfter.headlineZh,
      endingEmoji: ending.sceneAfter.focusEmoji,
      moments: List.unmodifiable(_moments),
    );
    setState(() {
      _completed = true;
      _storyCard = card;
    });
    if (!_storyCardDelivered) {
      _storyCardDelivered = true;
      unawaited(_deliverStoryCard(card));
    }
  }

  Future<void> _deliverStoryCard(ConversationStoryCard card) async {
    await widget.onStoryCardCreated?.call(card);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('家庭對話劇場'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: _Pill(
                icon: Icons.schedule_rounded,
                label: '約 1 分鐘',
                color: AppColors.jadeSoft,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          controller: _pageScrollController,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: _completed ? _buildCelebration() : _buildEpisode(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEpisode() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.episode.title,
                      style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 3),
                  Text(widget.episode.subtitle,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: AppColors.muted)),
                ],
              ),
            ),
            _StoryProgress(
              current: _prompt.step,
              total: widget.episode.totalTurns,
            ),
          ],
        ),
        const SizedBox(height: 14),
        _buildScene(),
        const SizedBox(height: 14),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          child: _elderResponse == null
              ? _buildChildTurn()
              : _buildElderResponse(_elderResponse!),
        ),
      ],
    );
  }

  Widget _buildScene() {
    final line = _elderResponse?.elderReply ?? _currentPromptElderLine;
    return AnimatedContainer(
      key: ValueKey('scene-state-${_scene.id}'),
      duration: const Duration(milliseconds: 360),
      height: _elderResponse == null ? 438 : 370,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A253331),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const _SceneGradient(),
          if (widget.episode.illustrationAsset case final asset?)
            AnimatedScale(
              duration: const Duration(milliseconds: 720),
              curve: Curves.easeOutCubic,
              scale: _elderResponse == null ? 1 : 1.045,
              child: Image.asset(
                asset,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const _SceneGradient(),
                frameBuilder: (context, child, frame, wasSyncLoaded) {
                  if (wasSyncLoaded) return child;
                  return AnimatedSwitcher(
                    duration: const Duration(milliseconds: 320),
                    child: frame == null
                        ? const _SceneImageSkeleton(
                            key: ValueKey('scene-image-loading'),
                          )
                        : KeyedSubtree(
                            key: const ValueKey('scene-image-ready'),
                            child: child,
                          ),
                  );
                },
              ),
            ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 520),
            decoration: BoxDecoration(
              color: _sceneAccent(_scene.id).withValues(
                alpha: _elderResponse == null ? .055 : .04,
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x22000000), Color(0xB8253331)],
                stops: [.25, 1],
              ),
            ),
          ),
          if (_elderResponse case final response?)
            Positioned.fill(
              child: IgnorePointer(
                child: _SceneMagicBurst(key: ValueKey(response.id)),
              ),
            ),
          Positioned(
            left: 14,
            top: 14,
            child: _Pill(
              icon: Icons.auto_stories_rounded,
              label: _actLabel,
              color: Colors.white.withValues(alpha: .92),
            ),
          ),
          if (_elderResponse == null)
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Semantics(
                container: true,
                label: '點一個圖像，選擇你想告訴${widget.episode.elderName}的事',
                child: Row(
                  children: [
                    for (var index = 0;
                        index < _prompt.choices.length;
                        index++) ...[
                      if (index > 0) const SizedBox(width: 9),
                      Expanded(
                        child: KeyedSubtree(
                          key: ValueKey(
                            'scene-choice-${_prompt.choices[index].id}',
                          ),
                          child: _MeaningChoiceButton(
                            choice: _prompt.choices[index],
                            selected: _preparedChoice?.id ==
                                _prompt.choices[index].id,
                            onTap: () => _prepareChoice(_prompt.choices[index]),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          if (_elderResponse == null)
            Positioned(
              left: 18,
              top: 64,
              child: Semantics(
                label: widget.episode.elderName,
                child: Container(
                  width: 82,
                  height: 82,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.sunSoft,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 4),
                  ),
                  child: const Icon(
                    Icons.face_3_rounded,
                    size: 50,
                    color: AppColors.coral,
                  ),
                ),
              ),
            ),
          if (_elderResponse case final response?)
            Positioned(
              right: 20,
              top: 58,
              child: TweenAnimationBuilder<double>(
                key: ValueKey('elder-action-${response.id}'),
                tween: Tween(begin: .72, end: 1),
                duration: const Duration(milliseconds: 620),
                curve: Curves.elasticOut,
                builder: (context, scale, child) => Transform.scale(
                  scale: scale,
                  child: child,
                ),
                child: Semantics(
                  label:
                      '${widget.episode.elderName}正在回應：${response.elderReply.translationZh}',
                  child: Container(
                    width: 72,
                    height: 72,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.sun,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 4),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x33000000),
                          blurRadius: 18,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.waving_hand_rounded,
                      size: 38,
                      color: AppColors.coral,
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            left: 18,
            right: 18,
            bottom: _elderResponse == null ? 116 : 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  key: ValueKey('scene-elder-${_prompt.id}'),
                  liveRegion: _elderResponse != null,
                  label:
                      '${widget.episode.elderName}說：${line.targetText}，${line.translationZh}',
                  child: Container(
                    key: ValueKey(
                      'elder-speech-bubble-${_elderResponse?.id ?? _prompt.id}',
                    ),
                    padding: const EdgeInsets.fromLTRB(16, 13, 16, 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .95),
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x26000000),
                          blurRadius: 18,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${widget.episode.elderName}說',
                                style: const TextStyle(
                                  color: AppColors.jade,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            _VoiceSourcePill(label: _currentLineSourceLabel),
                            if (_elderLinePlayed) ...[
                              const SizedBox(width: 4),
                              IconButton(
                                key: const ValueKey('replay-elder-line'),
                                tooltip: '再聽一次',
                                constraints: const BoxConstraints(
                                  minWidth: 48,
                                  minHeight: 48,
                                ),
                                onPressed: _speaking
                                    ? null
                                    : () => unawaited(_replaySceneLine(line)),
                                icon: Icon(
                                  _speaking
                                      ? Icons.graphic_eq_rounded
                                      : Icons.volume_up_rounded,
                                ),
                              ),
                            ],
                          ],
                        ),
                        Text(
                          line.targetText,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontSize: 20),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          line.romanization,
                          key: const ValueKey('elder-line-romanization'),
                          style: const TextStyle(
                            color: AppColors.jade,
                            fontSize: 14,
                            height: 1.3,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          line.translationZh,
                          style: const TextStyle(color: AppColors.muted),
                        ),
                        if (!_elderLinePlayed) ...[
                          const SizedBox(height: 9),
                          FilledButton.icon(
                            key: const ValueKey('listen-elder-line'),
                            onPressed: _speaking
                                ? null
                                : () => unawaited(_replaySceneLine(line)),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(60),
                              tapTargetSize: MaterialTapTargetSize.padded,
                              backgroundColor: AppColors.jade,
                              foregroundColor: Colors.white,
                            ),
                            icon: const Icon(Icons.volume_up_rounded),
                            label: Text('點一下，聽${widget.episode.elderName}說'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  child: Container(
                    key: ValueKey('scene-${_scene.id}'),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      color: AppColors.ink.withValues(alpha: .86),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (var index = 0;
                                index < _scene.environmentEmojis.length;
                                index++) ...[
                              if (index > 0) const SizedBox(width: 4),
                              _EnvironmentStageIcon(
                                emoji: _scene.environmentEmojis[index],
                                color: _sceneAccent(
                                  '${_scene.id}-$index',
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${_scene.headlineZh}｜${_scene.descriptionZh}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String get _actLabel => switch (_prompt.step) {
        1 => '故事剛開始',
        2 => '故事走到一半',
        _ => '最後一幕',
      };

  List<String> _practiceSegments(ConversationLine line) {
    final segments = line.romanization
        .split('/')
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .toList(growable: true);
    // A final Vietnamese particle such as "ạ", "à" or "quá" changes the
    // sentence's tone. Synthesizing it alone sounds like a dictionary entry,
    // so keep every one-word ending attached to the phrase before it.
    while (segments.length > 1 &&
        segments.last.split(RegExp(r'\s+')).length == 1) {
      final ending = segments.removeLast();
      segments[segments.length - 1] = '${segments.last} $ending';
    }
    return segments;
  }

  Future<void> _playPracticeLine(
    ConversationLine line, {
    required double ttsRate,
    required double playbackSpeed,
  }) async {
    final request = ++_speechEpoch;
    await _ignoreFailure(widget.media.stopPlayback());
    if (!mounted || request != _speechEpoch) return;
    if (mounted) setState(() => _speaking = true);
    try {
      if (line.audioPath case final path?) {
        try {
          await widget.media.playLocal(path, speed: playbackSpeed);
        } on Object {
          if (!path.startsWith('asset://')) rethrow;
          await widget.media.speakText(
            line.targetText,
            languageTag: widget.episode.languageTag,
            rate: ttsRate,
          );
          if (mounted && request == _speechEpoch) {
            setState(() {
              _bundledAudioFallbackText = line.targetText;
              _repairMessage = '這台裝置找不到預錄示範，已改用裝置朗讀。';
            });
          }
        }
      } else {
        await widget.media.speakText(
          line.targetText,
          languageTag: widget.episode.languageTag,
          rate: ttsRate,
        );
      }
    } on Object {
      if (mounted && request == _speechEpoch) {
        setState(() {
          _repairMessage = '這台裝置暫時播不出練習聲音。短句與分段仍在畫面上，可以請家人先陪你念一次。';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('練習聲音暫時播不出來，已保留文字分段。')),
        );
      }
    } finally {
      if (mounted && request == _speechEpoch) {
        setState(() => _speaking = false);
      }
    }
  }

  Future<void> _openPracticeListeningTools(
    ConversationChoice choice,
  ) async {
    final segments = _practiceSegments(choice.line);
    var sheetSpeaking = false;
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          Future<void> playFromSheet(
            ConversationLine line, {
            required double ttsRate,
            required double playbackSpeed,
          }) async {
            if (sheetSpeaking) return;
            setSheetState(() => sheetSpeaking = true);
            await _playPracticeLine(
              line,
              ttsRate: ttsRate,
              playbackSpeed: playbackSpeed,
            );
            if (sheetContext.mounted) {
              setSheetState(() => sheetSpeaking = false);
            }
          }

          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              20,
              0,
              20,
              24 + MediaQuery.viewInsetsOf(sheetContext).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '慢慢聽這一句',
                  style: Theme.of(sheetContext).textTheme.headlineSmall,
                ),
                const SizedBox(height: 5),
                Text(
                  choice.line.targetText,
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
                Text(
                  choice.line.romanization,
                  style: const TextStyle(
                    color: AppColors.jade,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  key: ValueKey('practice-slow-${choice.id}'),
                  onPressed: sheetSpeaking
                      ? null
                      : () => unawaited(
                            playFromSheet(
                              choice.line,
                              ttsRate: LocalMediaService.slowSpeechRate,
                              playbackSpeed:
                                  LocalMediaService.slowedRecordingSpeed,
                            ),
                          ),
                  icon: Icon(
                    sheetSpeaking
                        ? Icons.graphic_eq_rounded
                        : Icons.slow_motion_video_rounded,
                  ),
                  label: Text(sheetSpeaking ? '播放中…' : '較慢再聽'),
                ),
                const SizedBox(height: 18),
                Text(
                  '逐段聽',
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
                const SizedBox(height: 3),
                const Text(
                  '點一段，只朗讀這個自然短語；句尾語氣詞會和前一段一起念。',
                  style: TextStyle(color: AppColors.muted),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var index = 0; index < segments.length; index++)
                      ActionChip(
                        key: ValueKey(
                          'practice-segment-${choice.id}-$index',
                        ),
                        avatar: const Icon(Icons.volume_up_rounded, size: 18),
                        label: Text(segments[index]),
                        onPressed: sheetSpeaking
                            ? null
                            : () => unawaited(
                                  playFromSheet(
                                    ConversationLine(
                                      targetText: segments[index],
                                      translationZh: '讀音分段',
                                      romanization: segments[index],
                                    ),
                                    ttsRate:
                                        LocalMediaService.segmentSpeechRate,
                                    playbackSpeed: 1,
                                  ),
                                ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.jadeSoft,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Text(
                    '來源說明：逐段取自畫面上的「／」讀音提示；單獨的句尾語氣詞會接回前一段，避免念成字典單字。固定由裝置朗讀，不是假裝切開家人原音，也不是發音評分。',
                    style: TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const ValueKey('close-practice-listening'),
                  onPressed: () => Navigator.pop(sheetContext),
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('關閉慢速聆聽'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildChildTurn() {
    final prepared = _preparedChoice;
    if (prepared == null && _repairMessage == null) {
      return Container(
        key: ValueKey('child-turn-${_prompt.id}'),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.jadeSoft,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.jade.withValues(alpha: .22)),
        ),
        child: const Row(
          children: [
            Icon(Icons.touch_app_rounded, color: AppColors.jade, size: 26),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                '先點圖裡的一幕；選好後才會出現聆聽、慢速練習與麥克風。',
                style: TextStyle(
                  color: AppColors.jade,
                  fontWeight: FontWeight.w800,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Card(
      key: ValueKey('child-turn-${_prompt.id}'),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.touch_app_rounded, color: AppColors.jade),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    prepared == null ? '點圖接故事' : '你選了這個場景',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              prepared == null
                  ? '直接點上方兩個圖像選擇；選好後再決定要不要開口。'
                  : '「${prepared.line.translationZh}」— 可以先聽、慢慢練，或直接讓${widget.episode.elderName}回話。',
              style: const TextStyle(color: AppColors.muted),
            ),
            if (_repairMessage case final message?) ...[
              const SizedBox(height: 12),
              Container(
                key: const ValueKey('speech-repair'),
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: AppColors.sunSoft,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.hearing_rounded,
                          size: 27,
                          color: AppColors.coral,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            message,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    if (_speechSelfConfirmAvailable && prepared != null) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        key: const ValueKey('speech-pronunciation-help'),
                        onPressed: () => unawaited(
                          _openPracticeListeningTools(prepared),
                        ),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                        icon: const Icon(Icons.slow_motion_video_rounded),
                        label: const Text('先慢速・逐段聽，再試一次'),
                      ),
                      const SizedBox(height: 8),
                      FilledButton.tonalIcon(
                        key: const ValueKey('speech-self-confirm'),
                        onPressed: () => _chooseIntent(prepared),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                        icon: const Icon(Icons.check_circle_rounded),
                        label: Text(
                          '我說的是「${prepared.line.translationZh}」，繼續故事',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            if (prepared != null) ...[
              const SizedBox(height: 14),
              _PracticeCoach(
                choice: prepared,
                speaking: _speaking,
                onListen: () => unawaited(_speakLine(prepared.line)),
                onOpenListeningTools: () =>
                    unawaited(_openPracticeListeningTools(prepared)),
              ),
              const SizedBox(height: 12),
            ] else ...[
              const SizedBox(height: 12),
              const Text(
                '圖像按鈕就在舞台下方，不必先讀完整外語句子。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.jade,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
            ],
            Text(
              '系統只幫你把聲音寫成字；你想說什麼由你確認，家裡怎麼說由家人確認。聽寫不準也不會卡住故事。',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.muted, fontSize: 12),
            ),
            const SizedBox(height: 6),
            Semantics(
              container: true,
              button: true,
              enabled: prepared != null,
              excludeSemantics: true,
              onTap: prepared == null ? null : _toggleListening,
              label: _listening
                  ? '停止聽寫'
                  : prepared == null
                      ? '先選意思才能開啟麥克風'
                      : '開啟麥克風說練習短句',
              child: FilledButton.icon(
                key: const ValueKey('theater-microphone'),
                onPressed: prepared == null ? null : _toggleListening,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(66),
                  backgroundColor:
                      _listening ? AppColors.coral : AppColors.jade,
                  textStyle: const TextStyle(
                    fontFamily: 'NotoSansTC',
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                icon: Icon(
                  _listening ? Icons.stop_circle_rounded : Icons.mic_rounded,
                  size: 28,
                ),
                label: Text(
                  _listening
                      ? '正在聽，說完再點一下'
                      : prepared == null
                          ? '先選意思，再開口'
                          : '我準備好了，換我說',
                ),
              ),
            ),
            const SizedBox(height: 8),
            KeyedSubtree(
              key: const ValueKey('toggle-intent-hints'),
              child: OutlinedButton.icon(
                key: const ValueKey('continue-with-scene-choice'),
                onPressed:
                    prepared == null ? null : () => _chooseIntent(prepared),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                ),
                icon: const Icon(Icons.image_rounded),
                label: Text(
                  prepared == null
                      ? '先點圖中的一個場景'
                      : '不開麥克風，用這張圖讓${widget.episode.elderName}回話',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildElderResponse(ConversationChoice response) {
    final heardTranscript = _lastResponseWasSpoken && _moments.isNotEmpty
        ? _moments.last.transcript
        : null;
    return Card(
      key: ValueKey('elder-response-${response.id}'),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              key: ValueKey('story-consequence-${_scene.id}'),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.jadeSoft,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.auto_awesome_rounded,
                    color: AppColors.jade,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${widget.episode.elderName}已在圖上回話',
                          style: TextStyle(
                            color: AppColors.jade,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          _scene.headlineZh,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          heardTranscript == null
                              ? '你用圖卡選了「${response.line.translationZh}」。'
                              : '聽寫文字：$heardTranscript｜故事依你確認的「${response.line.translationZh}」前進。',
                          style: const TextStyle(color: AppColors.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _buildReplyControls(response),
          ],
        ),
      ),
    );
  }

  Widget _buildReplyControls(ConversationChoice response) {
    final finishesEpisode = response.nextPromptId == null;
    if (widget.autoAdvanceReplies &&
        _replyFlowPhase == _ReplyFlowPhase.speaking) {
      return Semantics(
        liveRegion: true,
        child: Row(
          children: [
            const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${widget.episode.elderName}正在回你…',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            TextButton.icon(
              key: const ValueKey('pause-story-auto-advance'),
              onPressed: _pauseReplyFlow,
              icon: const Icon(Icons.pause_rounded),
              label: const Text('先停一下'),
            ),
          ],
        ),
      );
    }
    if (widget.autoAdvanceReplies &&
        _replyFlowPhase == _ReplyFlowPhase.autoWaiting) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  finishesEpisode ? '故事要收尾了…' : '故事自己接下去…',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              TextButton.icon(
                key: const ValueKey('pause-story-auto-advance'),
                onPressed: _pauseReplyFlow,
                icon: const Icon(Icons.pause_rounded),
                label: const Text('先停一下'),
              ),
            ],
          ),
          TweenAnimationBuilder<double>(
            key: const ValueKey('story-auto-advance-progress'),
            duration: _replyAutoAdvanceDelay,
            tween: Tween(begin: 0, end: 1),
            builder: (context, value, _) => LinearProgressIndicator(
              value: value,
              minHeight: 7,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            key: const ValueKey('continue-theater-story'),
            onPressed: _continueStory,
            icon: Icon(finishesEpisode
                ? Icons.celebration_rounded
                : Icons.fast_forward_rounded),
            label: Text(finishesEpisode ? '馬上收好故事' : '馬上接下去'),
          ),
        ],
      );
    }
    return FilledButton.icon(
      key: const ValueKey('continue-theater-story'),
      onPressed: _speaking ? null : _continueStory,
      icon: Icon(finishesEpisode
          ? Icons.celebration_rounded
          : Icons.arrow_forward_rounded),
      label: Text(
        _speaking
            ? '${widget.episode.elderName}正在回你…'
            : _replyFlowPhase == _ReplyFlowPhase.paused
                ? '我看完了，接著演'
                : finishesEpisode
                    ? '完成這一集'
                    : '看接下來發生什麼',
      ),
    );
  }

  Widget _buildCelebration() {
    final card = _storyCard!;
    return Column(
      key: const ValueKey('theater-celebration'),
      children: [
        const SizedBox(height: 18),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: .55, end: 1),
          duration: const Duration(milliseconds: 650),
          curve: Curves.elasticOut,
          builder: (_, scale, child) => Transform.scale(
            scale: scale,
            child: child,
          ),
          child: Container(
            width: 118,
            height: 118,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.sunSoft,
              shape: BoxShape.circle,
            ),
            child: _StageGlyph(emoji: card.endingEmoji, size: 66),
          ),
        ),
        const SizedBox(height: 18),
        Text('我們把故事演完了！',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 6),
        Text(
          '沒有分數，因為你真的讓故事往前走了。',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.muted),
        ),
        const SizedBox(height: 18),
        Container(
          key: const ValueKey('generated-story-card'),
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFFF1BF), Color(0xFFFFE5DE)],
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: const [
              BoxShadow(color: Color(0x18000000), blurRadius: 18),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _Pill(
                icon: Icons.auto_stories_rounded,
                label: '今天的家庭故事卡',
                color: Colors.white,
              ),
              const SizedBox(height: 14),
              Text(card.title,
                  style: Theme.of(context).textTheme.headlineMedium),
              Text(card.endingTitleZh,
                  style: const TextStyle(
                    color: AppColors.coral,
                    fontWeight: FontWeight.w800,
                  )),
              const SizedBox(height: 14),
              for (final moment in card.moments)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _StageGlyph(emoji: moment.emoji, size: 26),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(moment.childLine,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800)),
                            Text(moment.translationZh,
                                style: const TextStyle(color: AppColors.muted)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              const Divider(),
              Text(card.shareMessageZh),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .72),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.record_voice_over_rounded,
                      color: AppColors.jade,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '今晚問問家人',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                          Text(
                            familyCulturePromptForEpisode(widget.episode.id),
                            style: const TextStyle(color: AppColors.muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () => Navigator.maybePop(context, card),
          icon: const Icon(Icons.home_rounded),
          label: const Text('帶著故事卡回家'),
        ),
      ],
    );
  }
}

Future<void> _ignoreFailure(Future<void> work) async {
  try {
    await work;
  } on Object {
    // Optional media and device speech plugins must never break the story.
  }
}

class _MeaningChoiceButton extends StatelessWidget {
  const _MeaningChoiceButton({
    required this.choice,
    required this.selected,
    required this.onTap,
  });

  final ConversationChoice choice;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '圖像選擇「${choice.line.translationZh}」；選取後可以開口或直接繼續故事',
      child: Material(
        color: selected ? AppColors.jadeSoft : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: selected ? AppColors.jade : AppColors.border,
            width: selected ? 2.5 : 1.5,
          ),
        ),
        child: InkWell(
          key: ValueKey('prepare-${choice.id}'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            child: Column(
              children: [
                _StageGlyph(emoji: choice.emoji, size: 31),
                const SizedBox(height: 5),
                Text(
                  choice.line.translationZh,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(
                  selected ? '已選・等你接故事' : '點圖選這一幕',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: selected ? AppColors.jade : AppColors.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PracticeCoach extends StatelessWidget {
  const _PracticeCoach({
    required this.choice,
    required this.speaking,
    required this.onListen,
    required this.onOpenListeningTools,
  });

  final ConversationChoice choice;
  final bool speaking;
  final VoidCallback onListen;
  final VoidCallback onOpenListeningTools;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey('practice-coach-${choice.id}'),
      padding: const EdgeInsets.fromLTRB(15, 14, 10, 14),
      decoration: BoxDecoration(
        color: AppColors.jadeSoft,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.jade.withValues(alpha: .28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _StageGlyph(emoji: choice.emoji, size: 36),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      choice.line.targetText,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontSize: 20,
                            height: 1.2,
                          ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      choice.line.romanization,
                      style: const TextStyle(
                        color: AppColors.jade,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      choice.line.translationZh,
                      style: const TextStyle(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                key: ValueKey('practice-listen-${choice.id}'),
                onPressed: speaking ? null : onListen,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 48),
                ),
                icon: Icon(
                  speaking ? Icons.graphic_eq_rounded : Icons.volume_up_rounded,
                ),
                label: Text(speaking ? '播放中…' : '先聽整句'),
              ),
              OutlinedButton.icon(
                key: ValueKey('practice-listening-tools-${choice.id}'),
                onPressed: speaking ? null : onOpenListeningTools,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 48),
                ),
                icon: const Icon(Icons.hearing_rounded),
                label: const Text('慢速・逐段學'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '跟讀三步：先聽整句 → 只練一小段 → 回來說整句。這是練習提示，不是發音評分。',
            style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _StoryProgress extends StatelessWidget {
  const _StoryProgress({required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '故事進度',
      value: switch (current) {
        1 => '剛開始',
        2 => '走到一半',
        _ => '最後一幕',
      },
      child: Row(
        children: List.generate(
          total,
          (index) => AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: index + 1 == current ? 28 : 10,
            height: 10,
            margin: const EdgeInsets.only(left: 5),
            decoration: BoxDecoration(
              color: index + 1 <= current ? AppColors.coral : AppColors.border,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
        ),
      ),
    );
  }
}

class _VoiceSourcePill extends StatelessWidget {
  const _VoiceSourcePill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final familyAudio = label == '家人原音';
    return Semantics(
      label: '這一句使用$label',
      child: Container(
        key: ValueKey('elder-voice-source-$label'),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: familyAudio ? AppColors.coralSoft : AppColors.jadeSoft,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              familyAudio ? Icons.family_restroom_rounded : Icons.phone_android,
              size: 13,
              color: familyAudio ? AppColors.coral : AppColors.jade,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: familyAudio ? AppColors.coral : AppColors.jade,
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.ink),
          const SizedBox(width: 5),
          Text(label,
              style: const TextStyle(
                  color: AppColors.ink,
                  fontSize: 12,
                  fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _SceneImageSkeleton extends StatelessWidget {
  const _SceneImageSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFDDEEFF), Color(0xFFFFF1BF), Color(0xFFFFE5DE)],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image_rounded, size: 42, color: Colors.white70),
            SizedBox(height: 10),
            DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white70,
                borderRadius: BorderRadius.all(Radius.circular(99)),
              ),
              child: SizedBox(width: 72, height: 7),
            ),
          ],
        ),
      ),
    );
  }
}

class _EnvironmentStageIcon extends StatelessWidget {
  const _EnvironmentStageIcon({required this.emoji, required this.color});

  final String emoji;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 25,
      height: 25,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .9),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white70),
      ),
      child: Icon(_stageIconForEmoji(emoji), size: 15, color: Colors.white),
    );
  }
}

class _StageGlyph extends StatelessWidget {
  const _StageGlyph({required this.emoji, required this.size});

  final String emoji;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Icon(
      _stageIconForEmoji(emoji),
      size: size,
      color: AppColors.coral,
    );
  }
}

const _sceneAccents = <Color>[
  Color(0xFF2D7A6E),
  Color(0xFFE96F51),
  Color(0xFF4A90D9),
  Color(0xFFE6A52E),
  Color(0xFF8A68B8),
  Color(0xFF4C9B58),
];

int _sceneSeed(String id) => id.codeUnits
    .fold<int>(0, (total, unit) => (total * 31 + unit) & 0x7fffffff);

Color _sceneAccent(String id) =>
    _sceneAccents[_sceneSeed(id) % _sceneAccents.length];

IconData _stageIconForEmoji(String emoji) {
  if (emoji.contains('🚪')) return Icons.door_front_door_rounded;
  if (emoji.contains('👵')) return Icons.face_3_rounded;
  if (emoji.contains('🎒')) return Icons.backpack_rounded;
  if (emoji.contains('🌧') || emoji.contains('💧') || emoji.contains('🫗')) {
    return Icons.water_drop_rounded;
  }
  if (emoji.contains('🛋') || emoji.contains('💤')) {
    return Icons.weekend_rounded;
  }
  if (emoji.contains('📚') || emoji.contains('📒') || emoji.contains('📖')) {
    return Icons.menu_book_rounded;
  }
  if (emoji.contains('🧑') || emoji.contains('👨') || emoji.contains('🙋')) {
    return Icons.groups_rounded;
  }
  if (emoji.contains('🥤')) return Icons.local_drink_rounded;
  if (emoji.contains('👐') || emoji.contains('🫧')) {
    return Icons.clean_hands_rounded;
  }
  if (emoji.contains('🍚') ||
      emoji.contains('🥣') ||
      emoji.contains('🥢') ||
      emoji.contains('🥖') ||
      emoji.contains('🍌') ||
      emoji.contains('🍲')) {
    return Icons.restaurant_rounded;
  }
  if (emoji.contains('🌱') ||
      emoji.contains('🪴') ||
      emoji.contains('🌿') ||
      emoji.contains('🌼') ||
      emoji.contains('🫘')) {
    return Icons.local_florist_rounded;
  }
  if (emoji.contains('🌙')) return Icons.bedtime_rounded;
  if (emoji.contains('🐯')) return Icons.pets_rounded;
  if (emoji.contains('🧸')) return Icons.toys_rounded;
  if (emoji.contains('🌤') || emoji.contains('☀') || emoji.contains('💛')) {
    return Icons.wb_sunny_rounded;
  }
  if (emoji.contains('💙')) return Icons.water_rounded;
  if (emoji.contains('💗') || emoji.contains('💞') || emoji.contains('🫂')) {
    return Icons.favorite_rounded;
  }
  if (emoji.contains('♨')) return Icons.thermostat_rounded;
  if (emoji.contains('😮') || emoji.contains('🥱')) {
    return Icons.bedtime_rounded;
  }
  if (emoji.contains('😄') || emoji.contains('😋')) {
    return Icons.sentiment_very_satisfied_rounded;
  }
  if (emoji.contains('💛') || emoji.contains('💙')) {
    return Icons.checkroom_rounded;
  }
  return Icons.auto_awesome_rounded;
}

class _SceneMagicBurst extends StatelessWidget {
  const _SceneMagicBurst({super.key});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 760),
      curve: Curves.easeOutBack,
      builder: (context, value, child) => Opacity(
        opacity: value.clamp(0, 1),
        child: Transform.scale(scale: .72 + value * .28, child: child),
      ),
      child: const Stack(
        children: [
          Positioned(
            top: 26,
            left: 128,
            child: Icon(
              Icons.auto_awesome_rounded,
              color: AppColors.sun,
              size: 32,
            ),
          ),
          Positioned(
            top: 92,
            right: 118,
            child: Icon(
              Icons.star_rounded,
              color: Colors.white,
              size: 25,
            ),
          ),
          Positioned(
            top: 145,
            left: 102,
            child: Icon(
              Icons.favorite_rounded,
              color: AppColors.coral,
              size: 24,
            ),
          ),
        ],
      ),
    );
  }
}

class _SceneGradient extends StatelessWidget {
  const _SceneGradient();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFDDEEFF), Color(0xFFFFE5DE)],
        ),
      ),
    );
  }
}
