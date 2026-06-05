import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api.dart';
import '../services/api_client.dart' show defaultBaseUrl;
import 'admin_kyc_review_page.dart';

class AdminPendingKYCPage extends StatefulWidget {
  const AdminPendingKYCPage({super.key});

  @override
  State<AdminPendingKYCPage> createState() => _AdminPendingKYCPageState();
}

class _AdminPendingKYCPageState extends State<AdminPendingKYCPage> {
  List<Map<String, dynamic>> _pendingUsers = <Map<String, dynamic>>[];
  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  Timer? _poller;

  @override
  void initState() {
    super.initState();
    _loadPendingKycs();
    _poller = Timer.periodic(const Duration(seconds: 8), (_) {
      _loadPendingKycs(silent: true);
    });
  }

  @override
  void dispose() {
    _poller?.cancel();
    super.dispose();
  }

  Future<void> _loadPendingKycs({bool silent = false}) async {
    if (_refreshing) return;
    if (!mounted) return;

    setState(() {
      _refreshing = true;
      if (!silent && _pendingUsers.isEmpty) {
        _loading = true;
      }
    });

    try {
      final rows = await api.getPendingKycs();
      if (!mounted) return;
      setState(() {
        _pendingUsers = rows
            .whereType<Map>()
            .map(
              (row) => Map<String, dynamic>.from(row.cast<String, dynamic>()),
            )
            .toList();
        _error = null;
        _loading = false;
        _refreshing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
        _refreshing = false;
      });
    }
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'U';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }

  String? _resolveMediaUrl(dynamic raw) {
    final value = (raw ?? '').toString().trim();
    if (value.isEmpty) return null;
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    if (value.startsWith('/')) return '$defaultBaseUrl$value';
    return '$defaultBaseUrl/$value';
  }

  Future<void> _openReview(Map<String, dynamic> user) async {
    final userId = _toInt(user['id']);
    final userName = (user['name'] ?? 'User').toString();
    if (userId <= 0) return;

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AdminKYCReviewPage(userId: userId, userName: userName),
      ),
    );

    if (result == true && mounted) {
      await _loadPendingKycs(silent: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        title: const Text('Pending KYC Approvals'),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _refreshing
                ? null
                : () => _loadPendingKycs(silent: true),
            icon: _refreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadPendingKycs(silent: true),
        child: Builder(
          builder: (context) {
            if (_loading) {
              return const Center(child: CircularProgressIndicator());
            }

            if (_error != null && _pendingUsers.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 140),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        children: [
                          const Icon(Icons.error_outline, color: Colors.red),
                          const SizedBox(height: 10),
                          Text(
                            'Failed to load pending KYC users\n$_error',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: _refreshing
                                ? null
                                : () => _loadPendingKycs(),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            }

            if (_pendingUsers.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 180),
                  Center(child: Text('No pending KYC submissions.')),
                ],
              );
            }

            return ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: _pendingUsers.length,
              itemBuilder: (context, index) {
                final user = _pendingUsers[index];
                final name = (user['name'] ?? 'User').toString();
                final email = (user['email'] ?? '-').toString();
                final avatarUrl = _resolveMediaUrl(user['avatar_url']);
                final docType = (user['kyc_doc_type'] ?? 'Unknown').toString();

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: ListTile(
                    isThreeLine: true,
                    onTap: () => _openReview(user),
                    leading: CircleAvatar(
                      backgroundColor: const Color(0xFFE6F4F2),
                      backgroundImage: avatarUrl == null
                          ? null
                          : NetworkImage(avatarUrl),
                      child: avatarUrl == null
                          ? Text(
                              _initials(name),
                              style: const TextStyle(
                                color: Color(0xFF0D9488),
                                fontWeight: FontWeight.w700,
                              ),
                            )
                          : null,
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const _PendingKycChip(),
                      ],
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            email,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Doc: $docType',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _PendingKycChip extends StatelessWidget {
  const _PendingKycChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFE6F4F2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Text(
        'Pending',
        style: TextStyle(
          fontSize: 11,
          color: Color(0xFF0F766E),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
