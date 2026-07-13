import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_theme.dart';
import '../services/app_store.dart';
import '../services/family_circle_store.dart';
import '../services/local_media_service.dart';

class PrivacyCenterSheet extends StatefulWidget {
  const PrivacyCenterSheet({
    required this.store,
    required this.familyCircle,
    required this.adultMemberId,
    required this.media,
    super.key,
  });

  final AppStore store;
  final FamilyCircleStore familyCircle;
  final String adultMemberId;
  final LocalMediaService media;

  @override
  State<PrivacyCenterSheet> createState() => _PrivacyCenterSheetState();
}

class _PrivacyCenterSheetState extends State<PrivacyCenterSheet> {
  bool _busy = false;

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      const message = '完整 JSON 已複製，可貼到本機文字檔保存。';
      final clipboardText = jsonEncode({
        'learningAndStories': jsonDecode(widget.store.exportJson()),
        'privateFamilyCircle': jsonDecode(widget.familyCircle.exportJson()),
      });
      await Clipboard.setData(ClipboardData(text: clipboardText));
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportPilotSummary() async {
    setState(() => _busy = true);
    try {
      await Clipboard.setData(
        ClipboardData(text: widget.store.exportPilotSummaryJson()),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('匿名試點摘要已複製；不含家庭短句、姓名或錄音路徑。')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _erase() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('刪除所有家庭資料？'),
        content: const Text('故事、音檔、照片與孩子的回答都會從這支裝置移除，無法復原。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.coral),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('全部刪除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      // The stores are independent, so start both erasures before awaiting
      // either one. A failure cannot silently prevent the other store from
      // receiving its deletion request.
      await Future.wait<void>([
        widget.familyCircle.deleteLocalCircle(
          actorMemberId: widget.adultMemberId,
        ),
        widget.store.eraseEverything(widget.media.eraseAllMedia),
      ]);
      if (mounted) Navigator.pop(context);
    } on Object {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('刪除沒有完整完成。請保留此頁、重新嘗試；若裝置空間或瀏覽器權限異常，請先排除後再刪除。'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        24,
        14,
        24,
        24 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text('隱私與資料', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 10),
          const Text(
            '家庭錄音預設保存在這個裝置，也不會被用來訓練模型。孩子只有主動使用「系統聽成什麼」時，裝置或瀏覽器才可能將當次語音送給其辨識供應商。Android 已關閉 App 備份；iOS 的系統備份仍須由使用者另行檢查。',
          ),
          const SizedBox(height: 20),
          const _PrivacyRow(
            icon: Icons.smartphone_outlined,
            title: '本機優先',
            body:
                '家庭資料預設留在這台裝置。內建示範音檔可直接播放；錄音、聽寫與裝置語音是否能在斷網時使用，仍依瀏覽器或作業系統能力而定。',
          ),
          const _PrivacyRow(
            icon: Icons.person_outline,
            title: '真人作最後判斷',
            body: '本機引擎只做草稿，不評判口音；家人才決定是否聽懂。',
          ),
          const _PrivacyRow(
            icon: Icons.cloud_off_outlined,
            title: '預設不連外部生成服務',
            body:
                '生活草稿、分段與節奏提示都在本機處理，不需要生成服務金鑰。裝置 TTS 與聽寫由作業系統或瀏覽器提供，是否連網依平台設定；開口前會另行提醒。',
          ),
          const _PrivacyRow(
            icon: Icons.lock_open_outlined,
            title: '原型尚未額外加密',
            body: '資料在 App 私有目錄，但尚未做應用層加密；公開展示請只用已同意的測試素材。',
          ),
          const _PrivacyRow(
            icon: Icons.pin_outlined,
            title: '管理碼留在本機',
            body: '連續五次錯誤會暫停 30 秒，錯誤次數與鎖定在重開後仍保留；但這仍不是遠端帳號，也沒有安全硬體保護。',
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: _busy ? null : _export,
            icon: const Icon(Icons.download_outlined),
            label: const Text('匯出文字與學習紀錄'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            key: const ValueKey('export-pilot-summary'),
            onPressed: _busy ? null : _exportPilotSummary,
            icon: const Icon(Icons.analytics_outlined),
            label: const Text('複製匿名試點摘要'),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(8, 6, 8, 0),
            child: Text(
              '只彙總五類題材的接棒階段、錄音使用數與平均時間；不含姓名、原句、譯句、成員 ID、故事 ID 或媒體路徑。是否交給教師仍由家庭決定。',
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: _busy ? null : _erase,
            style: TextButton.styleFrom(foregroundColor: AppColors.coral),
            icon: const Icon(Icons.delete_forever_outlined),
            label: const Text('刪除這支裝置上的全部資料'),
          ),
        ],
      ),
    );
  }
}

class _PrivacyRow extends StatelessWidget {
  const _PrivacyRow({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.jade),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                Text(body, style: const TextStyle(color: AppColors.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
