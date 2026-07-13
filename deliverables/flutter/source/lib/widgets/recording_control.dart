import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../models/recording_metrics.dart';
import '../services/local_media_service.dart';

class RecordingControl extends StatefulWidget {
  const RecordingControl({
    required this.media,
    required this.prefix,
    required this.onRecorded,
    this.initialPath,
    this.label = '按一下，開始說',
    this.maxSeconds = 15,
    this.playful = false,
    this.onMetrics,
    super.key,
  });

  final LocalMediaService media;
  final String prefix;
  final ValueChanged<String?> onRecorded;
  final String? initialPath;
  final String label;
  final int maxSeconds;
  final bool playful;
  final ValueChanged<RecordingMetrics>? onMetrics;

  @override
  State<RecordingControl> createState() => _RecordingControlState();
}

class _RecordingControlState extends State<RecordingControl> {
  bool _recording = false;
  bool _busy = false;
  bool _playing = false;
  bool _pulse = false;
  int _countdown = 0;
  int _elapsedSeconds = 0;
  String? _path;
  Timer? _timer;
  StreamSubscription<double>? _amplitudeSubscription;
  final Stopwatch _recordingWatch = Stopwatch();
  double _amplitudeTotal = 0;
  double? _peakDb;
  int _amplitudeCount = 0;

  @override
  void initState() {
    super.initState();
    _path = widget.initialPath;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _amplitudeSubscription?.cancel();
    if (_recording) unawaited(widget.media.cancelRecording());
    super.dispose();
  }

  Future<void> _start() async {
    if (_busy || _recording) return;
    setState(() {
      _busy = true;
      _path = null;
      _elapsedSeconds = 0;
      _countdown = 3;
      _amplitudeTotal = 0;
      _amplitudeCount = 0;
      _peakDb = null;
    });
    widget.onRecorded(null);
    try {
      for (var value = 3; value > 0; value--) {
        if (!mounted) return;
        setState(() => _countdown = value);
        await Future<void>.delayed(const Duration(milliseconds: 450));
      }
      if (!mounted) return;
      await widget.media.startRecording(widget.prefix);
      _recordingWatch
        ..reset()
        ..start();
      _amplitudeSubscription = widget.media.amplitudeDbSamples().listen((db) {
        if (!db.isFinite || db <= -160) return;
        _amplitudeTotal += db;
        _amplitudeCount += 1;
        _peakDb = _peakDb == null ? db : (_peakDb! > db ? _peakDb! : db);
      });
      if (!mounted) {
        await widget.media.cancelRecording();
        return;
      }
      setState(() {
        _countdown = 0;
        _recording = true;
        _busy = false;
      });
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        final next = _elapsedSeconds + 1;
        setState(() {
          _elapsedSeconds = next;
          _pulse = !_pulse;
        });
        if (next >= widget.maxSeconds) unawaited(_stop());
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _countdown = 0;
      });
      _showError(error);
    }
  }

  Future<void> _stop() async {
    if (!_recording || _busy) return;
    _timer?.cancel();
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;
    _recordingWatch.stop();
    setState(() => _busy = true);
    try {
      final path = await widget.media.stopRecording();
      if (!mounted) return;
      setState(() {
        _recording = false;
        _busy = false;
        _path = path;
      });
      widget.onRecorded(path);
      if (path != null) {
        widget.onMetrics?.call(
          RecordingMetrics(
            duration: _recordingWatch.elapsed,
            averageDb:
                _amplitudeCount == 0 ? null : _amplitudeTotal / _amplitudeCount,
            peakDb: _peakDb,
          ),
        );
      }
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _recording = false;
        _busy = false;
      });
      _showError(error);
    }
  }

  Future<void> _play() async {
    final path = _path;
    if (path == null || _playing) return;
    setState(() => _playing = true);
    try {
      await widget.media.playLocal(path);
    } on Object catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _playing = false);
    }
  }

  void _showError(Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error.toString().replaceFirst('Bad state: ', '')),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasRecording = _path != null && !_recording;
    final background =
        widget.playful ? const Color(0xFFFFF2C7) : AppColors.cream;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
      decoration: BoxDecoration(
        color: _recording ? AppColors.coralSoft : background,
        borderRadius: BorderRadius.circular(widget.playful ? 28 : 20),
        border: Border.all(
          color: _recording ? AppColors.coral : Colors.transparent,
          width: 2,
        ),
      ),
      child: Column(
        children: [
          if (!hasRecording) ...[
            AnimatedContainer(
              duration: const Duration(milliseconds: 700),
              width: _pulse ? 112 : 100,
              height: _pulse ? 112 : 100,
              padding: EdgeInsets.all(_pulse ? 8 : 2),
              decoration: BoxDecoration(
                color: _recording
                    ? AppColors.coral.withValues(alpha: .14)
                    : AppColors.jade.withValues(alpha: .10),
                shape: BoxShape.circle,
              ),
              child: Semantics(
                container: true,
                explicitChildNodes: true,
                button: true,
                enabled: !_busy,
                label: _recording ? '停止錄音' : '開始錄音',
                child: Material(
                  color: _recording ? AppColors.coral : AppColors.jade,
                  shape: const CircleBorder(),
                  elevation: 3,
                  child: InkWell(
                    key: const ValueKey('record-toggle'),
                    customBorder: const CircleBorder(),
                    onTap: _busy ? null : (_recording ? _stop : _start),
                    child: Center(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: _countdown > 0
                            ? Text(
                                '$_countdown',
                                key: ValueKey(_countdown),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 34,
                                  fontWeight: FontWeight.w900,
                                ),
                              )
                            : Icon(
                                _recording
                                    ? Icons.stop_rounded
                                    : Icons.mic_rounded,
                                key: ValueKey(_recording),
                                color: Colors.white,
                                size: 42,
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _countdown > 0
                  ? '準備好囉…'
                  : _recording
                      ? '正在聽你說  $_elapsedSeconds 秒'
                      : widget.label,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              _recording
                  ? '說完按中間停止，最長 ${widget.maxSeconds} 秒'
                  : '聲音只留在這個瀏覽器，不會自動上傳',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.muted),
              textAlign: TextAlign.center,
            ),
            if (_recording) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: ExcludeSemantics(
                  child: LinearProgressIndicator(
                    value: _elapsedSeconds / widget.maxSeconds,
                    minHeight: 7,
                    backgroundColor: Colors.white70,
                    color: AppColors.coral,
                  ),
                ),
              ),
            ],
          ] else ...[
            const Icon(
              Icons.check_circle_rounded,
              color: AppColors.jade,
              size: 42,
            ),
            const SizedBox(height: 6),
            Text(
              '你的聲音收到了！',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            const Text(
              '先聽聽看，再決定要不要重錄。',
              style: TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    key: const ValueKey('play-recording'),
                    onPressed: _playing ? null : _play,
                    icon: Icon(
                      _playing
                          ? Icons.graphic_eq_rounded
                          : Icons.play_arrow_rounded,
                    ),
                    label: Text(_playing ? '播放中…' : '聽聽看'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _start,
                    icon: const Icon(Icons.replay_rounded),
                    label: const Text('重新錄'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
