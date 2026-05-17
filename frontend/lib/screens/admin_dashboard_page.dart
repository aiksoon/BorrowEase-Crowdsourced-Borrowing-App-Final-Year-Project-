import 'package:flutter/material.dart';

import '../services/api.dart';
import 'admin_listings_page.dart';
import 'admin_pending_kyc_page.dart';
import 'admin_reports_page.dart';
import 'admin_total_users_page.dart';
import 'admin_transactions_page.dart';

// ==================== ADMIN DASHBOARD PAGE ====================
class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  Map<String, dynamic> _stats = <String, dynamic>{};
  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  DateTime? _lastUpdated;

  @override
  void initState() {
    super.initState();
    _refreshDashboard();
  }

  Future<Map<String, dynamic>> _loadStats() async {
    return api.getAdminDashboardStats();
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  String _friendlyError(Object error) {
    final text = error.toString();
    if (text.contains('403')) {
      return 'Access denied. Admin permission is required.';
    }
    if (text.contains('401')) {
      return 'Session expired. Please sign in again.';
    }
    return text;
  }

  Future<void> _refreshDashboard({bool silent = false}) async {
    if (_refreshing) return;
    setState(() {
      _refreshing = true;
      if (!silent) {
        _loading = true;
      }
    });

    try {
      final stats = await _loadStats();
      if (!mounted) return;
      setState(() {
        _stats = Map<String, dynamic>.from(stats);
        _error = null;
        _loading = false;
        _refreshing = false;
        _lastUpdated = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _friendlyError(e);
        _loading = false;
        _refreshing = false;
      });
    }
  }

  Future<void> _openAdminPage(
    Widget page, {
    bool refreshOnReturn = false,
  }) async {
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        pageBuilder: (_, __, ___) => page,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        transitionsBuilder: (_, animation, __, child) {
          return child;
        },
      ),
    );

    if (refreshOnReturn && mounted) {
      _refreshDashboard(silent: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.arrow_back),
                  ),
                  const SizedBox(width: 16),
                  const Text(
                    'Admin Dashboard',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: _refreshing
                        ? null
                        : () => _refreshDashboard(silent: true),
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
            ),
            Expanded(
              child: Builder(
                builder: (context) {
                  if (_loading) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (_error != null && _stats.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Failed to load dashboard: $_error'),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: _refreshing
                                ? null
                                : () => _refreshDashboard(),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    );
                  }

                  final stats = _stats;
                  final totalUsers = _toInt(stats['total_users']);
                  final activeListings = _toInt(stats['active_listings']);
                  final pendingKycCount = _toInt(stats['pending_kyc']);
                  final reportsCount = _toInt(stats['reports']);
                  final pendingListings = _toInt(
                    stats['unavailable_listings'] ?? stats['pending_listings'],
                  );
                  final transactions = _toInt(stats['transactions']);

                  return RefreshIndicator(
                    onRefresh: () => _refreshDashboard(silent: true),
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_error != null)
                            Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.red[50],
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'Failed to refresh some data: $_error',
                                style: TextStyle(color: Colors.red[700]),
                              ),
                            ),
                          if (_lastUpdated != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Text(
                                'Updated ${_lastUpdated!.hour.toString().padLeft(2, '0')}:${_lastUpdated!.minute.toString().padLeft(2, '0')}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ),
                          Row(
                            children: [
                              Expanded(
                                child: _buildStatCard(
                                  '$totalUsers',
                                  'Total Users',
                                  Icons.people,
                                  Colors.blue,
                                  onTap: () async {
                                    await _openAdminPage(
                                      const AdminTotalUsersPage(),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildStatCard(
                                  '$activeListings',
                                  'Active Listings',
                                  Icons.inventory_2,
                                  Colors.green,
                                  onTap: () async {
                                    await _openAdminPage(
                                      const AdminActiveListingsPage(),
                                      refreshOnReturn: true,
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _buildStatCard(
                                  '$pendingKycCount',
                                  'Pending KYC',
                                  Icons.verified_user,
                                  const Color(0xFF0D9488),
                                  onTap: () async {
                                    await _openAdminPage(
                                      const AdminPendingKYCPage(),
                                      refreshOnReturn: true,
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildStatCard(
                                  '$reportsCount',
                                  'Reports',
                                  Icons.flag,
                                  Colors.red,
                                  onTap: () async {
                                    await _openAdminPage(
                                      const AdminReportsPage(),
                                      refreshOnReturn: true,
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _buildStatCard(
                                  '$pendingListings',
                                  'Unavailable Listings',
                                  Icons.pending_actions,
                                  Colors.purple,
                                  onTap: () async {
                                    await _openAdminPage(
                                      const AdminUnavailableListingsPage(),
                                      refreshOnReturn: true,
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildStatCard(
                                  '$transactions',
                                  'Transactions',
                                  Icons.swap_horiz,
                                  Colors.teal,
                                  onTap: () async {
                                    await _openAdminPage(
                                      const AdminTransactionsPage(),
                                      refreshOnReturn: true,
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(
    String value,
    String label,
    IconData icon,
    Color color, {
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withValues(alpha: 0.08),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(height: 12),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                label,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
