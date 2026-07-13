import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../models/lesson_content.dart';
import '../models/task_draft.dart';
import '../services/app_store.dart';
import '../services/local_media_service.dart';
import '../services/local_task_engine.dart';
import '../widgets/recording_control.dart';

class CreateStoryScreen extends StatefulWidget {
  const CreateStoryScreen({
    required this.store,
    required this.media,
    required this.onCreated,
    super.key,
  });

  final AppStore store;
  final LocalMediaService media;
  final VoidCallback onCreated;

  @override
  State<CreateStoryScreen> createState() => _CreateStoryScreenState();
}

class _CreateStoryScreenState extends State<CreateStoryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _object = TextEditingController();
  final _vietnamese = TextEditingController();
  final _chinese = TextEditingController();
  final _pronunciation = TextEditingController();
  final _promptZh = TextEditingController();
  final _promptVi = TextEditingController();
  final _keywords = TextEditingController();
  final _challengeQuestion = TextEditingController();
  final _cultureNote = TextEditingController();
  final LocalTaskEngine _engine = const LocalTaskEngine();
  TaskDraft? _draft;
  String? _audioPath;
  String? _photoPath;
  bool _familyConfirmed = false;
  bool _textOnlyBackup = false;
  bool _saving = false;
  bool _addFamilyChallenge = true;
  int _formGeneration = 0;
  String _languageName = '越南語';
  String _pronunciationSystem = '羅馬字分詞';

  @override
  void dispose() {
    _title.dispose();
    _object.dispose();
    _vietnamese.dispose();
    _chinese.dispose();
    _pronunciation.dispose();
    _promptZh.dispose();
    _promptVi.dispose();
    _keywords.dispose();
    _challengeQuestion.dispose();
    _cultureNote.dispose();
    super.dispose();
  }

  void _generateDraft() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final draft = _engine.generate(
      objectName: _object.text,
      vietnamese: _vietnamese.text,
      chinese: _chinese.text,
    );
    setState(() {
      _draft = draft;
      _promptZh.text = draft.promptZh;
      _promptVi.text = draft.promptVi;
      _keywords.text = draft.keyPhrases.join('、');
      _familyConfirmed = false;
      if (_challengeQuestion.text.trim().isEmpty) {
        _challengeQuestion.text = '家人問：哪一個是「${_cleanChoice(_chinese.text)}」？';
      }
      if (_cultureNote.text.trim().isEmpty) {
        _cultureNote.text = '這句話在我們家通常什麼時候會說？完成後，可以請家人講一個小故事。';
      }
    });
  }

  void _invalidateDraft(String _) {
    if (_draft == null) return;
    setState(() {
      _draft = null;
      _familyConfirmed = false;
      _promptZh.clear();
      _promptVi.clear();
      _keywords.clear();
    });
  }

  Future<void> _choosePhoto(bool camera) async {
    try {
      final path = await widget.media.capturePhoto(useCamera: camera);
      if (path != null && mounted) setState(() => _photoPath = path);
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> _save() async {
    final draft = _draft;
    if (draft == null) return;
    if (_audioPath == null && !_textOnlyBackup) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('請錄下家人的聲音，或選擇文字備援。')));
      return;
    }
    if (!_familyConfirmed) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('請說這句話的家人先看過練習內容。')));
      return;
    }
    if (_promptZh.text.trim().isEmpty || _promptVi.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('中越任務內容不能空白。')));
      return;
    }
    final reviewedKeywords = _parseKeywords(_keywords.text);
    if (reviewedKeywords.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('請留下至少一個想練的詞。')));
      return;
    }
    if (_addFamilyChallenge &&
        (_challengeQuestion.text.trim().isEmpty ||
            _cultureNote.text.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請留下加碼題與一小段家庭提示，或關閉家人加碼題。')),
      );
      return;
    }
    setState(() => _saving = true);
    final reviewedDraft = TaskDraft(
      promptZh: _promptZh.text.trim(),
      promptVi: _promptVi.text.trim(),
      keyPhrases: reviewedKeywords,
      confidence: draft.confidence,
      explanation: draft.explanation,
    );
    await widget.store.addStory(
      title: _title.text,
      objectName: _object.text,
      vietnamese: _vietnamese.text,
      chinese: _chinese.text,
      draft: reviewedDraft,
      humanConfirmed: true,
      audioPath: _audioPath,
      photoPath: _photoPath,
      languageName: _languageName,
      languageTag: switch (_languageName) {
        '越南語' => 'vi-VN',
        '臺灣台語' => 'nan-TW',
        '客語' => 'hak-TW',
        _ => 'und',
      },
      pronunciationGuide: _pronunciation.text.trim().isEmpty
          ? _vietnamese.text.trim()
          : _pronunciation.text,
      pronunciationSystem: _pronunciationSystem,
      practiceChunks: reviewedKeywords.take(3).toList(growable: false),
      familyChallenge: _addFamilyChallenge
          ? FamilyChallenge(
              promptZh: _challengeQuestion.text.trim(),
              correctChoiceZh: _cleanChoice(_chinese.text),
              distractorsZh: _challengeDistractors(),
              successMessageZh: '找到家人藏的題目了！',
              cultureNoteZh: _cultureNote.text.trim(),
            )
          : null,
    );
    if (!mounted) return;
    _reset();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('這句話已留在這支裝置。')));
    widget.onCreated();
  }

  void _reset() {
    _title.clear();
    _object.clear();
    _vietnamese.clear();
    _chinese.clear();
    _pronunciation.clear();
    _promptZh.clear();
    _promptVi.clear();
    _keywords.clear();
    _challengeQuestion.clear();
    _cultureNote.clear();
    setState(() {
      _draft = null;
      _audioPath = null;
      _photoPath = null;
      _familyConfirmed = false;
      _textOnlyBackup = false;
      _saving = false;
      _addFamilyChallenge = true;
      _languageName = '越南語';
      _pronunciationSystem = '羅馬字分詞';
      _formGeneration += 1;
    });
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? '這個欄位不能空白' : null;

  List<String> _parseKeywords(String raw) => raw
      .split(RegExp(r'[,，、;；\n]+'))
      .map((keyword) => keyword.trim())
      .where((keyword) => keyword.isNotEmpty)
      .toSet()
      .toList(growable: false);

  String _cleanChoice(String value) => value
      .trim()
      .replaceAll(RegExp(r'[。！？!?]+$'), '')
      .replaceFirst(RegExp(r'^這是'), '')
      .trim();

  List<String> _challengeDistractors() {
    final correct = _cleanChoice(_chinese.text);
    final candidates = <String>[
      ...widget.store.stories.map((story) => _cleanChoice(story.chinese)),
      '白飯',
      '筷子',
      '水',
    ];
    return candidates
        .where((choice) => choice.isNotEmpty && choice != correct)
        .toSet()
        .take(2)
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 36),
        children: [
          Text('錄下我們家會說的話', style: Theme.of(context).textTheme.headlineLarge),
          const SizedBox(height: 8),
          const Text(
            '先選一個 2–6 個詞的生活短句，再補上拼音；孩子會用看圖、慢速聽與跟讀來練習。',
            style: TextStyle(color: AppColors.muted, fontSize: 16),
          ),
          const SizedBox(height: 24),
          _StepTitle(number: 1, title: '選一張照片或一個生活情境'),
          const SizedBox(height: 12),
          TextFormField(
            controller: _title,
            validator: _required,
            decoration: const InputDecoration(
              labelText: '幫這句話取個名字',
              hintText: '例如：外婆的魚露',
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _object,
            validator: _required,
            onChanged: _invalidateDraft,
            decoration: const InputDecoration(
              labelText: '這句話跟什麼有關？',
              hintText: '例如：魚露、晚餐或一張家庭照',
            ),
          ),
          const SizedBox(height: 12),
          if (_photoPath != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: kIsWeb
                  ? Image.network(
                      _photoPath!,
                      height: 180,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox(
                        height: 120,
                        child: Center(child: Text('瀏覽器已釋放這張照片，請重新選擇。')),
                      ),
                    )
                  : Image.file(
                      File(_photoPath!),
                      height: 180,
                      fit: BoxFit.cover,
                    ),
            ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _choosePhoto(true),
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('拍張照片'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _choosePhoto(false),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('選擇照片'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          _StepTitle(number: 2, title: '請家人用平常的說法錄一句'),
          const SizedBox(height: 12),
          RecordingControl(
            key: ValueKey(_formGeneration),
            media: widget.media,
            prefix: 'family_story',
            label: '錄下家人的聲音',
            onRecorded: (path) => setState(() => _audioPath = path),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _textOnlyBackup,
            onChanged: (value) =>
                setState(() => _textOnlyBackup = value ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('這次使用文字備援'),
            subtitle: const Text('只在麥克風不能用時選擇；不會把文字當成家人的聲音。'),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            key: ValueKey('language-$_formGeneration'),
            initialValue: _languageName,
            decoration: const InputDecoration(labelText: '這是哪一種家語？'),
            items: const [
              DropdownMenuItem(value: '越南語', child: Text('越南語')),
              DropdownMenuItem(value: '臺灣台語', child: Text('臺灣台語')),
              DropdownMenuItem(value: '客語', child: Text('客語')),
              DropdownMenuItem(value: '其他家語', child: Text('其他家語')),
            ],
            onChanged: (value) => setState(() {
              _languageName = value ?? '越南語';
              if (_languageName == '臺灣台語') {
                _pronunciationSystem = '臺羅';
              }
            }),
          ),
          if (_languageName == '其他家語') ...[
            const SizedBox(height: 8),
            const Text(
              '系統不會把未知家語猜成中文發音；請優先保留家人原音。',
              style: TextStyle(color: AppColors.coral, fontSize: 12),
            ),
          ],
          const SizedBox(height: 12),
          TextFormField(
            controller: _vietnamese,
            validator: _required,
            onChanged: _invalidateDraft,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: '家人說的短句（原文）',
              hintText: '例如：Đây là nước mắm.',
              helperText: '一次只練一個意思，建議 2–6 個詞。',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String>(
                  key: ValueKey(
                    'pronunciation-$_formGeneration-$_pronunciationSystem',
                  ),
                  initialValue: _pronunciationSystem,
                  decoration: const InputDecoration(labelText: '標音方式'),
                  items: const [
                    DropdownMenuItem(value: '羅馬字分詞', child: Text('羅馬字')),
                    DropdownMenuItem(value: '臺羅', child: Text('臺羅')),
                    DropdownMenuItem(value: '注音提示', child: Text('注音')),
                    DropdownMenuItem(value: '其他拼音', child: Text('其他')),
                  ],
                  onChanged: (value) => setState(
                    () => _pronunciationSystem = value ?? '羅馬字分詞',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 3,
                child: TextFormField(
                  controller: _pronunciation,
                  decoration: const InputDecoration(
                    labelText: '注音／羅馬拼音',
                    hintText: 'Đây · là · nước · mắm',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _chinese,
            validator: _required,
            onChanged: _invalidateDraft,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: '這句話的中文意思',
              hintText: '這是外婆常用來煮飯的魚露。',
            ),
          ),
          const SizedBox(height: 28),
          _StepTitle(number: 3, title: '整理成練習，請家人看過'),
          const SizedBox(height: 8),
          const Text(
            '系統先整理短句與練習焦點；練習提示只幫忙拆小步驟，家庭腔調仍由家人決定。',
            style: TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _generateDraft,
            icon: const Icon(Icons.tune_rounded),
            label: const Text('整理成一題練習'),
          ),
          if (_draft != null) ...[
            const SizedBox(height: 16),
            _DraftPanel(
              draft: _draft!,
              promptZh: _promptZh,
              promptVi: _promptVi,
              keywords: _keywords,
            ),
            const SizedBox(height: 12),
            _FamilyChallengePanel(
              enabled: _addFamilyChallenge,
              question: _challengeQuestion,
              cultureNote: _cultureNote,
              onEnabledChanged: (value) =>
                  setState(() => _addFamilyChallenge = value),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _familyConfirmed,
              onChanged: (value) =>
                  setState(() => _familyConfirmed = value ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('說這句話的家人已經看過，內容就是我們家的說法'),
              subtitle: const Text('家裡怎麼說，就請家人決定。'),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.check_rounded),
              label: Text(_saving ? '正在儲存…' : '存下這句話'),
            ),
          ],
        ],
      ),
    );
  }
}

class _FamilyChallengePanel extends StatelessWidget {
  const _FamilyChallengePanel({
    required this.enabled,
    required this.question,
    required this.cultureNote,
    required this.onEnabledChanged,
  });

  final bool enabled;
  final TextEditingController question;
  final TextEditingController cultureNote;
  final ValueChanged<bool> onEnabledChanged;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.sunSoft,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFFFD46B)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              key: const ValueKey('family-challenge-toggle'),
              contentPadding: EdgeInsets.zero,
              value: enabled,
              onChanged: onEnabledChanged,
              title: const Text(
                '加一題家人任務',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: const Text('系統會自動變成找物、聽音選圖與拼句三種玩法。'),
              secondary: const Icon(
                Icons.celebration_rounded,
                color: AppColors.coral,
              ),
            ),
            if (enabled) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: const [
                  Chip(
                    avatar: Icon(Icons.touch_app_rounded, size: 17),
                    label: Text('找一找'),
                  ),
                  Chip(
                    avatar: Icon(Icons.hearing_rounded, size: 17),
                    label: Text('聽一聽'),
                  ),
                  Chip(
                    avatar: Icon(Icons.extension_rounded, size: 17),
                    label: Text('拼一拼'),
                  ),
                ],
              ),
              const SizedBox(height: 11),
              TextField(
                controller: question,
                decoration: const InputDecoration(
                  labelText: '家人想出的加碼題',
                  helperText: '一句就好，孩子玩到最後會看到。',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: cultureNote,
                minLines: 2,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: '我們家的小故事或使用時機',
                  hintText: '例如：外婆做春捲時，會用自己的比例調魚露。',
                ),
              ),
            ],
          ],
        ),
      );
}

class _StepTitle extends StatelessWidget {
  const _StepTitle({required this.number, required this.title});

  final int number;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 15,
          backgroundColor: AppColors.coral,
          foregroundColor: Colors.white,
          child: Text(
            '$number',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
      ],
    );
  }
}

class _DraftPanel extends StatelessWidget {
  const _DraftPanel({
    required this.draft,
    required this.promptZh,
    required this.promptVi,
    required this.keywords,
  });

  final TaskDraft draft;
  final TextEditingController promptZh;
  final TextEditingController promptVi;
  final TextEditingController keywords;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: draft.requiresHumanReview
            ? AppColors.coralSoft
            : AppColors.jadeSoft,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('練習草稿', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(draft.explanation),
          const SizedBox(height: 8),
          TextField(
            controller: keywords,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: '想練的詞（可修改）',
              helperText: '用「、」分隔；家裡怎麼說，就怎麼寫。',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: promptZh,
            maxLines: 3,
            decoration: const InputDecoration(labelText: '中文任務（可修改）'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: promptVi,
            maxLines: 3,
            decoration: const InputDecoration(labelText: '越南語任務（可修改）'),
          ),
        ],
      ),
    );
  }
}
