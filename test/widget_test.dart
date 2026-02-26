import 'package:flutter_test/flutter_test.dart';
import 'package:p2p_classroom/providers/profile_provider.dart';
import 'package:p2p_classroom/main.dart';

void main() {
  testWidgets('App launches successfully', (WidgetTester tester) async {
    await tester.pumpWidget(P2PClassroomApp(profileProvider: ProfileProvider()));
    expect(find.text('P2P Classroom'), findsOneWidget);
  });
}
