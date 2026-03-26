import 'package:flutter_test/flutter_test.dart';

import 'package:lingfer/main.dart';

void main() {
  testWidgets('Home shows import button', (WidgetTester tester) async {
    await tester.pumpWidget(const LingferRoot());

    expect(find.text('我的书架'), findsWidgets);
    expect(find.text('探索'), findsWidgets);
    // Shelf may be empty when no bundled assets exist; UI should still render.
  });
}
