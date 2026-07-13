import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_theme.dart';
import '../services/app_store.dart';

Future<bool> requestAdultPin(
  BuildContext context,
  AppStore store, {
  required String reason,
}) async {
  var pin = '';
  String? errorText;
  var checking = false;
  final unlocked = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) {
        Future<void> verify() async {
          if (checking || store.adultPinLocked) return;
          setDialogState(() {
            checking = true;
            errorText = null;
          });
          final matches = await store.verifyAdultPin(pin);
          if (!context.mounted) return;
          if (matches) {
            Navigator.pop(context, true);
            return;
          }
          setDialogState(() {
            checking = false;
            errorText = store.adultPinLocked
                ? '嘗試次數過多，請在 ${store.pinLockRemainingSeconds} 秒後再試'
                : '家長碼不正確，還可嘗試 ${store.remainingPinAttempts} 次';
          });
        }

        return AlertDialog(
          icon: const Icon(
            Icons.admin_panel_settings_outlined,
            color: AppColors.jade,
          ),
          title: const Text('請由成人操作'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(reason),
                const SizedBox(height: 14),
                TextField(
                  autofocus: true,
                  obscureText: true,
                  enabled: !checking,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: '四位數家長碼',
                    errorText: errorText,
                  ),
                  onChanged: (value) => pin = value,
                  onSubmitted: (_) => verify(),
                ),
                const Text(
                  '這是競賽原型的本機角色區隔；連續輸錯會暫停嘗試。',
                  style: TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: checking ? null : () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: checking || store.adultPinLocked ? null : verify,
              child: Text(checking ? '正在確認…' : '確認'),
            ),
          ],
        );
      },
    ),
  );
  return unlocked ?? false;
}
