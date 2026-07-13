import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometongue_tags/core/app_theme.dart';
import 'package:hometongue_tags/models/family_circle.dart';
import 'package:hometongue_tags/models/family_invitation.dart';
import 'package:hometongue_tags/widgets/family_invitation_acceptance.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('invited adult personally creates a manual acceptance receipt',
      (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            SystemChannels.platform, (call) async => null);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.utc(2026, 7, 13, 8);
    final invitation = FamilyInvitationPackage(
      invitationId: 'invite-grandpa',
      circleId: 'circle-home',
      circleDisplayName: '我們家',
      invitedAdult: FamilyMember(
        id: 'grandpa',
        relationship: '外公',
        nickname: '阿公',
        isAdult: true,
        avatarEmoji: 'elder-man',
        roleColorValue: 0xFFDCEDE8,
        createdAt: now,
      ),
      issuedAt: now,
      expiresAt: now.add(const Duration(hours: 24)),
      publicKeyBase64: 'public-key-for-widget-test',
      tokenBase64: 'private-token-for-widget-test',
    ).encode();
    String? acceptedSource;
    String? acceptedPin;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () => showAcceptFamilyInvitationFlow(
                  context,
                  acceptInvitation: (source, {required pin}) async {
                    acceptedSource = source;
                    acceptedPin = pin;
                    return 'signed-acceptance-receipt';
                  },
                ),
                child: const Text('接受邀請'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('接受邀請'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('received-invitation-package')),
      invitation,
    );
    await tester.pumpAndSettle();

    expect(find.text('我們家 邀請你以「阿公」加入'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('invited-adult-pin')),
      '135790',
    );
    await tester.enterText(
      find.byKey(const ValueKey('confirm-invited-adult-pin')),
      '135790',
    );
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    final accept =
        find.byKey(const ValueKey('accept-invitation-create-receipt'));
    await tester.ensureVisible(accept);
    await tester.tap(accept);
    await tester.pumpAndSettle();

    expect(acceptedSource, invitation);
    expect(acceptedPin, '135790');
    expect(find.text('你已接受邀請'), findsOneWidget);
    expect(find.textContaining('沒有假裝即時同步'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('invitation-receipt-output')),
      findsOneWidget,
    );
    expect(find.text('signed-acceptance-receipt'), findsOneWidget);
    expect(find.text('完成'), findsNothing);
    expect(find.text('複製回覆包並完成'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('copy-invitation-receipt')),
    );
    await tester.pumpAndSettle();
    expect(find.text('你已接受邀請'), findsNothing);
  });
}
