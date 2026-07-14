import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometongue_tags/core/app_theme.dart';
import 'package:hometongue_tags/models/education_opportunity.dart';
import 'package:hometongue_tags/models/family_circle.dart';
import 'package:hometongue_tags/screens/practice_hub_screen.dart';
import 'package:hometongue_tags/services/family_circle_store.dart';

void main() {
  final checkedAt = DateTime(2026, 7, 13);

  Future<FamilyCircleStore> familyCircle() async {
    final store = await FamilyCircleStore.load(
      storage: MemoryFamilyCircleStorage(),
      clock: () => checkedAt,
    );
    await store.bootstrapAdult(
      FamilyMember(
        id: 'grandma',
        relationship: '外婆',
        nickname: '阿嬤',
        isAdult: true,
        avatarEmoji: 'elder-woman',
        roleColorValue: 0xFFFFE5DE,
        createdAt: checkedAt,
      ),
    );
    return store;
  }

  Future<void> pumpHub(
    WidgetTester tester, {
    required Future<bool> Function(Uri url) launchOfficialUrl,
    Future<void> Function(StoryIdea idea)? onCreateFromIdea,
    Set<String> completedStoryIdeaIds = const <String>{},
    DateTime? now,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: PracticeHubScreen(
            familyCircle: await familyCircle(),
            onOpenEpisode: (_) async {},
            onCreateFromIdea: onCreateFromIdea ?? (_) async {},
            completedStoryIdeaIds: completedStoryIdeaIds,
            now: () => now ?? checkedAt,
            launchOfficialUrl: launchOfficialUrl,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openOpportunitySheet(WidgetTester tester) async {
    final entry = find.byKey(const ValueKey('education-opportunity-entry'));
    await tester.scrollUntilVisible(
      entry,
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('show-education-opportunities')));
    await tester.pumpAndSettle();
  }

  testWidgets('story library hands five ideas to the family draft flow', (
    tester,
  ) async {
    StoryIdea? selectedIdea;
    await pumpHub(
      tester,
      launchOfficialUrl: (_) async => true,
      onCreateFromIdea: (idea) async {
        selectedIdea = idea;
      },
    );
    expect(
      find.byKey(const ValueKey('library-top-story-teaser')),
      findsOneWidget,
    );
    expect(find.text('把今天的事帶回家說'), findsOneWidget);
    expect(find.textContaining('3 筆官方教材・課程・競賽入口'), findsOneWidget);
    for (final idea in StoryIdeaCatalog.next) {
      expect(
          find.byKey(ValueKey('story-seed-chip-${idea.id}')), findsOneWidget);
    }
    final section = find.byKey(const ValueKey('story-idea-section'));
    await tester.scrollUntilVisible(
      section,
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('家庭故事靈感'), findsOneWidget);
    expect(find.textContaining('不是已完成劇集'), findsOneWidget);
    expect(find.textContaining('119 個內建示範音檔'), findsOneWidget);
    expect(find.textContaining('由家人確認、孩子可闖四關'), findsOneWidget);
    for (final idea in StoryIdeaCatalog.next) {
      expect(find.text(idea.title), findsOneWidget);
      expect(find.text(idea.prompt), findsOneWidget);
      expect(
        find.byKey(ValueKey('create-story-idea-${idea.id}')),
        findsOneWidget,
      );
    }
    expect(find.text('共創題材'), findsNWidgets(5));
    expect(find.text('交給家人做成四關任務'), findsNWidgets(5));

    final clubButton = find.byKey(const ValueKey('create-story-idea-club'));
    await tester.ensureVisible(clubButton);
    await tester.tap(clubButton);
    await tester.pump();
    expect(selectedIdea?.id, 'club');
    expect(selectedIdea?.draftSource, contains('社團'));
  });

  testWidgets('story passport counts only completed seed ids', (tester) async {
    await pumpHub(
      tester,
      launchOfficialUrl: (_) async => true,
      completedStoryIdeaIds: const {'club', 'lunch', 'not-a-story-seed'},
    );

    expect(
      find.byKey(const ValueKey('story-passport-progress')),
      findsOneWidget,
    );
    final passportCount = find.byKey(const ValueKey('story-passport-count'));
    expect(passportCount, findsOneWidget);
    expect(tester.widget<Text>(passportCount).data, '2／5');
    expect(find.text('已完成2種日常；再收集3種，就有一組家庭說故事素材。'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('story-seed-chip-club')),
        matching: find.byIcon(Icons.check_circle_rounded),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('story-seed-chip-friendship')),
        matching: find.byIcon(Icons.check_circle_rounded),
      ),
      findsNothing,
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('story-idea-section')),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('護照已蓋章'), findsNWidgets(2));
  });

  testWidgets('official information stays in app until its button is tapped', (
    tester,
  ) async {
    var launchCount = 0;
    Uri? launchedUrl;
    await pumpHub(
      tester,
      launchOfficialUrl: (url) async {
        launchCount++;
        launchedUrl = url;
        return true;
      },
    );

    await openOpportunitySheet(tester);
    expect(launchCount, 0);
    expect(find.text('即將收件'), findsOneWidget);
    expect(find.text('持續更新'), findsOneWidget);
    expect(find.text('已結束・成果參考'), findsOneWidget);
    expect(find.textContaining('查核 2026-07-14'), findsNWidgets(3));
    expect(
      find.text('資格、期限與文件一律以官網最新公告為準'),
      findsNWidgets(3),
    );
    expect(find.textContaining('適用｜'), findsNWidgets(3));
    expect(find.textContaining('報名角色｜'), findsNWidgets(3));
    expect(find.textContaining('規則重點｜'), findsNWidgets(3));
    expect(
      find.text('官方主辦：教育部國民及學前教育署'),
      findsNWidgets(3),
    );

    final button = find.byKey(
      const ValueKey('open-official-moe-2026-multilingual-reading'),
    );
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();

    expect(launchCount, 1);
    expect(
      launchedUrl,
      Uri.parse('https://mkm.k12ea.gov.tw/news/17202605110001'),
    );
  });

  testWidgets('stale official information is visibly blocked for recheck', (
    tester,
  ) async {
    await pumpHub(
      tester,
      launchOfficialUrl: (_) async => true,
      now: DateTime(2026, 8, 1),
    );

    await openOpportunitySheet(tester);
    expect(
      find.byKey(
        const ValueKey('education-stale-moe-2026-multilingual-reading'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('education-stale-moe-new-resident-education-portal'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('education-stale-moe-2026-storytelling-results'),
      ),
      findsNothing,
    );
  });

  testWidgets('reading opportunity starts a local family-sharing extension', (
    tester,
  ) async {
    var launchCount = 0;
    StoryIdea? selectedIdea;
    await pumpHub(
      tester,
      launchOfficialUrl: (_) async {
        launchCount++;
        return true;
      },
      onCreateFromIdea: (idea) async {
        selectedIdea = idea;
      },
    );

    await openOpportunitySheet(tester);
    expect(find.text('主題延伸，非官方授權教案'), findsNWidgets(3));
    final localExtension = find.byKey(
      const ValueKey(
        'start-local-extension-moe-2026-multilingual-reading',
      ),
    );
    await tester.ensureVisible(localExtension);
    await tester.tap(localExtension);
    await tester.pumpAndSettle();

    expect(selectedIdea?.id, 'family-sharing');
    expect(launchCount, 0);
    expect(
      find.byKey(const ValueKey('education-opportunity-list')),
      findsNothing,
    );
  });

  testWidgets('failed official launch shows a visible in-app explanation', (
    tester,
  ) async {
    await pumpHub(tester, launchOfficialUrl: (_) async => false);
    await openOpportunitySheet(tester);

    final button = find.byKey(
      const ValueKey('open-official-moe-2026-multilingual-reading'),
    );
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('official-link-error')), findsOneWidget);
    expect(find.text('無法開啟官方頁'), findsOneWidget);
    expect(find.textContaining('以官網公告為準'), findsOneWidget);
  });
}
