import 'package:flutter_test/flutter_test.dart';
import 'package:hometongue_tags/models/education_opportunity.dart';

void main() {
  test('timed opportunity status includes both collection boundary days', () {
    final opportunity = EducationOpportunityCatalog.official.firstWhere(
      (item) => item.id == 'moe-2026-multilingual-reading',
    );

    expect(opportunity.statusAt(DateTime(2026, 7, 13)), '即將收件');
    expect(opportunity.statusAt(DateTime(2026, 9, 20, 23, 59)), '即將收件');
    expect(opportunity.statusAt(DateTime(2026, 9, 21)), '收件中');
    expect(opportunity.statusAt(DateTime(2026, 10, 23, 23, 59)), '收件中');
    expect(opportunity.statusAt(DateTime(2026, 10, 24)), '已截止');
  });

  test('official catalog separates live resources from finished results', () {
    final portal = EducationOpportunityCatalog.official.firstWhere(
      (item) => item.id == 'moe-new-resident-education-portal',
    );
    final results = EducationOpportunityCatalog.official.firstWhere(
      (item) => item.id == 'moe-2026-storytelling-results',
    );

    expect(portal.statusAt(DateTime(2030)), '持續更新');
    expect(results.statusAt(DateTime(2026, 7, 13)), '已結束・成果參考');
    expect(
      EducationOpportunityCatalog.official.every(
        (item) => item.officialUrl.scheme == 'https',
      ),
      isTrue,
    );
    expect(EducationOpportunityCatalog.checkedOnLabel, contains('2026-07-14'));
    expect(
      EducationOpportunityCatalog.official.every(
        (item) =>
            item.officialRulesUrl == null ||
            item.officialRulesUrl!.scheme == 'https',
      ),
      isTrue,
    );
  });

  test('official information exposes a deterministic stale boundary', () {
    final opportunity = EducationOpportunityCatalog.official.firstWhere(
      (item) => item.id == 'moe-2026-multilingual-reading',
    );

    expect(opportunity.checkedOnLabel, '查核 2026-07-14');
    expect(opportunity.reviewByLabel, '下次複查 2026-07-28');
    expect(opportunity.needsReviewAt(DateTime(2026, 7, 28, 23, 59)), isFalse);
    expect(opportunity.needsReviewAt(DateTime(2026, 7, 29)), isTrue);
    expect(opportunity.eligibilityLabel, isNotEmpty);
    expect(opportunity.applicationRoleLabel, isNotEmpty);
    expect(opportunity.ruleSummary, isNotEmpty);
  });

  test('every official entry maps to a real local story extension', () {
    final storyIdeaIds = StoryIdeaCatalog.next.map((idea) => idea.id).toSet();

    expect(
      EducationOpportunityCatalog.official.every(
        (item) => storyIdeaIds.contains(item.localStoryIdeaId),
      ),
      isTrue,
    );
    expect(
      EducationOpportunityCatalog.official.every(
        (item) => item.localActionLabel.trim().isNotEmpty,
      ),
      isTrue,
    );
    expect(
      {
        for (final item in EducationOpportunityCatalog.official)
          item.id: item.localStoryIdeaId,
      },
      {
        'moe-2026-multilingual-reading': 'family-sharing',
        'moe-new-resident-education-portal': 'class',
        'moe-2026-storytelling-results': 'family-sharing',
      },
    );
  });

  test('five future story ideas are prompts, not episode records', () {
    expect(
      StoryIdeaCatalog.next.map((idea) => idea.title),
      ['和家人分享', '社團', '午餐', '上課', '朋友關係'],
    );
    expect(
      StoryIdeaCatalog.next.every((idea) => idea.prompt.contains('「')),
      isTrue,
    );
  });
}
