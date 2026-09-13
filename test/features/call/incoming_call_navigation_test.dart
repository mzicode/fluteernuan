import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:customer/features/call/pages/incoming_call_page.dart';

void main() {
  testWidgets('duplicate rejection callbacks only close the incoming route',
      (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    late BuildContext incomingContext;
    final closer = IncomingCallRouteCloser();

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: Text('message list')),
      ),
    );

    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/chat'),
        builder: (_) => const Scaffold(body: Text('chat page')),
      ),
    );
    await tester.pumpAndSettle();

    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/incoming-call'),
        builder: (context) {
          incomingContext = context;
          return const Scaffold(body: Text('incoming call'));
        },
      ),
    );
    await tester.pumpAndSettle();

    // rejectCall() changing state and its awaiting button callback both ask to
    // close the same route in one frame.
    expect(Navigator.of(incomingContext).canPop(), isTrue);
    closer.close(incomingContext);
    closer.close(incomingContext);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('incoming call'), findsNothing);
    expect(find.text('chat page'), findsOneWidget);
    expect(find.text('message list'), findsNothing);
  });
}
