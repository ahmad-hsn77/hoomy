import 'package:flutter_test/flutter_test.dart';
import 'package:hoomy/app/hoomy_app.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Hoomy renders auth screen', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const HoomyApp());
    await tester.pumpAndSettle();

    expect(find.text('Hoomy'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
  });
}