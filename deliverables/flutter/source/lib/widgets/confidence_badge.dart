import 'package:flutter/material.dart';

import '../core/app_theme.dart';

class ConfidenceBadge extends StatelessWidget {
  const ConfidenceBadge({
    required this.confidence,
    required this.confirmed,
    this.isSample = false,
    super.key,
  });

  final double confidence;
  final bool confirmed;
  final bool isSample;

  @override
  Widget build(BuildContext context) {
    final needsReview = !confirmed;
    final background = isSample
        ? AppColors.cream
        : needsReview
            ? AppColors.coralSoft
            : AppColors.jadeSoft;
    final foreground = isSample
        ? AppColors.muted
        : needsReview
            ? AppColors.coral
            : AppColors.jade;
    return Tooltip(
      message: isSample ? '這是內建文字示範，尚待越南語母語者審閱。' : '題目由固定規則整理，家人決定內容是不是自然。',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSample
                  ? Icons.menu_book_outlined
                  : needsReview
                      ? Icons.person_outline
                      : Icons.verified_outlined,
              size: 15,
              color: foreground,
            ),
            const SizedBox(width: 5),
            Text(
              isSample
                  ? '文字示範'
                  : needsReview
                      ? '請家人看過'
                      : '家人看過',
              style: TextStyle(
                color: foreground,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
