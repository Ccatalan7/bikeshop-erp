import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/services/user_management_service.dart';
import '../../hr/services/hr_service.dart';
import '../../hr/models/hr_models.dart';
import '../providers/chat_provider.dart';

class NewChatDialog extends StatefulWidget {
  const NewChatDialog({super.key});

  @override
  State<NewChatDialog> createState() => _NewChatDialogState();
}

class _NewChatDialogState extends State<NewChatDialog> {
  // Combined list items
  List<ChatCandidate> _candidates = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadCandidates();
  }

  Future<void> _loadCandidates() async {
    try {
      final currentUserId = Supabase.instance.client.auth.currentUser?.id;

      // Fetch both users and employees in parallel
      final results = await Future.wait([
        context.read<UserManagementService>().getTenantUsers(),
        context.read<HRService>().getEmployees(forceRefresh: true),
      ]);

      final users = results[0] as List<Map<String, dynamic>>;
      final employees = results[1] as List<Employee>;

      if (!mounted) return;

      final candidates = <ChatCandidate>[];
      final userIds = <String>{};

      // 1. Add all Chats-enabled Users (exclude self)
      for (final user in users) {
        final uid = user['id'] as String;
        if (uid == currentUserId) continue;

        userIds.add(uid);
        candidates.add(ChatCandidate(
          id: uid, // Use User ID for chat
          displayName: _getUserDisplayName(user),
          subtitle: _getUserSubtitle(user),
          initials: _getUserInitials(user),
          isActive: user['is_active'] as bool? ?? true,
          canChat: user['is_active'] as bool? ?? true,
          type: CandidateType.user,
        ));
      }

      // 2. Add Employees who don't have a linked user content in the list yet
      for (final emp in employees) {
        // If employee is linked to a user we already added, skip
        if (emp.userId != null && userIds.contains(emp.userId)) continue;

        // Otherwise, add as non-chattable employee
        candidates.add(ChatCandidate(
          id: emp.id!, // Use Employee ID (not used for chat)
          displayName: '${emp.firstName} ${emp.lastName}',
          subtitle: 'Trabajador sin cuenta activa',
          initials: emp.firstName.isNotEmpty ? emp.firstName[0] : '?',
          isActive: emp.status == EmployeeStatus.active,
          canChat: false,
          type: CandidateType.employee,
          errorMessage: 'Requiere cuenta de usuario',
        ));
      }

      setState(() {
        _candidates = candidates;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        debugPrint('Error loading chat candidates: $e');
      }
    }
  }

  String _getUserDisplayName(Map<String, dynamic> user) {
    final name = user['employee_name'] as String?;
    if (name != null && name.isNotEmpty) return name;
    final email = user['email'] as String? ?? '';
    return email.split('@').first;
  }

  String _getUserSubtitle(Map<String, dynamic> user) {
    final email = user['email'] as String? ?? 'Sin email';
    final role = user['role'] as String? ?? 'Usuario';
    return '$role • $email';
  }

  String _getUserInitials(Map<String, dynamic> user) {
    final name = user['employee_name'] as String?;
    if (name != null && name.isNotEmpty) return name[0];
    final email = user['email'] as String? ?? '';
    return email.isNotEmpty ? email[0].toUpperCase() : '?';
  }

  void _createChat(String userId) async {
    try {
      Navigator.of(context).pop();
      await context.read<ChatProvider>().createInternalChat(userId);
    } catch (e) {
      // Handle error
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _searchQuery.isEmpty
        ? _candidates
        : _candidates
            .where((c) =>
                c.displayName
                    .toLowerCase()
                    .contains(_searchQuery.toLowerCase()) ||
                c.subtitle.toLowerCase().contains(_searchQuery.toLowerCase()))
            .toList();

    return Dialog(
      child: Container(
        width: 400,
        constraints: const BoxConstraints(maxHeight: 600),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.chat_bubble_outline),
                const SizedBox(width: 12),
                const Text(
                  'Nuevo Chat',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              decoration: const InputDecoration(
                hintText: 'Buscar usuario o trabajador...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : filtered.isEmpty
                      ? const Center(child: Text('No se encontraron usuarios'))
                      : ListView.separated(
                          itemCount: filtered.length,
                          separatorBuilder: (context, index) =>
                              const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final candidate = filtered[index];

                            return ListTile(
                              enabled: candidate.canChat,
                              leading: CircleAvatar(
                                backgroundColor: candidate.isActive
                                    ? Colors.blue[100]
                                    : Colors.grey[300],
                                child: Text(
                                  candidate.initials,
                                  style: TextStyle(
                                      color: candidate.isActive
                                          ? Colors.blue[800]
                                          : Colors.grey[600]),
                                ),
                              ),
                              title: Text(candidate.displayName),
                              subtitle: Text(
                                candidate.subtitle,
                                style: const TextStyle(fontSize: 12),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: candidate.canChat
                                  ? null
                                  : Icon(Icons.person_off_outlined,
                                      size: 16, color: Colors.grey[400]),
                              onTap: candidate.canChat
                                  ? () => _createChat(candidate.id)
                                  : null,
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

enum CandidateType { user, employee }

class ChatCandidate {
  final String id;
  final String displayName;
  final String subtitle;
  final String initials;
  final bool isActive;
  final bool canChat;
  final CandidateType type;
  final String? errorMessage;

  ChatCandidate({
    required this.id,
    required this.displayName,
    required this.subtitle,
    required this.initials,
    required this.isActive,
    required this.canChat,
    required this.type,
    this.errorMessage,
  });
}
