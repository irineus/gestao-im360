import 'package:flutter_test/flutter_test.dart';

/// Os providers assíncronos resolvem em microtasks; o skeleton anima para
/// sempre, então o `pumpAndSettle` só é seguro depois que os dados chegaram.
Future<void> carregar(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 10),
  );
}
