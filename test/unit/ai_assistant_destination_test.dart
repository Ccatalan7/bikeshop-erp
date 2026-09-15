import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/ai_assistant/models/ai_assistant_destination.dart';
import 'package:vinabike_erp/shared/services/right_toolbar_service.dart';

void main() {
  group('AIAssistantDestination registry', () {
    test('the aggregate registry remains free of record identifiers', () {
      // Bare destinations stay aggregate. Exact record navigation lives in a
      // separate closed registry and never turns a model-authored string into
      // a route.
      for (final route
          in AIAssistantDestinationResolver.registeredWorkspaceRoutes) {
        expect(route, startsWith('/'));
        expect(
          route.endsWith('/edit'),
          isFalse,
          reason: '$route opens an editor',
        );
        expect(
          route.contains(':') || route.contains(r'$'),
          isFalse,
          reason: '$route interpolates an identifier',
        );
        expect(
          RegExp(r'/[0-9a-fA-F-]{8,}').hasMatch(route),
          isFalse,
          reason: '$route looks like it embeds a record id',
        );
      }
    });

    test('the eight card surfaces plus Tareas are the whole reachable set', () {
      expect(
        AIAssistantDestinationResolver.registeredWorkspaceRoutes,
        <String>{
          '/clientes',
          '/purchases/suppliers',
          '/taller/pegas',
          '/sales/invoices',
          '/purchases',
          '/inventory/products',
          '/accounting/expenses',
          '/chat',
        },
      );
      expect(
        AIAssistantDestinationResolver.registeredToolbarTools,
        <ToolbarTool>{ToolbarTool.tasks},
      );
    });

    test('every destination has an effect and names its surface', () {
      for (final destination in AIAssistantDestination.values) {
        expect(
          destination.isRegistered,
          isTrue,
          reason: '$destination has no registered effect',
        );
        expect(destination.ctaLabel, startsWith('Abrir '));
        expect(
            destination.ctaLabel.trim().length, greaterThan('Abrir '.length));
      }
    });

    test('a workspace destination navigates and never opens a tool', () {
      final routes = <String>[];
      final tools = <ToolbarTool>[];
      final resolver = AIAssistantDestinationResolver(
        navigateWorkspace: routes.add,
        openToolbarTool: tools.add,
      );

      expect(
        resolver.dispatch(AIAssistantDestination.inventoryProducts),
        isTrue,
      );
      expect(routes, <String>['/inventory/products']);
      expect(tools, isEmpty);
    });

    test('Tareas opens the toolbar tool and never navigates', () {
      // Tareas is a right-toolbar panel, not a route. Modelling it as a route
      // string would dispatch nothing at all and the click would look broken.
      final routes = <String>[];
      final tools = <ToolbarTool>[];
      final resolver = AIAssistantDestinationResolver(
        navigateWorkspace: routes.add,
        openToolbarTool: tools.add,
      );

      expect(resolver.dispatch(AIAssistantDestination.tasks), isTrue);
      expect(tools, <ToolbarTool>[ToolbarTool.tasks]);
      expect(routes, isEmpty);
    });

    test('dispatch produces exactly one effect per destination', () {
      for (final destination in AIAssistantDestination.values) {
        final routes = <String>[];
        final tools = <ToolbarTool>[];
        final resolver = AIAssistantDestinationResolver(
          navigateWorkspace: routes.add,
          openToolbarTool: tools.add,
        );

        expect(resolver.dispatch(destination), isTrue);
        expect(
          routes.length + tools.length,
          1,
          reason: '$destination produced ${routes.length + tools.length} '
              'effects',
        );
      }
    });

    test('verified entity references derive only canonical detail routes', () {
      const ids = <AIAssistantEntityKind, String>{
        AIAssistantEntityKind.workshopJob:
            '11111111-1111-4111-8111-111111111111',
        AIAssistantEntityKind.customer: '22222222-2222-4222-8222-222222222222',
        AIAssistantEntityKind.salesInvoice:
            '33333333-3333-4333-8333-333333333333',
        AIAssistantEntityKind.supplier: '44444444-4444-4444-8444-444444444444',
        AIAssistantEntityKind.purchaseInvoice:
            '55555555-5555-4555-8555-555555555555',
        AIAssistantEntityKind.expense: '66666666-6666-4666-8666-666666666666',
        AIAssistantEntityKind.conversation:
            '77777777-7777-4777-8777-777777777777',
      };
      const expectedRoutes = <AIAssistantEntityKind, String>{
        AIAssistantEntityKind.workshopJob:
            '/taller/pegas/11111111-1111-4111-8111-111111111111',
        AIAssistantEntityKind.customer:
            '/clientes/22222222-2222-4222-8222-222222222222',
        AIAssistantEntityKind.salesInvoice:
            '/sales/invoices/33333333-3333-4333-8333-333333333333',
        AIAssistantEntityKind.supplier:
            '/purchases/suppliers/44444444-4444-4444-8444-444444444444',
        AIAssistantEntityKind.purchaseInvoice:
            '/purchases/55555555-5555-4555-8555-555555555555',
        AIAssistantEntityKind.expense:
            '/accounting/expenses/66666666-6666-4666-8666-666666666666',
        AIAssistantEntityKind.conversation:
            '/chat?conversation=77777777-7777-4777-8777-777777777777',
      };

      for (final entry in ids.entries) {
        final routes = <String>[];
        final tools = <ToolbarTool>[];
        final ref = AIAssistantEntityRef.verified(
          kind: entry.key,
          id: entry.value.toUpperCase(),
        );
        final resolver = AIAssistantDestinationResolver(
          navigateWorkspace: routes.add,
          openToolbarTool: tools.add,
        );

        expect(
          resolver.dispatch(ref.destination, entityRef: ref),
          isTrue,
        );
        expect(routes, <String>[expectedRoutes[entry.key]!]);
        expect(tools, isEmpty);
      }
    });

    test('a product reference preserves the safe aggregate fallback', () {
      final routes = <String>[];
      final resolver = AIAssistantDestinationResolver(
        navigateWorkspace: routes.add,
        openToolbarTool: (_) => fail('must not open a toolbar tool'),
      );
      final ref = AIAssistantEntityRef.verified(
        kind: AIAssistantEntityKind.product,
        id: '66666666-6666-4666-8666-666666666666',
      );

      expect(
        resolver.dispatch(
          AIAssistantDestination.inventoryProducts,
          entityRef: ref,
        ),
        isTrue,
      );
      expect(routes, <String>['/inventory/products']);
      expect(ref.detailWorkspaceRoute, isNull);
    });

    test('mismatched references fail closed without aggregate fallback', () {
      final routes = <String>[];
      final tools = <ToolbarTool>[];
      final resolver = AIAssistantDestinationResolver(
        navigateWorkspace: routes.add,
        openToolbarTool: tools.add,
      );
      final ref = AIAssistantEntityRef.verified(
        kind: AIAssistantEntityKind.customer,
        id: '77777777-7777-4777-8777-777777777777',
      );

      expect(
        resolver.dispatch(
          AIAssistantDestination.workshopJobs,
          entityRef: ref,
        ),
        isFalse,
      );
      expect(routes, isEmpty);
      expect(tools, isEmpty);
    });

    test('non-UUID entity identifiers cannot enter the card contract', () {
      expect(
        () => AIAssistantEntityRef.verified(
          kind: AIAssistantEntityKind.customer,
          id: '../../admin',
        ),
        throwsArgumentError,
      );
    });
  });
}
