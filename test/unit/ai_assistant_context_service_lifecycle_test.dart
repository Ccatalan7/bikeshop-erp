import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vinabike_erp/modules/ai_assistant/services/ai_assistant_context_service.dart';

class _ContextPublisher extends StatefulWidget {
  const _ContextPublisher({
    required this.service,
    required this.owner,
  });

  final AIAssistantContextService service;
  final Object owner;

  @override
  State<_ContextPublisher> createState() => _ContextPublisherState();
}

class _ContextPublisherState extends State<_ContextPublisher> {
  @override
  void dispose() {
    widget.service.clearVisibleJobsContextAfterFrame(owner: widget.owner);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    context.watch<AIAssistantContextService>();
    return const SizedBox();
  }
}

void main() {
  testWidgets(
    'page disposal clears context after tree finalization without provider errors',
    (tester) async {
      final service = AIAssistantContextService();
      addTearDown(service.dispose);
      final owner = Object();
      service.setVisibleJobsContext(
        owner: owner,
        jobs: const [],
        scopeLabel: 'trabajos activos',
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<AIAssistantContextService>.value(
          value: service,
          child: MaterialApp(
            home: _ContextPublisher(service: service, owner: owner),
          ),
        ),
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<AIAssistantContextService>.value(
          value: service,
          child: const MaterialApp(home: SizedBox()),
        ),
      );
      expect(tester.takeException(), isNull);

      await tester.pump();
      expect(service.hasVisibleJobsContext, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('deferred clear cannot erase context from a newer owner',
      (tester) async {
    final service = AIAssistantContextService();
    addTearDown(service.dispose);
    final oldOwner = Object();
    final newOwner = Object();
    service.setVisibleJobsContext(
      owner: oldOwner,
      jobs: const [],
      scopeLabel: 'vista anterior',
    );

    service.clearVisibleJobsContextAfterFrame(owner: oldOwner);
    service.setVisibleJobsContext(
      owner: newOwner,
      jobs: const [],
      scopeLabel: 'vista nueva',
    );
    await tester.pump();

    expect(service.hasVisibleJobsContext, isTrue);
    expect(service.visibleJobsScopeLabel, 'vista nueva');
  });
}
