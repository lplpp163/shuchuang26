import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/app_theme.dart';
import '../services/app_store.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({required this.store, super.key});

  final AppStore store;

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final MobileScannerController _scanner = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );
  final TextEditingController _code = TextEditingController();
  bool _handling = false;
  String? _error;

  @override
  void dispose() {
    _scanner.dispose();
    _code.dispose();
    super.dispose();
  }

  void _resolve(String raw) {
    if (_handling) return;
    _handling = true;
    final story = widget.store.findStory(raw);
    if (story != null) {
      Navigator.pop(context, story);
      return;
    }
    setState(() {
      _error = '這支手機裡找不到這個代碼。';
      _handling = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('家中尋寶（選配）')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: SizedBox(
              height: 300,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  MobileScanner(
                    controller: _scanner,
                    onDetect: (capture) {
                      for (final barcode in capture.barcodes) {
                        final raw = barcode.rawValue;
                        if (raw != null) {
                          _resolve(raw);
                          break;
                        }
                      }
                    },
                  ),
                  IgnorePointer(
                    child: Center(
                      child: Container(
                        width: 210,
                        height: 210,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white, width: 3),
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            '把鏡頭對準家中的 QR Code，就能找到藏在這裡的一句話。掃描只在這支裝置上解析。',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 26),
          Row(
            children: [
              const Expanded(child: Divider()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  '無法使用相機',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppColors.muted),
                ),
              ),
              const Expanded(child: Divider()),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _code,
            autocorrect: false,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: '輸入尋寶代碼',
              hintText: '例如 HT-NUOC-MAM',
              errorText: _error,
              prefixIcon: const Icon(Icons.tag_rounded),
            ),
            onSubmitted: _resolve,
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => _resolve(_code.text),
            child: const Text('找到這句話'),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () {
              _code.text = 'HT-NUOC-MAM';
              _resolve(_code.text);
            },
            child: const Text('使用內建越南語範例'),
          ),
        ],
      ),
    );
  }
}
