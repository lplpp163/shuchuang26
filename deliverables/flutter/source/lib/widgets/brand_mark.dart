import 'package:flutter/material.dart';

import '../core/app_theme.dart';

const appBrandName = '傳家話';
const appBrandTagline = '說一句・演成我們家的故事';

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: compact ? 36 : 46,
          height: compact ? 36 : 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.coral, AppColors.sun],
            ),
            borderRadius: BorderRadius.circular(compact ? 12 : 15),
            boxShadow: const [
              BoxShadow(color: Color(0x22E96B52), blurRadius: 8),
            ],
          ),
          child: Icon(
            Icons.record_voice_over_rounded,
            color: Colors.white,
            size: compact ? 22 : 28,
          ),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(appBrandName, style: Theme.of(context).textTheme.titleLarge),
            Text(
              appBrandTagline,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.muted,
                    letterSpacing: .2,
                  ),
            ),
          ],
        ),
      ],
    );
  }
}
