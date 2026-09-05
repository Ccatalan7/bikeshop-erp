import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';

/// The row owns selection; its bubble owns reactions and horizontal reply.
/// Disabling text selection here also excludes the app's outer SelectionArea.
class ChatMessageRow extends StatelessWidget {
  const ChatMessageRow({
    super.key,
    required this.selected,
    required this.selecting,
    required this.onSelect,
    required this.child,
  });

  final bool selected;
  final bool selecting;
  final VoidCallback? onSelect;
  final Widget child;

  @override
  Widget build(BuildContext context) => SelectionContainer.disabled(
        child: Semantics(
          selected: selected,
          customSemanticsActions: {
            if (onSelect != null)
              CustomSemanticsAction(
                  label: selected
                      ? 'Deseleccionar mensaje'
                      : 'Seleccionar mensaje'): onSelect!,
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onLongPress: onSelect,
            onTap: selecting ? onSelect : null,
            child: ColoredBox(
              color: selected
                  ? Theme.of(context).colorScheme.secondaryContainer
                  : Colors.transparent,
              // Attachment/link taps must select while the toolbar is open.
              child: IgnorePointer(ignoring: selecting, child: child),
            ),
          ),
        ),
      );
}

class ChatMessageBubble extends StatefulWidget {
  const ChatMessageBubble({
    super.key,
    required this.child,
    this.onReact,
    this.onReply,
    this.onContextMenu,
    this.selecting = false,
  });

  final Widget child;
  final VoidCallback? onReact;
  final VoidCallback? onReply;
  final VoidCallback? onContextMenu;
  final bool selecting;

  @override
  State<ChatMessageBubble> createState() => _ChatMessageBubbleState();
}

class _ChatMessageBubbleState extends State<ChatMessageBubble> {
  // A deliberate horizontal movement, independent of density/bubble width.
  static const _replyDistance = kTouchSlop * 4;
  double _distance = 0;
  bool _dragging = false;
  bool _armed = false;

  @override
  void didUpdateWidget(ChatMessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selecting || widget.onReply == null) {
      _distance = 0;
      _dragging = false;
      _armed = false;
    }
  }

  void _reset({bool reply = false}) {
    final shouldReply = reply && _armed && !widget.selecting;
    setState(() {
      _distance = 0;
      _dragging = false;
      _armed = false;
    });
    if (shouldReply) widget.onReply?.call();
  }

  @override
  Widget build(BuildContext context) => Semantics(
        customSemanticsActions: {
          if (widget.onReact != null)
            const CustomSemanticsAction(label: 'Reaccionar al mensaje'):
                widget.onReact!,
          if (widget.onReply != null)
            const CustomSemanticsAction(label: 'Responder al mensaje'):
                widget.onReply!,
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPress: widget.onReact,
          onSecondaryTap: widget.onContextMenu,
          onHorizontalDragStart: widget.onReply == null || widget.selecting
              ? null
              : (_) => _dragging = true,
          onHorizontalDragUpdate: widget.onReply == null || widget.selecting
              ? null
              : (details) {
                  if (!_dragging) return;
                  final distance = (_distance + details.delta.dx)
                      .clamp(0.0, _replyDistance + kTouchSlop);
                  final armed = distance >= _replyDistance;
                  if (armed && !_armed) HapticFeedback.selectionClick();
                  setState(() {
                    _distance = distance;
                    _armed = armed;
                  });
                },
          onHorizontalDragEnd:
              widget.onReply == null ? null : (_) => _reset(reply: true),
          onHorizontalDragCancel: widget.onReply == null ? null : _reset,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.centerLeft,
            children: [
              if (_distance > 0)
                ExcludeSemantics(
                  child: Opacity(
                    opacity: (_distance / _replyDistance).clamp(0, 1),
                    child: Icon(Icons.reply,
                        color: Theme.of(context).colorScheme.primary),
                  ),
                ),
              AnimatedContainer(
                duration: _dragging ? Duration.zero : kThemeAnimationDuration,
                transform: Matrix4.translationValues(_distance, 0, 0),
                child: widget.child,
              ),
            ],
          ),
        ),
      );
}
