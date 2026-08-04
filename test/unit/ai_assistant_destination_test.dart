import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/ai_assistant/models/ai_assistant_destination.dart';
import 'package:vinabike_erp/shared/services/right_toolbar_service.dart';

void main() {
  group('AIAssistantDestination registry', () {
    test('every registered workspace route is an aggregate surface', () {
      // The assistant used to deep-link into editors: a card labelled "Abrir
      // trabajo" dropped the operator into the job form, and "Abrir producto"
      // into the product form, on an application that runs against
      // production. No registered route may end in an editor segment or carry
      // a record id.
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

    test('the six card surfaces plus Tareas are the whole reachable set', () {
      expect(
        AIAssistantDestinationResolver.registeredWorkspaceRoutes,
        <String>{
          '/clientes',
          '/purchases/suppliers',
          '/taller/pegas',
          '/sales/invoices',
          '/purchases',
          '/inventory/products',
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
  });
}
