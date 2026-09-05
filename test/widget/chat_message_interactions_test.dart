import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/messaging/widgets/chat_message_interactions.dart';

void main() {
  testWidgets(
      'bubble hold reacts, row hold selects and selected file tap selects',
      (tester) async {
    var reactions = 0;
    var selections = 0;
    var opens = 0;
    var selecting = false;
    late StateSetter rebuild;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: StatefulBuilder(
      builder: (context, setState) {
        rebuild = setState;
        return SelectionArea(
          child: ChatMessageRow(
            selected: selecting,
            selecting: selecting,
            onSelect: () => selections++,
            child: Row(children: [
              ChatMessageBubble(
                selecting: selecting,
                onReact: () => reactions++,
                child: InkWell(
                  onTap: () => opens++,
                  child: const SizedBox(
                      width: 200, height: 100, child: Text('Adjunto')),
                ),
              ),
              const Expanded(child: SizedBox(height: 100)),
            ]),
          ),
        );
      },
    ))));
    await tester.longPress(find.text('Adjunto'));
    expect(reactions, 1);
    expect(selections, 0);
    await tester.longPressAt(
        Offset(tester.getSize(find.byType(ChatMessageRow)).width - 10, 40));
    expect(selections, 1);
    rebuild(() => selecting = true);
    await tester.pump();
    await tester.tapAt(const Offset(100, 40));
    expect(selections, 2);
    expect(opens, 0);
  });

  testWidgets(
      'only deliberate right swipe replies; scroll, left and cancel do not',
      (tester) async {
    var replies = 0;
    final scroll = ScrollController();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ListView(
      controller: scroll,
      children: [
        ChatMessageBubble(
          onReply: () => replies++,
          child: const SizedBox(height: 200, child: Text('Mensaje')),
        ),
        const SizedBox(height: 1600),
      ],
    ))));
    final bubble = find.byType(ChatMessageBubble);
    await tester.drag(bubble, const Offset(-110, 0));
    expect(replies, 0);
    await tester.drag(bubble, const Offset(35, 0));
    expect(replies, 0);
    final gesture = await tester.startGesture(tester.getCenter(bubble));
    await gesture.moveBy(const Offset(110, 0));
    await gesture.cancel();
    expect(replies, 0);
    await tester.drag(bubble, const Offset(110, 0));
    expect(replies, 1);
    await tester.drag(bubble, const Offset(0, -110));
    await tester.pumpAndSettle();
    expect(replies, 1);
    expect(scroll.offset, greaterThan(0));
  });

  testWidgets('changing message identity cancels an in-progress reply gesture',
      (tester) async {
    var replies = 0;
    var messageId = 'a';
    late StateSetter rebuild;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: StatefulBuilder(
      builder: (context, setState) {
        rebuild = setState;
        return ChatMessageBubble(
          key: ValueKey(messageId),
          onReply: () => replies++,
          child:
              const SizedBox(width: 240, height: 100, child: Text('Mensaje')),
        );
      },
    ))));
    final gesture = await tester.startGesture(const Offset(40, 40));
    await gesture.moveBy(const Offset(110, 0));
    rebuild(() => messageId = 'b');
    await tester.pump();
    await gesture.up();
    expect(replies, 0);
  });
}
