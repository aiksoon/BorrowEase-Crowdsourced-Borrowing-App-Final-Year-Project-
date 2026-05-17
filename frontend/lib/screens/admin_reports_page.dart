import 'package:flutter/material.dart';

import '../services/api.dart';
import 'screens.dart';

class AdminReportsPage extends StatefulWidget {
  const AdminReportsPage({super.key});

  @override
  State<AdminReportsPage> createState() => _AdminReportsPageState();
}

class _AdminReportsPageState extends State<AdminReportsPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _reports = <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
      });
    }
    try {
      final rows = await api.getAdminReports();
      if (!mounted) return;
      setState(() {
        _reports = rows.whereType<Map<String, dynamic>>().toList();
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Color _statusBg(String status) {
    switch (status) {
      case 'resolved':
        return const Color(0xFFE8F8EE);
      case 'reviewing':
        return const Color(0xFFEAF4FF);
      case 'rejected':
        return const Color(0xFFFDECEC);
      default:
        return const Color(0xFFFDECEC);
    }
  }

  Color _statusFg(String status) {
    switch (status) {
      case 'resolved':
        return const Color(0xFF1A7F37);
      case 'reviewing':
        return const Color(0xFF1D4ED8);
      case 'rejected':
        return const Color(0xFFB91C1C);
      default:
        return const Color(0xFFB91C1C);
    }
  }

  String _statusText(String status) {
    switch (status) {
      case 'resolved':
        return 'Resolved';
      case 'reviewing':
        return 'Reviewing';
      case 'rejected':
        return 'Rejected';
      default:
        return 'Unresolved';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('Reports'),
        actions: [
          IconButton(
            onPressed: () => _load(silent: true),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Failed to load reports: $_error'))
              : RefreshIndicator(
                  onRefresh: () => _load(silent: true),
                  child: _reports.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 180),
                            Center(child: Text('No reports yet')),
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _reports.length,
                          itemBuilder: (context, index) {
                            final report = _reports[index];
                            final id = _toInt(report['id']);
                            final status = (report['status'] ?? 'open')
                                .toString()
                                .toLowerCase();
                            final reasonCategory = (report['reason_category'] ?? 'Issue')
                                .toString();
                            final description = (report['description'] ?? report['reason'] ?? '')
                                .toString();
                            final reporter = (report['reporter_name'] ?? 'Reporter').toString();
                            final reported =
                                (report['reported_user_name'] ?? 'Reported User').toString();
                            final itemTitle = (report['item_title'] ?? 'Item').toString();

                            return InkWell(
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => AdminReportDetailPage(reportId: id),
                                  ),
                                );
                                await _load(silent: true);
                              },
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.04),
                                      blurRadius: 12,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          'Report #$id',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 15,
                                          ),
                                        ),
                                        const Spacer(),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 5,
                                          ),
                                          decoration: BoxDecoration(
                                            color: _statusBg(status),
                                            borderRadius: BorderRadius.circular(999),
                                          ),
                                          child: Text(
                                            _statusText(status),
                                            style: TextStyle(
                                              color: _statusFg(status),
                                              fontWeight: FontWeight.w700,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      reasonCategory,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFFB91C1C),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      description,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: Colors.grey[700]),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      'Item: $itemTitle',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: Colors.grey[800],
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '$reporter -> $reported',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
    );
  }
}
