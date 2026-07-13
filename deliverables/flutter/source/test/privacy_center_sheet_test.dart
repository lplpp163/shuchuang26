import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometongue_tags/models/family_circle.dart';
import 'package:hometongue_tags/services/app_store.dart';
import 'package:hometongue_tags/services/family_circle_store.dart';
import 'package:hometongue_tags/services/local_media_service.dart';
import 'package:hometongue_tags/widgets/privacy_center_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SilentMediaService extends LocalMediaService {
  @override
  Future<void> stopPlayback() async {}

  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('pilot summary button copies only aggregate evidence',
      (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = await AppStore.load();
    await store.startFamilyRelay(
      seedId: 'club',
      seedTitle: 'SECRET_SEED_TITLE',
      childIntentZh: 'SECRET_CHILD_INTENT',
      childMemberId: 'SECRET_CHILD_MEMBER',
    );
    final now = DateTime.utc(2026, 7, 14);
    final familyCircle = await FamilyCircleStore.load(
      storage: MemoryFamilyCircleStorage(),
      clock: () => now,
    );
    await familyCircle.bootstrapAdult(
      FamilyMember(
        id: 'grandma',
        relationship: '外婆',
        nickname: '阿嬤',
        isAdult: true,
        avatarEmoji: 'elder-woman',
        roleColorValue: 0xFFFFE5DE,
        createdAt: now,
      ),
    );
    String? copiedText;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copiedText =
            (call.arguments as Map<Object?, Object?>)['text'] as String?;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PrivacyCenterSheet(
            store: store,
            familyCircle: familyCircle,
            adultMemberId: 'grandma',
            media: _SilentMediaService(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('複製匿名試點摘要'), findsOneWidget);
    expect(find.textContaining('只彙總五類題材的接棒階段'), findsOneWidget);
    expect(
      find.textContaining('不含姓名、原句、譯句、成員 ID、故事 ID 或媒體路徑'),
      findsOneWidget,
    );
    expect(find.textContaining('是否交給教師仍由家庭決定'), findsOneWidget);

    final export = find.byKey(const ValueKey('export-pilot-summary'));
    await tester.scrollUntilVisible(
      export,
      240,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(export);
    await tester.pumpAndSettle();

    expect(copiedText, isNotNull);
    final copied = jsonDecode(copiedText!) as Map<String, dynamic>;
    expect(copied['schema'], 'hometongue-pilot-summary-v1');
    expect(copied.containsKey('generatedAt'), isFalse);
    expect(
      (copied['totals'] as Map<String, dynamic>)['started'],
      1,
    );
    expect(copiedText, isNot(contains('SECRET_CHILD_INTENT')));
    expect(copiedText, isNot(contains('SECRET_CHILD_MEMBER')));
    expect(copiedText, isNot(contains('SECRET_SEED_TITLE')));
    expect(
      find.text('匿名試點摘要已複製；不含家庭短句、姓名或錄音路徑。'),
      findsOneWidget,
    );
  });
}
