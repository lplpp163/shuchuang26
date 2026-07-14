import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometongue_tags/app.dart';
import 'package:hometongue_tags/core/app_theme.dart';
import 'package:hometongue_tags/models/family_circle.dart';
import 'package:hometongue_tags/models/family_invitation.dart';
import 'package:hometongue_tags/models/family_relay.dart';
import 'package:hometongue_tags/services/app_store.dart';
import 'package:hometongue_tags/services/family_circle_store.dart';
import 'package:hometongue_tags/services/family_invitation_crypto.dart';
import 'package:hometongue_tags/services/local_media_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<List<int>> fastTestPinKdf(String pin, List<int> salt) async =>
      List<int>.generate(
        32,
        (index) =>
            pin.codeUnitAt(index % pin.length) ^ salt[index % salt.length],
      );

  Future<AppStore> acceptedStore() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = await AppStore.load(adultPinKdf: fastTestPinKdf);
    await store.acceptPrivacy(adultPin: '2468');
    final circle = await FamilyCircleStore.load();
    final now = DateTime(2026, 7, 13);
    await circle.bootstrapAdult(
      FamilyMember(
        id: primaryAdultMemberId,
        relationship: '外婆',
        nickname: '外婆',
        isAdult: true,
        avatarEmoji: '👵🏻',
        roleColorValue: 0xFFFFE5DE,
        createdAt: now,
      ),
    );
    await circle.inviteMember(
      actorMemberId: primaryAdultMemberId,
      member: FamilyMember(
        id: primaryChildMemberId,
        relationship: '孩子',
        nickname: '小玩家',
        isAdult: false,
        avatarEmoji: '🧒🏻',
        roleColorValue: 0xFFDDEEFF,
        createdAt: now,
      ),
    );
    await circle.approveMember(
      actorMemberId: primaryAdultMemberId,
      memberId: primaryChildMemberId,
    );
    return store;
  }

  Widget testApp(
    AppStore store, {
    LocalMediaService? media,
  }) =>
      HomeTongueApp(
        store: store,
        media: media ?? _SilentMediaService(),
      );

  Future<void> unlockParent(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('parent-mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('continue-to-family-pin')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, '四位數家長碼'),
      '2468',
    );
    await tester.tap(find.widgetWithText(FilledButton, '確認'));
    await tester.pumpAndSettle();
  }

  Future<void> chooseLine(
    WidgetTester tester,
    String translation,
  ) async {
    final choiceId = <String, String>{
      '我回來了。': 'came-home',
      '今天很開心。': 'happy-today',
      '好呀！': 'wash-hands',
    }[translation]!;
    final choice = find.byKey(ValueKey('prepare-$choiceId'));
    await tester.scrollUntilVisible(
      choice,
      260,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(choice);
    await tester.pumpAndSettle();
    final continueWithScene =
        find.byKey(const ValueKey('continue-with-scene-choice'));
    await tester.scrollUntilVisible(
      continueWithScene,
      260,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(continueWithScene);
    await tester.pumpAndSettle();
  }

  Future<void> continueStory(WidgetTester tester) async {
    final button = find.byKey(const ValueKey('continue-theater-story'));
    if (button.evaluate().isEmpty) {
      // MainShell enables the child-controllable auto-continue flow. A
      // pumpAndSettle may already have advanced this act, so there is no
      // manual button left to press.
      return;
    }
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'first launch requires explicit family and local-storage consent',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = await AppStore.load(adultPinKdf: fastTestPinKdf);

      await tester.pumpWidget(testApp(store));
      await tester.pumpAndSettle();

      expect(find.text('傳家話'), findsOneWidget);
      expect(find.text('說一句・演成我們家的故事'), findsOneWidget);
      expect(find.text('聽家人說，換你回一句'), findsNothing);
      expect(find.text('我們家怎麼說'), findsNothing);
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).title,
        '傳家話',
      );
      final semantics = tester.ensureSemantics();
      await tester.pump();
      expect(find.bySemanticsLabel('傳家話'), findsOneWidget);
      semantics.dispose();

      expect(find.text('先取得家人的同意'), findsOneWidget);
      expect(find.text('同意並開始'), findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '同意並開始'),
      );
      expect(button.onPressed, isNull);
    },
  );

  testWidgets('cold launch exposes a zero-data three-act relay preview',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = await AppStore.load(adultPinKdf: fastTestPinKdf);
    final media = _SilentMediaService();
    final storyIdsBefore = store.stories.map((story) => story.id).toList();
    final attemptIdsBefore =
        store.attempts.map((attempt) => attempt.id).toList();
    final relayIdsBefore = store.relays.map((relay) => relay.id).toList();

    await tester.pumpWidget(testApp(store, media: media));
    await tester.pumpAndSettle();

    final previewCta = find.byKey(const ValueKey('open-theater-preview'));
    expect(find.text('先取得家人的同意'), findsOneWidget);
    expect(find.text('先試演約 30 秒'), findsOneWidget);
    expect(find.textContaining('怎麼把一句話傳回家'), findsOneWidget);
    expect(previewCta, findsOneWidget);
    expect(media.played, isEmpty);
    expect(store.privacyConsent, isFalse);

    await tester.tap(previewCta);
    await tester.pumpAndSettle();

    expect(find.text('約 30 秒試演'), findsOneWidget);
    expect(find.text('這次不錄音'), findsOneWidget);
    expect(find.text('不存家庭資料'), findsOneWidget);
    expect(find.text('選一句'), findsOneWidget);
    expect(find.text('看故事變'), findsOneWidget);
    expect(find.text('傳回家'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('preview-act-progress-step-1')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('preview-opening')), findsOneWidget);
    expect(find.byKey(const ValueKey('preview-listen-line')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('finish-theater-preview')), findsOneWidget);
    expect(media.played, isEmpty);
    expect(store.privacyConsent, isFalse);

    expect(
      find.byKey(const ValueKey('preview-choice-icon-came-home')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('preview-choice-icon-a-bit-tired')),
      findsOneWidget,
    );
    expect(find.text('🙋🏻'), findsNothing);
    expect(find.text('😮‍💨'), findsNothing);

    final cameHomeChoice =
        find.byKey(const ValueKey('preview-choice-came-home'));
    await tester.ensureVisible(cameHomeChoice);
    await tester.pumpAndSettle();
    await tester.tap(cameHomeChoice);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('preview-outcome-came-home')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('preview-opening')), findsNothing);
    expect(
      find.byKey(const ValueKey('preview-outcome-stage-home-door-open')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('preview-outcome-icon-came-home')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('preview-outcome-image-home-door-open'),
      ),
      findsOneWidget,
    );
    expect(find.text('✨'), findsNothing);
    expect(find.textContaining('家真正會說的版本或原音'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('preview-act-progress-step-2')),
      findsOneWidget,
    );
    expect(find.textContaining('已聽過：你選的話'), findsOneWidget);
    expect(find.byKey(const ValueKey('preview-to-relay')), findsOneWidget);
    expect(media.played, isNotEmpty);
    expect(store.privacyConsent, isFalse);

    final playedAfterOutcome = media.played.length;
    await tester.ensureVisible(
      find.byKey(const ValueKey('preview-to-relay')),
    );
    await tester.tap(find.byKey(const ValueKey('preview-to-relay')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('preview-act-progress-step-3')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('preview-relay')), findsOneWidget);
    expect(find.byKey(const ValueKey('preview-relay-baton-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('preview-relay-baton-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('preview-relay-baton-3')), findsOneWidget);
    expect(find.text('孩子帶回'), findsOneWidget);
    expect(find.text('家人傳下'), findsOneWidget);
    expect(find.text('孩子接住'), findsOneWidget);
    expect(find.text('門打開了！'), findsOneWidget);
    expect(find.text('Cháu về rồi ạ.'), findsOneWidget);
    expect(find.textContaining('Piper 合成操作示範'), findsOneWidget);
    expect(find.textContaining('不是真人原音'), findsOneWidget);
    expect(find.textContaining('未使用、建立或保存任何家庭資料'), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, '同意後建立我們家的三棒故事'),
      findsOneWidget,
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('preview-replay-outcome')),
    );
    await tester.tap(find.byKey(const ValueKey('preview-replay-outcome')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('preview-act-progress-step-2')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('preview-outcome-came-home')),
      findsOneWidget,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('preview-to-relay')),
    );
    await tester.tap(find.byKey(const ValueKey('preview-to-relay')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('preview-act-progress-step-3')),
      findsOneWidget,
    );

    for (final seed in <String>[
      'family-sharing',
      'club',
      'lunch',
      'class',
      'friendship',
    ]) {
      expect(
        find.byKey(ValueKey('preview-life-seed-$seed')),
        findsOneWidget,
      );
    }
    final clubSeed = find.byKey(const ValueKey('preview-life-seed-club'));
    await tester.ensureVisible(clubSeed);
    await tester.tap(clubSeed);
    await tester.pumpAndSettle();
    expect(find.textContaining('我今天第一次參加社團'), findsOneWidget);
    expect(find.textContaining('系統不會自己猜翻譯'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const ValueKey('preview-relay-listen')),
    );
    await tester.tap(find.byKey(const ValueKey('preview-relay-listen')));
    await tester.pumpAndSettle();
    expect(media.played.length, playedAfterOutcome + 1);
    expect(find.text('三棒接力完成 ✓'), findsOneWidget);

    expect(store.stories.map((story) => story.id).toList(), storyIdsBefore);
    expect(
      store.attempts.map((attempt) => attempt.id).toList(),
      attemptIdsBefore,
    );
    expect(store.relays.map((relay) => relay.id).toList(), relayIdsBefore);
    expect(store.privacyConsent, isFalse);

    await tester.ensureVisible(
      find.byKey(const ValueKey('finish-theater-preview')),
    );
    await tester.tap(find.byKey(const ValueKey('finish-theater-preview')));
    await tester.pumpAndSettle();
    expect(find.text('先取得家人的同意'), findsOneWidget);
    expect(store.stories.map((story) => story.id).toList(), storyIdsBefore);
    expect(
      store.attempts.map((attempt) => attempt.id).toList(),
      attemptIdsBefore,
    );
    expect(store.relays.map((relay) => relay.id).toList(), relayIdsBefore);
  });

  testWidgets('preview choices open visibly different story worlds',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = await AppStore.load(adultPinKdf: fastTestPinKdf);
    final storyIdsBefore = store.stories.map((story) => story.id).toList();
    final attemptIdsBefore =
        store.attempts.map((attempt) => attempt.id).toList();
    final relayIdsBefore = store.relays.map((relay) => relay.id).toList();

    await tester.pumpWidget(testApp(store));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open-theater-preview')));
    await tester.pumpAndSettle();

    final cameHome = find.byKey(const ValueKey('preview-choice-came-home'));
    await tester.ensureVisible(cameHome);
    await tester.tap(cameHome);
    await tester.pumpAndSettle();
    expect(
      find.byKey(
        const ValueKey('preview-outcome-image-home-door-open'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('preview-outcome-image-home-cushion')),
      findsNothing,
    );
    expect(
      find.bySemanticsLabel('孩子說回來了，外婆在打開的家門前迎接他'),
      findsOneWidget,
    );

    final tryOther = find.byKey(const ValueKey('preview-try-other'));
    await tester.ensureVisible(tryOther);
    await tester.tap(tryOther);
    await tester.pumpAndSettle();
    final tired = find.byKey(const ValueKey('preview-choice-a-bit-tired'));
    await tester.ensureVisible(tired);
    await tester.tap(tired);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('preview-outcome-image-home-cushion')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('preview-outcome-image-home-door-open'),
      ),
      findsNothing,
    );
    expect(
      find.bySemanticsLabel('孩子說有一點累，外婆陪他在柔軟的休息場景坐下來'),
      findsOneWidget,
    );
    expect(store.privacyConsent, isFalse);
    expect(store.stories.map((story) => story.id).toList(), storyIdsBefore);
    expect(
      store.attempts.map((attempt) => attempt.id).toList(),
      attemptIdsBefore,
    );
    expect(store.relays.map((relay) => relay.id).toList(), relayIdsBefore);
  });

  testWidgets('three-act preview stays usable at 320px and 200 percent text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = await AppStore.load(adultPinKdf: fastTestPinKdf);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 640),
          textScaler: TextScaler.linear(2),
        ),
        child: testApp(store),
      ),
    );
    await tester.pumpAndSettle();

    final open = find.byKey(const ValueKey('open-theater-preview'));
    await tester.ensureVisible(open);
    await tester.tap(open);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final choice = find.byKey(const ValueKey('preview-choice-came-home'));
    await tester.ensureVisible(choice);
    expect(tester.getSize(choice).height, greaterThanOrEqualTo(48));
    await tester.tap(choice);
    await tester.pumpAndSettle();
    final relay = find.byKey(const ValueKey('preview-to-relay'));
    await tester.ensureVisible(relay);
    await tester.tap(relay);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('preview-relay')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('preview-act-progress-step-3')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    final lifeSeed = find.byKey(const ValueKey('preview-life-seed-friendship'));
    await tester.ensureVisible(lifeSeed);
    expect(tester.getSize(lifeSeed).height, greaterThanOrEqualTo(48));
    await tester.tap(lifeSeed);
    await tester.pumpAndSettle();
    expect(find.textContaining('我想和朋友把事情說開'), findsOneWidget);
    expect(tester.takeException(), isNull);
    final finish = find.byKey(const ValueKey('finish-theater-preview'));
    await tester.ensureVisible(finish);
    expect(finish, findsOneWidget);
    expect(tester.getSize(finish).height, greaterThanOrEqualTo(48));
    expect(tester.takeException(), isNull);
  });

  testWidgets('consent never fabricates family members', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = await AppStore.load(adultPinKdf: fastTestPinKdf);
    await store.acceptPrivacy(adultPin: '2468');

    await tester.pumpWidget(testApp(store));
    await tester.pumpAndSettle();

    expect(find.text('先建立你們家的小圈圈'), findsOneWidget);
    expect(find.textContaining('不會自動假設誰是家人'), findsOneWidget);
    expect(find.textContaining('越南語 bà 可用於'), findsOneWidget);
    final createButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey('create-family-circle')),
    );
    expect(createButton.onPressed, isNull);

    final inclusiveRelationship = find.widgetWithText(ChoiceChip, '其他女性長輩');
    expect(inclusiveRelationship, findsOneWidget);
    await tester.ensureVisible(inclusiveRelationship);
    expect(
      tester.getSize(inclusiveRelationship).height,
      greaterThanOrEqualTo(48),
    );
    await tester.tap(inclusiveRelationship);
    await tester.pump();
    expect(
      tester.widget<ChoiceChip>(inclusiveRelationship).selected,
      isTrue,
    );

    await tester.enterText(
      find.byKey(const ValueKey('family-setup-adult-name')),
      '玲玲阿嬤',
    );
    await tester.enterText(
      find.byKey(const ValueKey('family-setup-child-name')),
      '小米',
    );
    final setupCheckbox = find.byType(Checkbox);
    await tester.ensureVisible(setupCheckbox);
    await tester.tap(setupCheckbox);
    await tester.pump();
    final createCircle = find.byKey(const ValueKey('create-family-circle'));
    await tester.ensureVisible(createCircle);
    await tester.tap(createCircle);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('open-daily-theater')), findsOneWidget);
    final circle = await FamilyCircleStore.load();
    expect(circle.members, hasLength(2));
    expect(
      circle.members.singleWhere((member) => member.isAdult).relationship,
      '其他女性長輩',
    );
    expect(circle.members.map((member) => member.nickname),
        containsAll(<String>['玲玲阿嬤', '小米']));
    expect(
        circle.members.map((member) => member.nickname), isNot(contains('爸爸')));

    await tester.tap(find.byKey(const ValueKey('open-daily-theater')));
    await tester.pumpAndSettle();
    expect(find.text('玲玲阿嬤說'), findsOneWidget);
    expect(find.textContaining('玲玲阿嬤'), findsWidgets);
  });

  testWidgets('home is a focused conversation theater, not a mode dashboard', (
    tester,
  ) async {
    final store = await acceptedStore();
    await tester.pumpWidget(testApp(store));
    await tester.pumpAndSettle();

    expect(find.text('今天，外婆在等你接故事'), findsOneWidget);
    expect(find.byKey(const ValueKey('open-daily-theater')), findsOneWidget);
    expect(find.text('約 1 分鐘 · 點場景、聽阿嬤、讓故事改變'), findsOneWidget);
    expect(find.text('你一句、她一句'), findsNothing);
    expect(find.text('故事會改變'), findsNothing);
    expect(find.text('可說也可點圖'), findsNothing);
    expect(find.text('連勝'), findsNothing);
    expect(find.text('看圖配對'), findsNothing);
    expect(find.text('排句'), findsNothing);

    final openTheater = find.byKey(const ValueKey('open-daily-theater'));
    await tester.ensureVisible(openTheater);
    await tester.tap(openTheater);
    await tester.pumpAndSettle();
    expect(find.text('家庭對話劇場'), findsOneWidget);
    expect(find.text('家庭對話劇場'), findsOneWidget);
    expect(find.byKey(const ValueKey('theater-microphone')), findsNothing);
    expect(
      find.textContaining('先點圖裡的一幕'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('prepare-came-home')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('scene-choice-came-home')), findsOneWidget);
  });

  testWidgets('three meaningful choices create one private family story card', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await acceptedStore();
    await tester.pumpWidget(testApp(store));
    await tester.pumpAndSettle();

    final openTheater = find.byKey(const ValueKey('open-daily-theater'));
    await tester.ensureVisible(openTheater);
    await tester.tap(openTheater);
    await tester.pumpAndSettle();
    expect(find.text('家庭對話劇場'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('scene-choice-came-home')),
      findsOneWidget,
    );

    await chooseLine(tester, '我回來了。');
    expect(find.textContaining('門打開了'), findsWidgets);
    await continueStory(tester);

    await chooseLine(tester, '今天很開心。');
    expect(
      find.byKey(const ValueKey('scene-state-home-happy-story')),
      findsOneWidget,
    );
    await continueStory(tester);

    await chooseLine(tester, '好呀！');
    await continueStory(tester);

    expect(find.text('我們把故事演完了！'), findsOneWidget);
    expect(find.byKey(const ValueKey('generated-story-card')), findsOneWidget);
    expect(find.text('我回來了。'), findsOneWidget);
    expect(find.text('今天很開心。'), findsOneWidget);

    await tester.tap(find.text('帶著故事卡回家'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('家人圈'));
    await tester.pumpAndSettle();
    expect(find.text('我們家的故事圈'), findsOneWidget);
    expect(find.text('放學回家'), findsOneWidget);
    expect(find.text('我回來了。'), findsOneWidget);
    expect(find.textContaining('故事已經完整演完'), findsOneWidget);

    await unlockParent(tester);
    expect(find.text('回應孩子的故事卡（1）'), findsOneWidget);
    await tester.tap(find.text('回應孩子的故事卡（1）'));
    await tester.pumpAndSettle();
    expect(find.text('今天先回應一個故事'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('adult-primary-story-response')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('add-family-member')), findsNothing);
    final familyTools = find.byKey(const ValueKey('family-tools-disclosure'));
    await tester.scrollUntilVisible(
      familyTools,
      220,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.drag(
      find.byType(Scrollable).last,
      const Offset(0, -120),
    );
    await tester.pumpAndSettle();
    await tester.tap(familyTools);
    await tester.pumpAndSettle();
    final addFamilyMember = find.byKey(const ValueKey('add-family-member'));
    await tester.scrollUntilVisible(
      addFamilyMember,
      220,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('邀請或加入一位家人'), findsOneWidget);
    expect(find.text('家人已接受：帶入回覆包'), findsOneWidget);
    expect(find.text('完整文字備份與搬移'), findsOneWidget);
    final proud = find.text('以你為榮');
    await tester.scrollUntilVisible(
      proud,
      260,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(proud);
    await tester.pumpAndSettle();
    expect(find.text('外婆'), findsWidgets);
    expect(find.byIcon(Icons.star_rounded), findsWidgets);
  });

  testWidgets('story library offers five episodes instead of four fake modes', (
    tester,
  ) async {
    final store = await acceptedStore();
    await tester.pumpWidget(testApp(store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('選故事'));
    await tester.pumpAndSettle();

    expect(find.text('挑一集來演'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('library-theater-homecoming')),
      500,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    expect(find.text('放學回家'), findsOneWidget);
    expect(find.text('早安！起床囉'), findsOneWidget);
    expect(find.text('一起準備晚餐'), findsOneWidget);
    expect(find.text('陽台澆花'), findsOneWidget);
    expect(find.text('睡前故事'), findsOneWidget);
    expect(find.text('看圖配對'), findsNothing);
    expect(find.text('聽音排序'), findsNothing);
    expect(find.text('影子跟讀'), findsNothing);
  });

  testWidgets('child can hand a school-life story seed to an unlocked adult', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await acceptedStore();
    await tester.pumpWidget(testApp(store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('選故事'));
    await tester.pumpAndSettle();

    final clubSeed = find.byKey(const ValueKey('story-seed-chip-club'));
    await tester.ensureVisible(clubSeed);
    await tester.tap(clubSeed);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('story-seed-intent-club')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('handoff-story-idea-club')),
      findsNothing,
    );
    await tester.tap(
      find.byKey(const ValueKey('story-seed-choice-club-first-club')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('handoff-story-idea-club')),
      findsOneWidget,
    );
    expect(find.text('把「社團」交給家人'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('continue-story-idea-club')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, '四位數家長碼'),
      '2468',
    );
    await tester.tap(find.widgetWithText(FilledButton, '確認'));
    await tester.pumpAndSettle();

    expect(find.text('把「社團」變成四關故事任務'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('relay-child-first-baton')),
      findsOneWidget,
    );
    expect(find.text('我今天第一次參加社團。'), findsOneWidget);
    final source = tester.widget<TextField>(
      find.byKey(const ValueKey('quick-challenge-source')),
    );
    expect(source.controller?.text, contains('社團'));
    expect(source.controller?.text, contains('孩子想和家人分享'));
    expect(store.relays, hasLength(1));
    expect(store.relays.single.stage, FamilyRelayStage.waitingForAdult);
  });

  testWidgets('adult menu has only creation, family response, and privacy', (
    tester,
  ) async {
    final store = await acceptedStore();
    await tester.pumpWidget(testApp(store));
    await tester.pumpAndSettle();
    await unlockParent(tester);

    expect(find.text('用幾行話留一張短句'), findsOneWidget);
    expect(find.text('回應孩子的故事卡'), findsOneWidget);
    expect(find.text('隱私與家庭資料'), findsOneWidget);
    expect(find.text('完整建立一則故事'), findsNothing);
    expect(find.textContaining('串接設定'), findsNothing);

    await tester.tap(find.text('用幾行話留一張短句'));
    await tester.pumpAndSettle();
    expect(find.text('一句話變成孩子任務'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('quick-challenge-source')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('generate-quick-challenge-draft')),
      findsOneWidget,
    );
  });

  testWidgets('privacy deletion clears both stores and returns to consent', (
    tester,
  ) async {
    final store = await acceptedStore();
    final media = _SilentMediaService();
    await tester.pumpWidget(testApp(store, media: media));
    await tester.pumpAndSettle();

    await unlockParent(tester);
    await tester.tap(find.text('隱私與家庭資料'));
    await tester.pumpAndSettle();
    expect(find.text('隱私與資料'), findsOneWidget);
    final erase = find.text('刪除這支裝置上的全部資料');
    await tester.scrollUntilVisible(
      erase,
      240,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(erase);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '全部刪除'));
    await tester.pumpAndSettle();

    expect(find.text('先取得家人的同意'), findsOneWidget);
    expect(store.privacyConsent, isFalse);
    expect(store.stories, isEmpty);
    expect(media.erased, isTrue);
    final circle = await FamilyCircleStore.load();
    expect(circle.members, isEmpty);
    expect(circle.cards, isEmpty);
  });

  testWidgets('invited adult enters with only their own PIN gate', (
    tester,
  ) async {
    final store = await acceptedStore();
    final now = DateTime.utc(2026, 7, 13, 7);
    final storage = MemoryFamilyCircleStorage();
    var circle = await FamilyCircleStore.load(
      storage: storage,
      clock: () => now,
    );
    await circle.bootstrapAdult(
      FamilyMember(
        id: primaryAdultMemberId,
        relationship: '外婆',
        nickname: '外婆',
        isAdult: true,
        avatarEmoji: 'elder-woman',
        roleColorValue: 0xFFFFE5DE,
        createdAt: now,
      ),
    );
    await circle.inviteMember(
      actorMemberId: primaryAdultMemberId,
      member: FamilyMember(
        id: primaryChildMemberId,
        relationship: '孩子',
        nickname: '小玩家',
        isAdult: false,
        avatarEmoji: 'child',
        roleColorValue: 0xFFDDEEFF,
        createdAt: now,
      ),
    );
    await circle.approveMember(
      actorMemberId: primaryAdultMemberId,
      memberId: primaryChildMemberId,
    );
    // This widget test only exercises the identity gate. Crypto derivation,
    // signature verification and real PIN matching are covered by the
    // dedicated invitation store tests, so use a structurally valid local
    // credential here without spending 600,000 KDF rounds in fake async.
    final snapshot = jsonDecode(storage.value!) as Map<String, dynamic>;
    final testSalt = List<int>.filled(16, 1);
    final testVerifier = await fastTestPinKdf('135790', testSalt);
    (snapshot['members'] as List<Object?>).add(
      FamilyMember(
        id: 'grandpa',
        relationship: '外公',
        nickname: '阿公',
        isAdult: true,
        avatarEmoji: 'elder-man',
        roleColorValue: 0xFFDCEDE8,
        createdAt: now,
      )
          .approve(
            approvedByMemberId: primaryAdultMemberId,
            approvedAt: now,
          )
          .toJson(),
    );
    snapshot['memberPinCredentials'] = [
      {
        'memberId': 'grandpa',
        'algorithm': 'pbkdf2-hmac-sha256',
        'iterations': 600000,
        'salt': base64UrlEncode(testSalt),
        'verifier': base64UrlEncode(testVerifier),
        'createdAt': now.toIso8601String(),
      },
    ];
    storage.value = jsonEncode(snapshot);
    circle = await FamilyCircleStore.load(
      storage: storage,
      clock: () => now,
      invitationCrypto: _FastFamilyInvitationCrypto(),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: MainShell(
          store: store,
          familyCircle: circle,
          media: _SilentMediaService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('parent-mode')));
    await tester.pumpAndSettle();
    expect(find.text('四位數家長碼'), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey('continue-as-invited-family')),
    );
    await tester.pumpAndSettle();
    expect(find.text('今天由哪位家人回應？'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('enter-as-grandpa')));
    await tester.pumpAndSettle();

    expect(find.text('請 阿公 本人確認'), findsOneWidget);
    expect(find.byKey(const ValueKey('member-pin-grandpa')), findsOneWidget);
    expect(find.text('四位數家長碼'), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('member-pin-grandpa')),
      '135790',
    );
    await tester.tap(
      find.byKey(const ValueKey('verify-individual-member-pin')),
    );
    await tester.pumpAndSettle();
    expect(find.text('家人加戲 · 阿公'), findsOneWidget);
    expect(find.text('今天先回應一個故事'), findsOneWidget);
    expect(find.byKey(const ValueKey('add-family-member')), findsNothing);
  });
}

class _FastFamilyInvitationCrypto extends FamilyInvitationCrypto {
  @override
  Future<bool> verifyPin(
    String pin,
    FamilyMemberPinCredential credential,
  ) async =>
      pin == '135790';
}

class _SilentMediaService extends LocalMediaService {
  bool erased = false;
  final List<String> played = [];

  @override
  Future<void> speakText(
    String text, {
    String languageTag = 'vi-VN',
    double rate = LocalMediaService.normalSpeechRate,
  }) async {}

  @override
  Future<void> playLocal(
    String path, {
    double speed = 1,
    Duration? start,
    Duration? end,
  }) async {
    played.add(path);
  }

  @override
  Future<void> stopPlayback() async {}

  @override
  Future<void> eraseAllMedia() async {
    erased = true;
  }

  @override
  Future<void> dispose() async {}
}
