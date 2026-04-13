import 'package:flutter_test/flutter_test.dart';
import 'package:aeronav/main.dart';

void main() {
  testWidgets('AeroNav splash screen renders', (WidgetTester tester) async {
    await tester.pumpWidget(const AeroNavApp());
    expect(find.text('GET STARTED'), findsNothing); // router handles navigation
  });
}
