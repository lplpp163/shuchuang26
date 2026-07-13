import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_theme.dart';
import '../services/app_store.dart';
import '../services/local_media_service.dart';
import '../widgets/brand_mark.dart';
import 'theater_preview_screen.dart';

class PrivacyGate extends StatefulWidget {
  const PrivacyGate({required this.store, required this.media, super.key});

  final AppStore store;
  final LocalMediaService media;

  @override
  State<PrivacyGate> createState() => _PrivacyGateState();
}

class _PrivacyGateState extends State<PrivacyGate> {
  final TextEditingController _adultPin = TextEditingController();
  bool _familyPermission = false;
  bool _localStorage = false;
  bool _busy = false;

  @override
  void dispose() {
    _adultPin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canContinue = _familyPermission &&
        _localStorage &&
        RegExp(r'^\d{4}$').hasMatch(_adultPin.text) &&
        !_busy;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const BrandMark(),
                  const SizedBox(height: 8),
                  const Text(
                    '聽家人說，換你回一句',
                    style: TextStyle(color: AppColors.muted),
                  ),
                  const SizedBox(height: 20),
                  _PreviewInvitation(
                    onTap: () => Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (context) =>
                            TheaterPreviewScreen(media: widget.media),
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                  Text(
                    '先取得家人的同意',
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '家人的聲音、照片與孩子的回答都可能辨識身分。App 不會把素材送到我們的伺服器或拿去訓練模型；裝置的作業系統備份仍受平台設定影響。',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyLarge?.copyWith(color: AppColors.muted),
                  ),
                  const SizedBox(height: 24),
                  _ConsentTile(
                    value: _familyPermission,
                    title: '我已得到錄音者與孩子監護人的同意',
                    subtitle: '家人可以隨時撤回，並刪除裝置上的資料。',
                    onChanged: (value) =>
                        setState(() => _familyPermission = value),
                  ),
                  const SizedBox(height: 10),
                  _ConsentTile(
                    value: _localStorage,
                    title: '我了解資料會保存在這支裝置',
                    subtitle: '匯出檔只有文字與紀錄；Android 已關閉 App 備份，iOS 仍須檢查系統備份設定。',
                    onChanged: (value) => setState(() => _localStorage = value),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _adultPin,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: '設定四位數家長碼',
                      helperText: '進入錄一句、家人聽聽、匯出或刪除前會再次詢問。',
                      prefixIcon: Icon(Icons.pin_outlined),
                    ),
                  ),
                  const SizedBox(height: 26),
                  FilledButton(
                    onPressed: canContinue
                        ? () async {
                            setState(() => _busy = true);
                            await widget.store.acceptPrivacy(
                              adultPin: _adultPin.text,
                            );
                          }
                        : null,
                    child: Text(_busy ? '正在儲存…' : '同意並開始'),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '此同意只適用於本機競賽原型；正式上線仍須有完整兒少隱私政策與家長權限。',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PreviewInvitation extends StatelessWidget {
  const _PreviewInvitation({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 230,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A253331),
            blurRadius: 22,
            offset: Offset(0, 9),
          ),
        ],
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/family-homecoming-theater-v2.png',
            fit: BoxFit.cover,
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x08000000), Color(0xE6253331)],
                stops: [.2, 1],
              ),
            ),
          ),
          Positioned(
            left: 18,
            right: 18,
            bottom: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '先看一句話怎麼讓故事改變',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                const Text(
                  '不錄音、不儲存，也不用先填家庭資料。',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  key: const ValueKey('open-theater-preview'),
                  onPressed: onTap,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.sun,
                    foregroundColor: AppColors.ink,
                  ),
                  icon: const Icon(Icons.theater_comedy_rounded),
                  label: const Text('先試演 30 秒'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConsentTile extends StatelessWidget {
  const _ConsentTile({
    required this.value,
    required this.title,
    required this.subtitle,
    required this.onChanged,
  });

  final bool value;
  final String title;
  final String subtitle;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppColors.border),
      ),
      child: CheckboxListTile(
        value: value,
        onChanged: (next) => onChanged(next ?? false),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        title: Text(title, style: Theme.of(context).textTheme.titleMedium),
        subtitle: Text(subtitle),
      ),
    );
  }
}
