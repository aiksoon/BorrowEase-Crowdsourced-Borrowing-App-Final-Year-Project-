import 'package:flutter/material.dart';

import '../services/api.dart';
import '../services/api_client.dart' show defaultBaseUrl;

class AdminTotalUsersPage extends StatefulWidget {
  const AdminTotalUsersPage({super.key});

  @override
  State<AdminTotalUsersPage> createState() => _AdminTotalUsersPageState();
}

class _AdminTotalUsersPageState extends State<AdminTotalUsersPage> {
  static const Color _ecoTeal = Color(0xFF0D9488);

  final TextEditingController _searchController = TextEditingController();
  final Set<int> _updatingUserIds = <int>{};

  List<Map<String, dynamic>> _users = <Map<String, dynamic>>[];
  String _searchQuery = '';
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final rows = await api.getAdminUsers();
      if (!mounted) return;

      final users = rows
          .whereType<Map<String, dynamic>>()
          .map((u) => Map<String, dynamic>.from(u))
          .toList();

      setState(() {
        _users = users;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  List<Map<String, dynamic>> get _filteredUsers {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return _users;

    return _users.where((user) {
      final name = (user['name'] ?? '').toString().toLowerCase();
      final email = (user['email'] ?? '').toString().toLowerCase();
      return name.contains(q) || email.contains(q);
    }).toList();
  }

  bool _isBanned(Map<String, dynamic> user) {
    final raw = user['is_banned'];
    if (raw is bool) return raw;
    if (raw is num) return raw.toInt() == 1;
    if (raw is String) {
      final text = raw.trim().toLowerCase();
      return text == '1' || text == 'true' || text == 'yes';
    }
    return false;
  }

  Future<void> _toggleBan(Map<String, dynamic> user, bool activeValue) async {
    final userId = (user['id'] as num).toInt();
    final userName = (user['name'] ?? 'Unknown').toString();
    final nextBanned = !activeValue;

    if (_updatingUserIds.contains(userId)) return;

    setState(() {
      _updatingUserIds.add(userId);
      user['is_banned'] = nextBanned;
    });

    try {
      await api.setAdminUserBan(userId: userId, isBanned: nextBanned);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'User $userName has been ${nextBanned ? 'banned' : 'unbanned'}',
          ),
          backgroundColor: nextBanned ? Colors.red[700] : Colors.green[700],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        user['is_banned'] = !nextBanned;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update status for $userName'),
          backgroundColor: Colors.red[700],
        ),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _updatingUserIds.remove(userId);
      });
    }
  }

  String _initialsFromName(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();

    if (parts.isEmpty) return 'U';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  String? _resolveMediaUrl(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final value = raw.trim();
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    final cleanValue = value.startsWith('/') ? value.substring(1) : value;
    final baseUrl = defaultBaseUrl.endsWith('/')
        ? defaultBaseUrl.substring(0, defaultBaseUrl.length - 1)
        : defaultBaseUrl;
    return '$baseUrl/$cleanValue';
  }

  Widget _buildAvatar(Map<String, dynamic> user) {
    final avatarUrl = _resolveMediaUrl(user['avatar_url']?.toString());
    final name = (user['name'] ?? 'User').toString();

    if (avatarUrl != null) {
      return CircleAvatar(
        radius: 22,
        backgroundColor: _ecoTeal.withValues(alpha: 0.15),
        backgroundImage: NetworkImage(avatarUrl),
      );
    }

    return CircleAvatar(
      radius: 22,
      backgroundColor: _ecoTeal.withValues(alpha: 0.18),
      child: Text(
        _initialsFromName(name),
        style: const TextStyle(fontWeight: FontWeight.bold, color: _ecoTeal),
      ),
    );
  }

  Widget _buildStatusBadge(bool isBanned) {
    final color = isBanned ? Colors.red : Colors.green;
    final text = isBanned ? 'Banned' : 'Active';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color.shade700,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final users = _filteredUsers;

    return Scaffold(
      backgroundColor: const Color(0xFFF4FBFA),
      appBar: AppBar(
        backgroundColor: _ecoTeal,
        foregroundColor: Colors.white,
        title: const Text('User Management'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
              decoration: InputDecoration(
                hintText: 'Search by username or email',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              color: _ecoTeal,
              onRefresh: _loadUsers,
              child: Builder(
                builder: (context) {
                  if (_loading) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (_error != null) {
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        const SizedBox(height: 120),
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Column(
                              children: [
                                const Icon(
                                  Icons.error_outline,
                                  color: Colors.red,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Failed to load users\n$_error',
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 12),
                                ElevatedButton(
                                  onPressed: _loadUsers,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _ecoTeal,
                                    foregroundColor: Colors.white,
                                  ),
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  }

                  if (users.isEmpty) {
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 120),
                        Center(child: Text('No users found')),
                      ],
                    );
                  }

                  return ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                    itemCount: users.length,
                    itemBuilder: (context, index) {
                      final user = users[index];
                      final isBanned = _isBanned(user);
                      final isUpdating = _updatingUserIds.contains(
                        (user['id'] as num).toInt(),
                      );

                      return Card(
                        color: Colors.white,
                        elevation: 0,
                        margin: const EdgeInsets.symmetric(vertical: 5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: Colors.grey.withValues(alpha: 0.18),
                          ),
                        ),
                        child: ListTile(
                          isThreeLine: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          leading: _buildAvatar(user),
                          title: Text(
                            (user['name'] ?? 'Unknown').toString(),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  (user['email'] ?? '-').toString(),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 6),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: _buildStatusBadge(isBanned),
                                ),
                              ],
                            ),
                          ),
                          trailing: SizedBox(
                            width: 66,
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: Switch(
                                value: !isBanned,
                                activeThumbColor: _ecoTeal,
                                onChanged: isUpdating
                                    ? null
                                    : (value) => _toggleBan(user, value),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
