import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_theme.dart';
import '../models/family_invitation.dart';
import '../services/family_circle_store.dart';

typedef FamilyInvitationAcceptor = Future<String> Function(
  String source, {
  required String pin,
});

/// Lets an invited adult personally accept a manually exchanged invitation.
///
/// This deliberately does not import family data or claim that another device
/// has been updated. It only creates the signed receipt that must be carried
/// back to the original family circle for final approval.
Future<void> showAcceptFamilyInvitationFlow(
  BuildContext context, {
  FamilyInvitationAcceptor? acceptInvitation,
}) async {
  final effectiveAcceptor = acceptInvitation ??
      (source, {required pin}) =>
          FamilyCircleStore.acceptAdultInvitationPackage(source, pin: pin);
  final packageController = TextEditingController();
  final pinController = TextEditingController();
  final confirmPinController = TextEditingController();
  var confirmedIdentity = false;
  var busy = false;
  String? errorText;
  FamilyInvitationPackage? preview;

  final receipt = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) {
        Future<void> refreshPreview() async {
          final source = packageController.text.trim();
          if (source.isEmpty) {
            setDialogState(() {
              preview = null;
              errorText = null;
            });
            return;
          }
          try {
            final decoded = FamilyInvitationPackage.decode(source);
            setDialogState(() {
              preview = decoded;
              errorText = null;
            });
          } on Object {
            setDialogState(() {
              preview = null;
              errorText = '這份邀請包讀不懂，請原家庭重新做一份。';
            });
          }
        }

        Future<void> pastePackage() async {
          final data = await Clipboard.getData(Clipboard.kTextPlain);
          if (data?.text == null) return;
          packageController.text = data!.text!;
          await refreshPreview();
        }

        Future<void> accept() async {
          if (busy) return;
          final pin = pinController.text;
          if (preview == null) {
            setDialogState(() => errorText = '先貼上原家庭交給你的邀請包。');
            return;
          }
          if (!RegExp(r'^\d{6}$').hasMatch(pin)) {
            setDialogState(() => errorText = '家人碼要剛好六位數。');
            return;
          }
          if (pin != confirmPinController.text) {
            setDialogState(() => errorText = '兩次家人碼不一樣，請再輸入一次。');
            return;
          }
          if (!confirmedIdentity) {
            setDialogState(() => errorText = '請由受邀的家人本人確認加入。');
            return;
          }
          setDialogState(() {
            busy = true;
            errorText = null;
          });
          try {
            final result = await effectiveAcceptor(
              packageController.text,
              pin: pin,
            );
            if (dialogContext.mounted) Navigator.pop(dialogContext, result);
          } on FamilyInvitationException catch (error) {
            setDialogState(() {
              busy = false;
              errorText = switch (error.failure) {
                FamilyInvitationFailure.expired => '這份邀請已過期，請原家庭重新邀請。',
                FamilyInvitationFailure.revoked => '這份邀請已取消，沒有加入任何人。',
                _ => '這份邀請包無法驗證，請原家庭重新做一份。',
              };
            });
          } on Object {
            setDialogState(() {
              busy = false;
              errorText = '現在沒能做出回覆包；原資料沒有被更動，請再試一次。';
            });
          }
        }

        return AlertDialog(
          title: const Text('我收到家人邀請'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '這一步請由受邀的成人本人完成。邀請不會自動傳送，也不會帶入孩子的故事或錄音。',
                    style: TextStyle(color: AppColors.muted, height: 1.45),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    key: const ValueKey('received-invitation-package'),
                    controller: packageController,
                    minLines: 2,
                    maxLines: 4,
                    onChanged: (_) => refreshPreview(),
                    decoration: InputDecoration(
                      labelText: '邀請包',
                      hintText: '貼上原家庭交給你的內容',
                      suffixIcon: IconButton(
                        key: const ValueKey('paste-invitation-package'),
                        tooltip: '從剪貼簿貼上',
                        onPressed: pastePackage,
                        icon: const Icon(Icons.content_paste_rounded),
                      ),
                    ),
                  ),
                  if (preview != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.jade.withValues(alpha: .10),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        '${preview!.circleDisplayName} 邀請你以「${preview!.invitedAdult.nickname}」加入',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('invited-adult-pin'),
                    controller: pinController,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: '設定你的六位數家人碼',
                      helperText: '之後用你的角色回應時，只問你自己的家人碼。',
                      prefixIcon: Icon(Icons.pin_outlined),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    key: const ValueKey('confirm-invited-adult-pin'),
                    controller: confirmPinController,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: '再輸入一次家人碼',
                      prefixIcon: Icon(Icons.verified_user_outlined),
                    ),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: confirmedIdentity,
                    onChanged: busy
                        ? null
                        : (value) => setDialogState(
                              () => confirmedIdentity = value ?? false,
                            ),
                    title: Text(
                      preview == null
                          ? '我是受邀的家人，願意加入'
                          : '我就是受邀的 ${preview!.invitedAdult.nickname}，願意加入',
                    ),
                    subtitle: const Text('接受後仍要交回回覆包，由原家庭最後確認。'),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  if (errorText != null)
                    Text(
                      errorText!,
                      key: const ValueKey('invitation-acceptance-error'),
                      style: const TextStyle(
                        color: AppColors.coral,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(dialogContext),
              child: const Text('先不要'),
            ),
            FilledButton.icon(
              key: const ValueKey('accept-invitation-create-receipt'),
              onPressed: busy ? null : accept,
              icon: busy
                  ? const SizedBox.square(
                      dimension: 17,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.mark_email_read_rounded),
              label: Text(busy ? '正在保護家人碼…' : '接受，做回覆包'),
            ),
          ],
        );
      },
    ),
  );

  await Future<void>.delayed(kThemeAnimationDuration);
  packageController.dispose();
  pinController.dispose();
  confirmPinController.dispose();
  if (receipt == null || !context.mounted) return;

  var copiedReceipt = false;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => PopScope(
        canPop: copiedReceipt,
        child: AlertDialog(
          icon: const Icon(
            Icons.verified_rounded,
            color: AppColors.jade,
            size: 38,
          ),
          title: const Text('你已接受邀請'),
          content: SizedBox(
            width: 470,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '請把這份回覆包帶回原家庭的裝置。原家庭確認後才會正式加入；這裡沒有假裝即時同步。',
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
                      receipt,
                      key: const ValueKey('invitation-receipt-output'),
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            FilledButton.icon(
              key: const ValueKey('copy-invitation-receipt'),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: receipt));
                if (!dialogContext.mounted) return;
                setDialogState(() => copiedReceipt = true);
                await WidgetsBinding.instance.endOfFrame;
                if (!dialogContext.mounted) return;
                final route = ModalRoute.of(dialogContext);
                if (route != null) {
                  Navigator.of(dialogContext).removeRoute(route);
                }
              },
              icon: const Icon(Icons.content_copy_rounded),
              label: const Text('複製回覆包並完成'),
            ),
          ],
        ),
      ),
    ),
  );
}
