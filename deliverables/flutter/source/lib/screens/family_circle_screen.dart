import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_theme.dart';
import '../models/conversation_episode.dart';
import '../models/family_circle.dart';
import '../models/family_culture_prompt.dart';
import '../models/family_invitation.dart';
import '../services/family_circle_store.dart';
import '../services/local_media_service.dart';
import '../widgets/recording_control.dart';

enum _EpisodeVoiceEditAction { save, remove, cancel }

class FamilyCircleScreen extends StatelessWidget {
  const FamilyCircleScreen({
    required this.store,
    required this.viewerMemberId,
    required this.media,
    required this.childMemberId,
    this.adultActions = false,
    this.managerMemberId,
    super.key,
  });

  final FamilyCircleStore store;
  final String viewerMemberId;
  final LocalMediaService media;
  final String childMemberId;
  final bool adultActions;
  final String? managerMemberId;

  Future<void> _react(
    BuildContext context,
    FamilyCircleStoryCard card,
    FamilySticker sticker,
  ) async {
    try {
      final alreadySelected = card.reactions.any(
        (reaction) =>
            reaction.memberId == viewerMemberId && reaction.sticker == sticker,
      );
      if (alreadySelected) {
        await store.retractReaction(
          actorMemberId: viewerMemberId,
          cardId: card.id,
        );
      } else {
        await store.addOrReplaceReaction(
          actorMemberId: viewerMemberId,
          cardId: card.id,
          sticker: sticker,
        );
      }
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$error')),
        );
      }
    }
  }

  Future<void> _markActivityRead(
    BuildContext context,
    FamilyCircleStoryCard card,
  ) async {
    if (!card.isUnreadFor(viewerMemberId)) return;
    try {
      await store.markRead(
        actorMemberId: viewerMemberId,
        cardId: card.id,
      );
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$error')),
        );
      }
    }
  }

  Future<void> _addContinuation(
    BuildContext context,
    FamilyCircleStoryCard card,
  ) async {
    final controller = TextEditingController();
    String? recordingPath;
    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('留一句給孩子'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const ValueKey('family-continuation-field'),
                controller: controller,
                autofocus: true,
                maxLength: 80,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: familyCulturePromptForEpisode(card.episode),
                  labelText: '孩子下次會看到的話',
                ),
              ),
              const SizedBox(height: 10),
              RecordingControl(
                media: media,
                prefix: 'family_continuation',
                maxSeconds: 12,
                label: '也可以錄下家人的聲音（選填）',
                onRecorded: (path) => recordingPath = path,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) Navigator.pop(context, true);
            },
            child: const Text('留給孩子'),
          ),
        ],
      ),
    );
    final text = controller.text.trim();
    controller.dispose();
    if (shouldSave != true || text.isEmpty || !context.mounted) return;
    try {
      final now = DateTime.now();
      await store.appendContinuation(
        actorMemberId: viewerMemberId,
        cardId: card.id,
        continuation: AdultStoryContinuation(
          id: 'continuation-${now.microsecondsSinceEpoch}',
          adultMemberId: viewerMemberId,
          kind: StoryContinuationKind.familyNote,
          text: text,
          createdAt: now,
          localRecordingReference: recordingPath,
        ),
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已留在這台裝置的家庭故事卡裡。')),
        );
      }
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$error')),
        );
      }
    }
  }

  Future<void> _editEpisodeVoice(
    BuildContext context,
    ConversationEpisode episode,
    ConversationPrompt prompt,
  ) async {
    final promptStorageId =
        prompt.id == episode.openingPromptId ? null : prompt.id;
    final current = store.episodeVoiceFor(
      episode.id,
      promptId: promptStorageId,
    );
    final builtIn = prompt.elderLine;
    final target = TextEditingController(
      text: current?.targetText ?? builtIn.targetText,
    );
    final translation = TextEditingController(
      text: current?.translationZh ?? builtIn.translationZh,
    );
    final romanization = TextEditingController(
      text: current?.romanization ?? builtIn.romanization,
    );
    var recordingReference = current?.localRecordingReference;
    String? errorText;
    final action = await showDialog<_EpisodeVoiceEditAction>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('「${episode.title}」第 ${prompt.step} 回合'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '改成這個故事節點裡，家人真的會說的一句。沒錄音時，劇場會清楚標示「裝置朗讀」。',
                  style: TextStyle(color: AppColors.muted, height: 1.4),
                ),
                const SizedBox(height: 14),
                TextField(
                  key: ValueKey(
                    'family-voice-target-${episode.id}-${prompt.id}',
                  ),
                  controller: target,
                  decoration: InputDecoration(
                    labelText: '我們家的說法（目標語）',
                    errorText: errorText,
                  ),
                  maxLength: 80,
                ),
                TextField(
                  key: ValueKey(
                    'family-voice-romanization-${episode.id}-${prompt.id}',
                  ),
                  controller: romanization,
                  decoration: const InputDecoration(
                    labelText: '羅馬拼音／讀音提示',
                  ),
                  maxLength: 100,
                ),
                TextField(
                  key: ValueKey(
                    'family-voice-translation-${episode.id}-${prompt.id}',
                  ),
                  controller: translation,
                  decoration: const InputDecoration(labelText: '中文意思'),
                  maxLength: 80,
                ),
                const SizedBox(height: 10),
                RecordingControl(
                  media: media,
                  prefix: 'episode_voice_${episode.id}_${prompt.id}',
                  initialPath: recordingReference,
                  maxSeconds: 12,
                  label: '錄下這個回合的家人原音（選填）',
                  onRecorded: (path) => recordingReference = path,
                ),
              ],
            ),
          ),
          actions: [
            if (current != null)
              TextButton(
                onPressed: () => Navigator.pop(
                  context,
                  _EpisodeVoiceEditAction.remove,
                ),
                child: const Text('恢復內建台詞'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(
                context,
                _EpisodeVoiceEditAction.cancel,
              ),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                if (target.text.trim().isEmpty ||
                    translation.text.trim().isEmpty ||
                    romanization.text.trim().isEmpty) {
                  setDialogState(() => errorText = '說法、中文意思與拼音都要填寫');
                  return;
                }
                Navigator.pop(context, _EpisodeVoiceEditAction.save);
              },
              child: const Text('放進主劇情'),
            ),
          ],
        ),
      ),
    );

    final targetValue = target.text.trim();
    final translationValue = translation.text.trim();
    final romanizationValue = romanization.text.trim();
    target.dispose();
    translation.dispose();
    romanization.dispose();

    final oldRecording = current?.localRecordingReference;
    if (action == null || action == _EpisodeVoiceEditAction.cancel) {
      if (recordingReference != null && recordingReference != oldRecording) {
        await media.deletePath(recordingReference);
      }
      return;
    }

    try {
      if (action == _EpisodeVoiceEditAction.remove) {
        await store.removeEpisodeVoice(
          actorMemberId: viewerMemberId,
          episodeId: episode.id,
          promptId: promptStorageId,
        );
        await media.deletePath(oldRecording);
        if (recordingReference != oldRecording) {
          await media.deletePath(recordingReference);
        }
      } else {
        await store.upsertEpisodeVoice(
          actorMemberId: viewerMemberId,
          voice: FamilyEpisodeVoice(
            episodeId: episode.id,
            promptId: promptStorageId,
            adultMemberId: viewerMemberId,
            targetText: targetValue,
            translationZh: translationValue,
            romanization: romanizationValue,
            updatedAt: DateTime.now(),
            localRecordingReference: recordingReference,
          ),
        );
        if (oldRecording != null && oldRecording != recordingReference) {
          await media.deletePath(oldRecording);
        }
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              action == _EpisodeVoiceEditAction.remove
                  ? '已恢復這個回合的內建台詞與裝置朗讀。'
                  : recordingReference == null
                      ? '家庭說法已進入這個回合；目前由裝置朗讀。'
                      : '家人原音已進入這個回合。',
            ),
          ),
        );
      }
    } on Object catch (error) {
      if (recordingReference != null && recordingReference != oldRecording) {
        await media.deletePath(recordingReference);
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('家庭原音沒有存好：$error')),
        );
      }
    }
  }

  Future<void> _addFamilyMember(BuildContext context) async {
    var nicknameValue = '';
    var relationshipValue = '';
    var avatar = 'elder-woman';
    var isAdult = true;
    String? errorText;
    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('把家人請進故事圈'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  key: const ValueKey('family-member-nickname'),
                  onChanged: (value) => nicknameValue = value,
                  decoration: InputDecoration(
                    labelText: '孩子怎麼叫他？',
                    hintText: '例如：阿公、小阿姨',
                    errorText: errorText,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  key: const ValueKey('family-member-relationship'),
                  onChanged: (value) => relationshipValue = value,
                  decoration: const InputDecoration(
                    labelText: '家庭關係',
                    hintText: '例如：外公、姑姑、哥哥',
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 7,
                  children: [
                    for (final option in const <String, IconData>{
                      'elder-woman': Icons.face_3_rounded,
                      'elder-man': Icons.face_4_rounded,
                      'adult-woman': Icons.person_2_rounded,
                      'adult-man': Icons.person_3_rounded,
                      'person': Icons.person_rounded,
                    }.entries)
                      ChoiceChip(
                        selected: avatar == option.key,
                        onSelected: (_) =>
                            setDialogState(() => avatar = option.key),
                        avatar: Icon(option.value, size: 21),
                        label: const Text(''),
                      ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: isAdult,
                  onChanged: (value) => setDialogState(() => isAdult = value),
                  title: const Text('這位家人是成人'),
                  subtitle: const Text('只有成人能核准成員及留話給孩子'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                if (nicknameValue.trim().isEmpty ||
                    relationshipValue.trim().isEmpty) {
                  setDialogState(() => errorText = '請填孩子看得懂的稱呼與關係');
                  return;
                }
                Navigator.pop(context, true);
              },
              child: Text(isAdult ? '做一份邀請包' : '由我確認加入'),
            ),
          ],
        ),
      ),
    );
    nicknameValue = nicknameValue.trim();
    relationshipValue = relationshipValue.trim();
    if (shouldSave != true || !context.mounted) return;
    final now = DateTime.now();
    final id = 'family-member-${now.microsecondsSinceEpoch}';
    try {
      final member = FamilyMember(
        id: id,
        relationship: relationshipValue,
        nickname: nicknameValue,
        isAdult: isAdult,
        avatarEmoji: avatar,
        roleColorValue: const [
          0xFFFFE5DE,
          0xFFDDEEFF,
          0xFFDCEDE8,
          0xFFEAE2FF,
          0xFFFFF1BF,
        ][store.members.length % 5],
        createdAt: now,
      );
      if (isAdult) {
        final package = await store.createAdultInvitationPackage(
          actorMemberId: viewerMemberId,
          invitedAdult: member,
        );
        if (context.mounted) {
          await _showInvitationPackage(
            context,
            nickname: nicknameValue,
            package: package,
          );
        }
      } else {
        await store.inviteMember(
          actorMemberId: viewerMemberId,
          member: member,
        );
        await store.approveMember(
          actorMemberId: viewerMemberId,
          memberId: id,
        );
      }
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$error')),
        );
      }
    }
  }

  Future<void> _showInvitationPackage(
    BuildContext context, {
    required String nickname,
    required String package,
  }) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(
          Icons.forward_to_inbox_rounded,
          color: AppColors.coral,
          size: 38,
        ),
        title: Text('把邀請親自交給 $nickname'),
        content: SizedBox(
          width: 470,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '這份一次性邀請不會自己傳出去。請用你信任的方式交給本人；裡面沒有孩子的故事、照片、錄音或家人碼。',
                style: TextStyle(height: 1.45),
              ),
              const SizedBox(height: 12),
              Container(
                constraints: const BoxConstraints(maxHeight: 150),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.cream,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    package,
                    key: const ValueKey('adult-invitation-package-output'),
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '狀態：等待 $nickname 本人接受（24 小時內有效）',
                style: const TextStyle(
                  color: AppColors.berry,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                '關閉後不會保留這段邀請內容；若還沒複製，只能取消邀請再重做。',
                style: TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('關閉（遺失就重做）'),
          ),
          FilledButton.icon(
            key: const ValueKey('copy-adult-invitation-package'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: package));
              if (!dialogContext.mounted) return;
              ScaffoldMessenger.of(dialogContext).showSnackBar(
                SnackBar(content: Text('已複製邀請包，請親自交給 $nickname。')),
              );
            },
            icon: const Icon(Icons.content_copy_rounded),
            label: const Text('複製邀請包'),
          ),
        ],
      ),
    );
  }

  Future<void> _importInvitationReceipt(BuildContext context) async {
    final controller = TextEditingController();
    String? errorText;
    var busy = false;
    final approved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('確認家人的接受回覆'),
          content: SizedBox(
            width: 470,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '只帶入受邀者親自做出的回覆包。核准成功後，這位家人才會出現在孩子的故事圈。',
                  style: TextStyle(color: AppColors.muted, height: 1.45),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('adult-invitation-receipt-input'),
                  controller: controller,
                  minLines: 3,
                  maxLines: 6,
                  decoration: InputDecoration(
                    labelText: '接受回覆包',
                    hintText: '貼上家人交回的內容',
                    suffixIcon: IconButton(
                      key: const ValueKey('paste-adult-invitation-receipt'),
                      tooltip: '從剪貼簿貼上',
                      onPressed: busy
                          ? null
                          : () async {
                              final data = await Clipboard.getData(
                                Clipboard.kTextPlain,
                              );
                              if (data?.text != null) {
                                controller.text = data!.text!;
                              }
                            },
                      icon: const Icon(Icons.content_paste_rounded),
                    ),
                  ),
                ),
                if (errorText != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    errorText!,
                    key: const ValueKey('invitation-receipt-error'),
                    style: const TextStyle(
                      color: AppColors.coral,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(dialogContext),
              child: const Text('先不要'),
            ),
            FilledButton.icon(
              key: const ValueKey('approve-adult-invitation-receipt'),
              onPressed: busy
                  ? null
                  : () async {
                      if (controller.text.trim().isEmpty) {
                        setDialogState(() => errorText = '請先貼上接受回覆包。');
                        return;
                      }
                      setDialogState(() {
                        busy = true;
                        errorText = null;
                      });
                      try {
                        await store.importAdultInvitationReceipt(
                          actorMemberId: viewerMemberId,
                          source: controller.text,
                        );
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext, true);
                        }
                      } on FamilyInvitationException catch (error) {
                        setDialogState(() {
                          busy = false;
                          errorText = switch (error.failure) {
                            FamilyInvitationFailure.expired => '這份邀請已過期，請重新邀請。',
                            FamilyInvitationFailure.used =>
                              '這份回覆已經帶入過，不會重複建立角色。',
                            FamilyInvitationFailure.wrongCircle =>
                              '這不是這個家庭圈的回覆，沒有帶入任何內容。',
                            FamilyInvitationFailure.revoked =>
                              '這份邀請已取消，沒有加入任何人。',
                            FamilyInvitationFailure.tampered =>
                              '回覆內容似乎被改過，沒有帶入任何內容。',
                            FamilyInvitationFailure.invalid =>
                              '這份回覆包讀不懂，請家人重新接受邀請。',
                          };
                        });
                      } on Object {
                        setDialogState(() {
                          busy = false;
                          errorText = '現在無法確認；原家庭資料沒有被更動。';
                        });
                      }
                    },
              icon: busy
                  ? const SizedBox.square(
                      dimension: 17,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.person_add_alt_1_rounded),
              label: Text(busy ? '正在確認本人回覆…' : '確認家人加入'),
            ),
          ],
        ),
      ),
    );
    await Future<void>.delayed(kThemeAnimationDuration);
    controller.dispose();
    if (approved == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('家人已正式加入；切換成他的角色時會詢問他自己的家人碼。')),
      );
    }
  }

  Future<void> _revokeInvitation(
    BuildContext context,
    PendingAdultInvitation invitation,
  ) async {
    final member = store.memberById(invitation.memberId);
    final nickname = member?.nickname ?? '這位家人';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('取消 $nickname 的邀請？'),
        content: const Text('取消後，原本的邀請包和接受回覆都不能再使用。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('保留邀請'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('確認取消'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await store.revokeAdultInvitation(
        actorMemberId: viewerMemberId,
        invitationId: invitation.id,
      );
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('沒有取消成功：$error')),
        );
      }
    }
  }

  Future<void> _removeFamilyMember(
    BuildContext context,
    FamilyMember member,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('移除 ${member.nickname}？'),
        content: const Text('這會移除這位角色留下的貼圖、留言與主劇情原音；裝置上的其他家人不受影響。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('先不要'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('確認移除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final voiceRecordings = store.episodeVoices
        .where((voice) => voice.adultMemberId == member.id)
        .map((voice) => voice.localRecordingReference)
        .whereType<String>()
        .toList(growable: false);
    try {
      await store.removeMember(
        actorMemberId: viewerMemberId,
        memberId: member.id,
      );
      for (final recording in voiceRecordings) {
        await media.deletePath(recording);
      }
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('無法移除：$error')),
        );
      }
    }
  }

  Future<void> _copyFamilyPackage(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: store.exportJson()));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('家庭文字資料包已複製；可手動帶到另一台裝置，錄音檔不會一起帶過去。'),
      ),
    );
  }

  Future<void> _importFamilyPackage(BuildContext context) async {
    final controller = TextEditingController();
    final source = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('帶入家庭文字資料包'),
        content: TextField(
          key: const ValueKey('family-package-input'),
          controller: controller,
          minLines: 5,
          maxLines: 10,
          decoration: const InputDecoration(
            hintText: '貼上另一台裝置匯出的 JSON',
            helperText: '會取代這台裝置的家庭圈；不包含錄音檔本體。',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) Navigator.pop(context, value);
            },
            child: const Text('驗證並帶入'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (source == null || !context.mounted) return;
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map || decoded['members'] is! List) {
        throw const FormatException('不是完整的家庭圈資料包。');
      }
      final memberIds = (decoded['members'] as List)
          .whereType<Map>()
          .map((item) => item['id'])
          .whereType<String>()
          .toSet();
      if (!memberIds.contains(viewerMemberId) ||
          !memberIds.contains(childMemberId)) {
        throw const FormatException('資料包缺少目前的家長或孩子角色。');
      }
      await store.importJson(source, actorMemberId: viewerMemberId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('家庭圈文字與回應已帶入這台裝置。')),
        );
      }
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('沒有帶入：$error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final viewer = store.memberById(viewerMemberId);
        final canManageFamily = adultActions &&
            (managerMemberId == null || managerMemberId == viewerMemberId);
        return ListView(
          key: ValueKey(
              adultActions ? 'adult-family-circle' : 'child-family-circle'),
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 36),
          children: [
            Text(
              adultActions ? '回到故事裡陪孩子' : '我們家的故事圈',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 6),
            Text(
              adultActions
                  ? '家人可以用一個表情或一句話接著演，不必替孩子打分。'
                  : '看看家人留下的笑臉和話；這裡沒有陌生人、公開排行或私訊。',
              style: const TextStyle(color: AppColors.muted, fontSize: 16),
            ),
            const SizedBox(height: 14),
            _FamilyActivityFeed(
              store: store,
              viewerMemberId: viewerMemberId,
              media: media,
              onMarkRead: (card) => _markActivityRead(context, card),
            ),
            const SizedBox(height: 10),
            _FamilyStoryChapterProgress(store: store),
            const SizedBox(height: 12),
            _LocalOnlyBanner(adultActions: adultActions),
            const SizedBox(height: 16),
            _MemberRow(
              members: store.members
                  .where((member) => member.isApproved)
                  .toList(growable: false),
              viewer: viewer,
              protectedMemberIds: {viewerMemberId, childMemberId},
              onRemove: canManageFamily
                  ? (member) => _removeFamilyMember(context, member)
                  : null,
            ),
            if (canManageFamily) ...[
              if (store.pendingAdultInvitations.isNotEmpty) ...[
                const SizedBox(height: 12),
                _PendingInvitationsPanel(
                  store: store,
                  onRevoke: (invitation) =>
                      _revokeInvitation(context, invitation),
                ),
              ],
              const SizedBox(height: 10),
              OutlinedButton.icon(
                key: const ValueKey('add-family-member'),
                onPressed: () => _addFamilyMember(context),
                icon: const Icon(Icons.person_add_alt_rounded),
                label: const Text('邀請或加入一位家人'),
              ),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                key: const ValueKey('import-adult-invitation-receipt'),
                onPressed: () => _importInvitationReceipt(context),
                icon: const Icon(Icons.mark_email_read_outlined),
                label: const Text('家人已接受：帶入回覆包'),
              ),
              const SizedBox(height: 16),
              ExpansionTile(
                key: const ValueKey('manual-family-backup-tools'),
                tilePadding: EdgeInsets.zero,
                leading: const Icon(Icons.inventory_2_outlined),
                title: const Text('完整文字備份與搬移'),
                subtitle: const Text('手動操作，不是邀請或即時同步'),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          key: const ValueKey('export-family-package'),
                          onPressed: () => _copyFamilyPackage(context),
                          icon: const Icon(Icons.content_copy_rounded),
                          label: const Text('複製備份'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          key: const ValueKey('import-family-package'),
                          onPressed: () => _importFamilyPackage(context),
                          icon: const Icon(Icons.move_to_inbox_rounded),
                          label: const Text('帶入備份'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
            ],
            if (adultActions) ...[
              _FamilyVoiceStudio(
                store: store,
                onEdit: (episode, prompt) =>
                    _editEpisodeVoice(context, episode, prompt),
              ),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: Text(
                    adultActions ? '幫孩子留一個回應' : '我們演過的故事',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (store.cards.isNotEmpty)
                  Text(
                    '${store.cards.length} 張',
                    style: const TextStyle(
                      color: AppColors.berry,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (store.cards.isEmpty)
              const _EmptyCircle()
            else
              for (final card in store.cards) ...[
                _FamilyStoryCardView(
                  card: card,
                  store: store,
                  media: media,
                  actorMemberId: viewerMemberId,
                  adultActions: adultActions,
                  onReact: (sticker) => _react(context, card, sticker),
                  onContinue: () => _addContinuation(context, card),
                ),
                const SizedBox(height: 14),
              ],
          ],
        );
      },
    );
  }
}

class _PendingInvitationsPanel extends StatelessWidget {
  const _PendingInvitationsPanel({
    required this.store,
    required this.onRevoke,
  });

  final FamilyCircleStore store;
  final ValueChanged<PendingAdultInvitation> onRevoke;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('pending-family-invitations'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.berry.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.berry.withValues(alpha: .18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.hourglass_top_rounded, color: AppColors.berry),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '等待家人本人接受',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            '在帶回有效的接受回覆以前，這些角色不會出現在孩子的家庭成員列。',
            style: TextStyle(color: AppColors.muted, height: 1.4),
          ),
          for (final invitation in store.pendingAdultInvitations) ...[
            const Divider(height: 18),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        store.memberById(invitation.memberId)?.nickname ??
                            '受邀家人',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      Text(
                        '有效到 ${_shortDateTime(invitation.expiresAt)}',
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => onRevoke(invitation),
                  child: const Text('取消邀請'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

String _shortDateTime(DateTime value) {
  final local = value.toLocal();
  String two(int part) => part.toString().padLeft(2, '0');
  return '${local.month}/${local.day} ${two(local.hour)}:${two(local.minute)}';
}

class _FamilyVoiceStudio extends StatelessWidget {
  const _FamilyVoiceStudio({required this.store, required this.onEdit});

  final FamilyCircleStore store;
  final void Function(ConversationEpisode, ConversationPrompt) onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('family-voice-studio'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.coralSoft,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.coral.withValues(alpha: .2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.record_voice_over_rounded,
                  color: AppColors.coral),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  '把家人的聲音放進五集主劇情',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          const Text(
            '展開每一集，可替三回合的所有故事節點留下家庭說法。真人原音優先，沒有錄音則由裝置朗讀。',
            style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 12),
          for (final episode in ConversationEpisodeCatalog.defaults) ...[
            Material(
              color: Colors.white.withValues(alpha: .86),
              borderRadius: BorderRadius.circular(16),
              child: ExpansionTile(
                key: ValueKey('family-voice-episode-${episode.id}'),
                leading: const Icon(
                  Icons.auto_stories_rounded,
                  color: AppColors.coral,
                ),
                title: Text(
                  episode.title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: Text(
                  '${store.episodeVoicesFor(episode.id).length}/${episode.prompts.length} 個節點已有家庭版本',
                  style: const TextStyle(fontSize: 11),
                ),
                children: [
                  for (var step = 1; step <= episode.totalTurns; step++) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 5),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '第 $step 回合',
                          style: const TextStyle(
                            color: AppColors.coral,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                    for (final prompt
                        in episode.prompts.where((item) => item.step == step))
                      _FamilyPromptVoiceTile(
                        episode: episode,
                        prompt: prompt,
                        voice: store.episodeVoiceFor(
                          episode.id,
                          promptId: prompt.id == episode.openingPromptId
                              ? null
                              : prompt.id,
                        ),
                        store: store,
                        onTap: () => onEdit(episode, prompt),
                      ),
                  ],
                  const SizedBox(height: 10),
                ],
              ),
            ),
            if (episode != ConversationEpisodeCatalog.defaults.last)
              const SizedBox(height: 7),
          ],
        ],
      ),
    );
  }
}

class _FamilyPromptVoiceTile extends StatelessWidget {
  const _FamilyPromptVoiceTile({
    required this.episode,
    required this.prompt,
    required this.voice,
    required this.store,
    required this.onTap,
  });

  final ConversationEpisode episode;
  final ConversationPrompt prompt;
  final FamilyEpisodeVoice? voice;
  final FamilyCircleStore store;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final adult = voice == null ? null : store.memberById(voice!.adultMemberId);
    final source = voice == null
        ? '裝置朗讀 · ${prompt.elderLine.translationZh}'
        : voice!.hasFamilyRecording
            ? '家人原音 · ${adult?.nickname ?? '家人'}'
            : '裝置朗讀 · 我們家的說法';
    return ListTile(
      key: ValueKey('edit-family-voice-${episode.id}-${prompt.id}'),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      dense: true,
      leading: Icon(
        voice?.hasFamilyRecording ?? false
            ? Icons.family_restroom_rounded
            : Icons.phone_android_rounded,
        color: voice?.hasFamilyRecording ?? false
            ? AppColors.coral
            : AppColors.jade,
      ),
      title: Text(
        prompt.stageDirectionZh,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(source, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.edit_rounded, size: 19),
    );
  }
}

class _FamilyStoryChapterProgress extends StatelessWidget {
  const _FamilyStoryChapterProgress({required this.store});

  final FamilyCircleStore store;

  @override
  Widget build(BuildContext context) {
    final hasStoryCard = store.cards.isNotEmpty;
    final hasFamilyRecording =
        store.episodeVoices.any((voice) => voice.hasFamilyRecording);
    final hasAdultMemory =
        store.cards.any((card) => card.continuations.isNotEmpty);
    final completed = [
      hasStoryCard,
      hasFamilyRecording,
      hasAdultMemory,
    ].where((item) => item).length;
    final isComplete = completed == 3;

    return Material(
      key: const ValueKey('family-story-chapter-progress'),
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: AppColors.jade.withValues(alpha: .2)),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.fromLTRB(13, 3, 12, 3),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 13),
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: isComplete ? AppColors.jade : AppColors.jadeSoft,
            shape: BoxShape.circle,
          ),
          child: Icon(
            isComplete ? Icons.auto_awesome_rounded : Icons.menu_book_rounded,
            color: isComplete ? Colors.white : AppColors.jade,
            size: 21,
          ),
        ),
        title: Row(
          children: [
            const Expanded(
              child: Text(
                '一起完成家庭故事章',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
              ),
            ),
            Container(
              key: const ValueKey('family-chapter-count'),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: isComplete ? AppColors.jade : AppColors.jadeSoft,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                '$completed/3',
                style: TextStyle(
                  color: isComplete ? Colors.white : AppColors.jade,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            isComplete ? '家庭故事章完成' : '不急，孩子的故事照樣可以繼續',
            key: isComplete
                ? const ValueKey('family-chapter-complete')
                : const ValueKey('family-chapter-open'),
            style: TextStyle(
              color: isComplete ? AppColors.jade : AppColors.muted,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: completed / 3,
              minHeight: 6,
              backgroundColor: AppColors.jadeSoft,
              color: AppColors.jade,
            ),
          ),
          const SizedBox(height: 9),
          _FamilyChapterTaskRow(
            key: const ValueKey('family-chapter-task-story'),
            completed: hasStoryCard,
            label: '孩子演完一個故事',
          ),
          _FamilyChapterTaskRow(
            key: const ValueKey('family-chapter-task-voice'),
            completed: hasFamilyRecording,
            label: '家人留下一段主劇情原音',
          ),
          _FamilyChapterTaskRow(
            key: const ValueKey('family-chapter-task-memory'),
            completed: hasAdultMemory,
            label: '成人留一句家庭記憶',
          ),
          if (!isComplete)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                '家人有空再加入就好，沒有倒數，也不影響孩子繼續玩。',
                style: TextStyle(color: AppColors.muted, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }
}

class _FamilyChapterTaskRow extends StatelessWidget {
  const _FamilyChapterTaskRow({
    required this.completed,
    required this.label,
    super.key,
  });

  final bool completed;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            completed
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            color: completed ? AppColors.jade : AppColors.muted,
            size: 19,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: completed ? AppColors.ink : AppColors.muted,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            completed ? '有了' : '等待家人',
            style: TextStyle(
              color: completed ? AppColors.jade : AppColors.muted,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _LocalOnlyBanner extends StatelessWidget {
  const _LocalOnlyBanner({required this.adultActions});

  final bool adultActions;

  @override
  Widget build(BuildContext context) {
    if (!adultActions) {
      return Semantics(
        label: '私密家庭圈，資料目前只保存在這台裝置',
        child: Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: AppColors.jadeSoft,
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: AppColors.jade.withValues(alpha: .2)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_rounded, color: AppColors.jade, size: 17),
                SizedBox(width: 6),
                Text(
                  '只給家人看 · 保存在這台裝置',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.jadeSoft,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lock_rounded, color: AppColors.jade),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '目前回應只保存在這台裝置；右上角可切換已核准成人角色。換裝置須手動複製文字資料包，錄音不會一起帶過去。',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

IconData _memberAvatarIcon(FamilyMember member) {
  switch (member.avatarEmoji) {
    case 'elder-woman':
      return Icons.face_3_rounded;
    case 'elder-man':
      return Icons.face_4_rounded;
    case 'adult-woman':
      return Icons.person_2_rounded;
    case 'adult-man':
      return Icons.person_3_rounded;
    case 'person':
      return Icons.person_rounded;
  }
  if (!member.isAdult) return Icons.child_care_rounded;
  if (RegExp(r'公|爺|叔|舅|爸').hasMatch(member.relationship)) {
    return Icons.face_4_rounded;
  }
  if (RegExp(r'婆|嬤|奶|姨|姑|媽').hasMatch(member.relationship)) {
    return Icons.face_3_rounded;
  }
  return Icons.person_rounded;
}

IconData _stickerIcon(FamilySticker sticker) => switch (sticker) {
      FamilySticker.heart => Icons.favorite_rounded,
      FamilySticker.clap => Icons.waving_hand_rounded,
      FamilySticker.hug => Icons.volunteer_activism_rounded,
      FamilySticker.laugh => Icons.sentiment_very_satisfied_rounded,
      FamilySticker.proud => Icons.star_rounded,
    };

enum _FamilyActivityKind { story, reaction, continuation }

class _FamilyActivity {
  const _FamilyActivity({
    required this.kind,
    required this.card,
    required this.actor,
    required this.createdAt,
    this.reaction,
    this.continuation,
  });

  final _FamilyActivityKind kind;
  final FamilyCircleStoryCard card;
  final FamilyMember? actor;
  final DateTime createdAt;
  final FamilyStickerReaction? reaction;
  final AdultStoryContinuation? continuation;

  String get id => switch (kind) {
        _FamilyActivityKind.story => 'story-${card.id}',
        _FamilyActivityKind.reaction =>
          'reaction-${card.id}-${reaction!.memberId}-${reaction!.createdAt.microsecondsSinceEpoch}',
        _FamilyActivityKind.continuation => 'continuation-${continuation!.id}',
      };
}

List<_FamilyActivity> _latestFamilyActivities(
  FamilyCircleStore store,
  String viewerMemberId,
) {
  final activities = <_FamilyActivity>[];
  for (final card in store.cards) {
    if (card.createdByMemberId != viewerMemberId) {
      activities.add(
        _FamilyActivity(
          kind: _FamilyActivityKind.story,
          card: card,
          actor: store.memberById(card.createdByMemberId),
          createdAt: card.createdAt,
        ),
      );
    }
    for (final reaction in card.reactions) {
      if (reaction.memberId == viewerMemberId) continue;
      activities.add(
        _FamilyActivity(
          kind: _FamilyActivityKind.reaction,
          card: card,
          actor: store.memberById(reaction.memberId),
          reaction: reaction,
          createdAt: reaction.createdAt,
        ),
      );
    }
    for (final continuation in card.continuations) {
      if (continuation.adultMemberId == viewerMemberId) continue;
      activities.add(
        _FamilyActivity(
          kind: _FamilyActivityKind.continuation,
          card: card,
          actor: store.memberById(continuation.adultMemberId),
          continuation: continuation,
          createdAt: continuation.createdAt,
        ),
      );
    }
  }
  activities.sort((left, right) => right.createdAt.compareTo(left.createdAt));
  return activities.take(3).toList(growable: false);
}

class _FamilyActivityFeed extends StatelessWidget {
  const _FamilyActivityFeed({
    required this.store,
    required this.viewerMemberId,
    required this.media,
    required this.onMarkRead,
  });

  final FamilyCircleStore store;
  final String viewerMemberId;
  final LocalMediaService media;
  final ValueChanged<FamilyCircleStoryCard> onMarkRead;

  @override
  Widget build(BuildContext context) {
    final activities = _latestFamilyActivities(store, viewerMemberId);
    final unreadCards = store.unreadCardsFor(viewerMemberId);
    final latestByCard = <String, DateTime>{};
    for (final activity in activities) {
      final current = latestByCard[activity.card.id];
      if (current == null || activity.createdAt.isAfter(current)) {
        latestByCard[activity.card.id] = activity.createdAt;
      }
    }
    return Container(
      key: const ValueKey('family-activity-feed'),
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFF1BF), Color(0xFFFFE5DE)],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.notifications_active_rounded,
                color: AppColors.coral,
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      activities.isEmpty ? '家人互動' : '家人剛剛留下的',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const Text(
                      '這台裝置上的最新互動',
                      style: TextStyle(color: AppColors.muted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              if (unreadCards.isNotEmpty)
                Container(
                  key: const ValueKey('family-unread-count'),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.coral,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    '${unreadCards.length} 張未讀',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (activities.isEmpty)
            Container(
              key: const ValueKey('family-activity-empty'),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .76),
                borderRadius: BorderRadius.circular(17),
              ),
              child: const Row(
                children: [
                  Icon(Icons.forum_outlined, color: AppColors.jade),
                  SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      '故事已經在家裡了；等家人有空，就能在這台裝置留下表情或一句話。',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            )
          else
            SizedBox(
              height: 132,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: activities.length,
                separatorBuilder: (_, __) => const SizedBox(width: 9),
                itemBuilder: (context, index) {
                  final activity = activities[index];
                  final isLatestForCard =
                      latestByCard[activity.card.id] == activity.createdAt;
                  return SizedBox(
                    width: MediaQuery.sizeOf(context).width < 500 ? 292 : 320,
                    child: _FamilyActivityTile(
                      activity: activity,
                      media: media,
                      unread: activity.card.isUnreadFor(viewerMemberId) &&
                          isLatestForCard,
                      onMarkRead: () => onMarkRead(activity.card),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _FamilyActivityTile extends StatelessWidget {
  const _FamilyActivityTile({
    required this.activity,
    required this.media,
    required this.unread,
    required this.onMarkRead,
  });

  final _FamilyActivity activity;
  final LocalMediaService media;
  final bool unread;
  final VoidCallback onMarkRead;

  String get _actorName => activity.actor?.nickname ?? '家人';

  String get _headline => switch (activity.kind) {
        _FamilyActivityKind.story => '$_actorName 演完一個故事',
        _FamilyActivityKind.reaction =>
          '$_actorName 送來「${activity.reaction!.sticker.zhLabel}」',
        _FamilyActivityKind.continuation => '$_actorName 留了一句',
      };

  String get _detail => switch (activity.kind) {
        _FamilyActivityKind.story =>
          activity.card.sourceConversationCard?.title ?? activity.card.episode,
        _FamilyActivityKind.reaction => activity.card.sceneOutcome,
        _FamilyActivityKind.continuation => activity.continuation!.text,
      };

  IconData get _icon => switch (activity.kind) {
        _FamilyActivityKind.story => Icons.auto_stories_rounded,
        _FamilyActivityKind.reaction =>
          _stickerIcon(activity.reaction!.sticker),
        _FamilyActivityKind.continuation =>
          activity.continuation!.localRecordingReference == null
              ? Icons.chat_bubble_rounded
              : Icons.record_voice_over_rounded,
      };

  Future<void> _playRecording(BuildContext context) async {
    final path = activity.continuation?.localRecordingReference;
    if (path == null) return;
    try {
      await media.playLocal(path);
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final actor = activity.actor;
    final hasRecording = activity.continuation?.localRecordingReference != null;
    return Semantics(
      button: unread,
      label: '$_headline。$_detail。${unread ? '未讀，點一下標成看過' : '已看過'}',
      child: Material(
        color: Colors.white.withValues(alpha: .94),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          key: ValueKey('family-activity-${activity.id}'),
          onTap: unread ? onMarkRead : null,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: actor == null
                            ? AppColors.jadeSoft
                            : Color(actor.roleColorValue),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        actor == null
                            ? Icons.family_restroom_rounded
                            : _memberAvatarIcon(actor),
                        size: 22,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        _headline,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    if (unread)
                      Container(
                        key: ValueKey('family-activity-unread-${activity.id}'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.coral,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: const Text(
                          '新',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    Icon(_icon, size: 18, color: AppColors.coral),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Row(
                  children: [
                    const Icon(
                      Icons.phone_android_rounded,
                      size: 14,
                      color: AppColors.jade,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      unread ? '點一下標成看過' : '本機家庭圈',
                      style: const TextStyle(
                        color: AppColors.jade,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    if (hasRecording)
                      IconButton(
                        key: ValueKey('play-activity-${activity.id}'),
                        tooltip: '播放$_actorName錄下的話',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 30,
                          height: 30,
                        ),
                        onPressed: () => _playRecording(context),
                        icon: const Icon(
                          Icons.volume_up_rounded,
                          color: AppColors.jade,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.members,
    required this.viewer,
    required this.protectedMemberIds,
    this.onRemove,
  });

  final List<FamilyMember> members;
  final FamilyMember? viewer;
  final Set<String> protectedMemberIds;
  final ValueChanged<FamilyMember>? onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('這個圈圈裡', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          children: [
            for (final member in members.where((item) => item.isApproved))
              Semantics(
                label: '${member.nickname}，已由成人核准',
                child: Column(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 58,
                          height: 58,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Color(member.roleColorValue),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: member.id == viewer?.id
                                  ? AppColors.ink
                                  : Colors.white,
                              width: 3,
                            ),
                          ),
                          child: Icon(
                            _memberAvatarIcon(member),
                            size: 30,
                            color: AppColors.ink,
                          ),
                        ),
                        if (onRemove != null &&
                            !protectedMemberIds.contains(member.id))
                          Positioned(
                            right: -7,
                            top: -7,
                            child: Tooltip(
                              message: '移除 ${member.nickname}',
                              child: InkWell(
                                key: ValueKey('remove-member-${member.id}'),
                                onTap: () => onRemove!(member),
                                borderRadius: BorderRadius.circular(99),
                                child: Container(
                                  width: 25,
                                  height: 25,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: AppColors.border),
                                  ),
                                  child: const Icon(
                                    Icons.close_rounded,
                                    size: 16,
                                    color: AppColors.muted,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      member.nickname,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _FamilyStoryCardView extends StatelessWidget {
  const _FamilyStoryCardView({
    required this.card,
    required this.store,
    required this.media,
    required this.actorMemberId,
    required this.adultActions,
    required this.onReact,
    required this.onContinue,
  });

  final FamilyCircleStoryCard card;
  final FamilyCircleStore store;
  final LocalMediaService media;
  final String actorMemberId;
  final bool adultActions;
  final ValueChanged<FamilySticker> onReact;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final source = card.sourceConversationCard;
    FamilyStickerReaction? actorReaction;
    for (final reaction in card.reactions) {
      if (reaction.memberId == actorMemberId) {
        actorReaction = reaction;
        break;
      }
    }
    return Container(
      key: ValueKey('family-card-${card.id}'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 54,
                height: 54,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.sunSoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.auto_stories_rounded,
                  color: AppColors.coral,
                  size: 30,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      source?.title ?? card.episode,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      card.sceneOutcome,
                      style: const TextStyle(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (card.relayId != null) ...[
            const SizedBox(height: 14),
            _FamilyRelayCardBody(card: card, media: media),
          ],
          if (source != null) ...[
            const SizedBox(height: 14),
            for (var index = 0; index < source.moments.length; index++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: AppColors.berrySoft,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(
                          color: AppColors.berry,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            source.moments[index].childLine,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          Text(
                            source.moments[index].translationZh,
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
          if (card.reactions.isNotEmpty) ...[
            const Divider(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final reaction in card.reactions)
                  _ReactionChip(reaction: reaction, store: store),
              ],
            ),
          ],
          if (card.continuations.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final continuation in card.continuations)
              _ContinuationNote(
                continuation: continuation,
                store: store,
                media: media,
              ),
          ],
          if (adultActions) ...[
            const Divider(height: 26),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.jadeSoft,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.family_restroom_rounded,
                    color: AppColors.jade,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      '把我們家的版本說回來：${familyCulturePromptForEpisode(card.episode)}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              '用一個表情回應',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 9),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final sticker in FamilySticker.values)
                  ChoiceChip(
                    key: ValueKey('reaction-${card.id}-${sticker.name}'),
                    selected: actorReaction?.sticker == sticker,
                    onSelected: (_) => onReact(sticker),
                    avatar: Icon(_stickerIcon(sticker), size: 18),
                    label: Text(sticker.zhLabel),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              key: ValueKey('continue-${card.id}'),
              onPressed: onContinue,
              icon: const Icon(Icons.add_comment_outlined),
              label: const Text('留一句，孩子下次會看到'),
            ),
          ] else if (card.reactions.isEmpty && card.continuations.isEmpty) ...[
            const Divider(height: 24),
            const Text(
              '故事已經完整演完；家人有空時可以再來加一個驚喜。',
              style: TextStyle(color: AppColors.muted),
            ),
          ],
        ],
      ),
    );
  }
}

class _FamilyRelayCardBody extends StatelessWidget {
  const _FamilyRelayCardBody({required this.card, required this.media});

  final FamilyCircleStoryCard card;
  final LocalMediaService media;

  Future<void> _play(BuildContext context, String path) async {
    try {
      await media.playLocal(path);
    } on Object catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Bad state: ', '')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey('family-circle-relay-${card.relayId}'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.sunSoft, AppColors.jadeSoft],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '三棒家庭接力',
            style: TextStyle(
              color: AppColors.berry,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          _RelayCircleLine(
            number: 1,
            label: '孩子帶回',
            text: card.childChoice ?? '今天有一件事想告訴家人。',
            color: AppColors.coral,
          ),
          const _RelayCircleConnector(),
          _RelayCircleLine(
            number: 2,
            label: '家人傳下',
            text: card.childUtterance ?? '家人已留下家庭版本。',
            color: AppColors.berry,
          ),
          if (card.familyRecordingReference case final path?) ...[
            const SizedBox(height: 7),
            OutlinedButton.icon(
              onPressed: () => _play(context, path),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('播放家人原音'),
            ),
          ],
          const _RelayCircleConnector(),
          _RelayCircleLine(
            number: 3,
            label: '孩子接住',
            text: card.localRecordingReference == null
                ? '用文字完成這一棒'
                : '已留下孩子自己的錄音',
            color: AppColors.jade,
          ),
          if (card.localRecordingReference case final path?) ...[
            const SizedBox(height: 7),
            OutlinedButton.icon(
              onPressed: () => _play(context, path),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('播放孩子接棒'),
            ),
          ],
        ],
      ),
    );
  }
}

class _RelayCircleLine extends StatelessWidget {
  const _RelayCircleLine({
    required this.number,
    required this.label,
    required this.text,
    required this.color,
  });

  final int number;
  final String label;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: color,
            foregroundColor: Colors.white,
            child: Text(
              '$number',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(color: color, fontWeight: FontWeight.w900),
                ),
                Text(text),
              ],
            ),
          ),
        ],
      );
}

class _RelayCircleConnector extends StatelessWidget {
  const _RelayCircleConnector();

  @override
  Widget build(BuildContext context) => const SizedBox(
        height: 24,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: EdgeInsets.only(left: 5),
            child: Icon(
              Icons.arrow_downward_rounded,
              size: 18,
              color: AppColors.muted,
            ),
          ),
        ),
      );
}

class _ContinuationNote extends StatelessWidget {
  const _ContinuationNote({
    required this.continuation,
    required this.store,
    required this.media,
  });

  final AdultStoryContinuation continuation;
  final FamilyCircleStore store;
  final LocalMediaService media;

  @override
  Widget build(BuildContext context) {
    final member = store.memberById(continuation.adultMemberId);
    final nickname = member?.nickname ?? '家人';
    return Semantics(
      container: true,
      label: '$nickname留給你的話：${continuation.text}',
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: AppColors.berrySoft,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: member == null
                    ? Colors.white
                    : Color(member.roleColorValue),
                shape: BoxShape.circle,
              ),
              child: Icon(
                member == null
                    ? Icons.chat_bubble_rounded
                    : _memberAvatarIcon(member),
                color: AppColors.ink,
                size: 21,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$nickname 留給你',
                    style: const TextStyle(
                      color: AppColors.berry,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    continuation.text,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
            if (continuation.localRecordingReference != null)
              IconButton(
                tooltip: '播放$nickname錄下的話',
                onPressed: () async {
                  try {
                    await media.playLocal(
                      continuation.localRecordingReference!,
                    );
                  } on Object catch (error) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('$error')),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.volume_up_rounded),
              ),
          ],
        ),
      ),
    );
  }
}

class _ReactionChip extends StatelessWidget {
  const _ReactionChip({required this.reaction, required this.store});

  final FamilyStickerReaction reaction;
  final FamilyCircleStore store;

  @override
  Widget build(BuildContext context) {
    final member = store.memberById(reaction.memberId);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.coralSoft,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _stickerIcon(reaction.sticker),
            size: 17,
            color: AppColors.coral,
          ),
          const SizedBox(width: 5),
          Text(
            member?.nickname ?? '家人',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _EmptyCircle extends StatelessWidget {
  const _EmptyCircle();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.berrySoft,
        borderRadius: BorderRadius.circular(26),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.menu_book_rounded,
            size: 50,
            color: AppColors.berry,
          ),
          const SizedBox(height: 8),
          const Text(
            '第一張故事卡還在等你',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          const Text(
            '去劇場演完三個回合，它就會自己出現在這裡。',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}
