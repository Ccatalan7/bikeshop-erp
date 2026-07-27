import 'package:flutter/material.dart';

class WorkshopBoardCompactGroup {
  const WorkshopBoardCompactGroup({
    required this.id,
    required this.label,
    required this.color,
    required this.children,
  });

  final String id;
  final String label;
  final Color color;
  final List<Widget> children;
}

/// Parent-owned compact board navigation state.
///
/// Keeping this object above the mode widget lets Jobs restore the exact board
/// column after an inline job round trip or a temporary view change.
class WorkshopBoardCompactSession {
  WorkshopBoardCompactSession({this.selectedGroupId});

  String? selectedGroupId;
}

/// Phone/tablet composition for the workshop status board.
///
/// A desktop kanban depends on simultaneously visible columns. On a compact
/// viewport the same state is exposed through one clearly labelled status
/// selector and a full-width list, preserving density and touch ergonomics
/// without introducing horizontal board scrolling.
class WorkshopBoardCompactView extends StatefulWidget {
  const WorkshopBoardCompactView({
    super.key,
    required this.groups,
    this.emptyLabel = 'No hay trabajos que mostrar',
    this.session,
  });

  final List<WorkshopBoardCompactGroup> groups;
  final String emptyLabel;
  final WorkshopBoardCompactSession? session;

  @override
  State<WorkshopBoardCompactView> createState() =>
      _WorkshopBoardCompactViewState();
}

class _WorkshopBoardCompactViewState extends State<WorkshopBoardCompactView> {
  final WorkshopBoardCompactSession _localSession =
      WorkshopBoardCompactSession();

  WorkshopBoardCompactSession get _session => widget.session ?? _localSession;

  WorkshopBoardCompactGroup? get _selectedGroup {
    if (widget.groups.isEmpty) {
      return null;
    }

    return widget.groups.cast<WorkshopBoardCompactGroup?>().firstWhere(
          (group) => group?.id == _session.selectedGroupId,
          orElse: () => widget.groups.first,
        );
  }

  @override
  void didUpdateWidget(covariant WorkshopBoardCompactView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.groups.every(
      (group) => group.id != _session.selectedGroupId,
    )) {
      _session.selectedGroupId = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedGroup = _selectedGroup;
    if (selectedGroup == null) {
      return Center(
        child: Text(
          widget.emptyLabel,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return Column(
      key: const ValueKey('workshop-board-compact-view'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: DropdownButtonFormField<String>(
            key: const ValueKey('workshop-board-status-selector'),
            initialValue: selectedGroup.id,
            isExpanded: true,
            itemHeight: 56,
            decoration: const InputDecoration(
              labelText: 'Estado del tablero',
              contentPadding: EdgeInsets.symmetric(horizontal: 12),
              constraints: BoxConstraints(minHeight: 56),
              border: OutlineInputBorder(),
            ),
            selectedItemBuilder: (context) => widget.groups
                .map(
                  (group) => _StatusOption(
                    group: group,
                    showCount: true,
                  ),
                )
                .toList(),
            items: widget.groups
                .map(
                  (group) => DropdownMenuItem<String>(
                    value: group.id,
                    child: _StatusOption(
                      group: group,
                      showCount: true,
                    ),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value == null || value == selectedGroup.id) {
                return;
              }
              setState(() => _session.selectedGroupId = value);
            },
          ),
        ),
        Expanded(
          child: selectedGroup.children.isEmpty
              ? Center(
                  child: Text(
                    'Sin trabajos en ${selectedGroup.label}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : ListView.separated(
                  key: PageStorageKey(
                    'workshop-board-group-${selectedGroup.id}',
                  ),
                  padding: EdgeInsets.fromLTRB(
                    12,
                    4,
                    12,
                    MediaQuery.paddingOf(context).bottom + 20,
                  ),
                  itemCount: selectedGroup.children.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) =>
                      selectedGroup.children[index],
                ),
        ),
      ],
    );
  }
}

class _StatusOption extends StatelessWidget {
  const _StatusOption({
    required this.group,
    required this.showCount,
  });

  final WorkshopBoardCompactGroup group;
  final bool showCount;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: group.color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            group.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (showCount) ...[
          const SizedBox(width: 8),
          Text(
            '${group.children.length}',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ],
    );
  }
}
