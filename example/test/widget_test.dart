import 'package:flutter_test/flutter_test.dart';
import 'package:luxand_liveness_example/main.dart';

void main() {
  testWidgets('home screen shows primary actions', (WidgetTester tester) async {
    await tester.pumpWidget(const LuxandLivenessExampleApp());

    expect(find.text('Luxand Liveness Example'), findsOneWidget);
    expect(find.text('Camera only (plugin)'), findsOneWidget);
    expect(find.text('Full verify (plugin + Luxand Cloud)'), findsOneWidget);
  });
}
