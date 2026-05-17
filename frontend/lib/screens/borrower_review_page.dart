import 'package:flutter/material.dart';

import '../services/api.dart';
import 'screens.dart';

// ==================== BORROWER REVIEW PAGE ====================
class BorrowerReviewPage extends StatefulWidget {
  const BorrowerReviewPage({super.key});

  @override
  State<BorrowerReviewPage> createState() => _BorrowerReviewPageState();
}

class _BorrowerReviewPageState extends State<BorrowerReviewPage> {
  List<Map<String, dynamic>> _completed = <Map<String, dynamic>>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh({bool silent = false}) async {
    try {
      final raw = await api.getRequests(role: 'borrower');
      if (!mounted) return;
      final list = raw
          .whereType<Map<String, dynamic>>()
          .where((req) => req['status']?.toString() == 'completed')
          .toList();
      setState(() {
        _completed = list;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (!silent) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.arrow_back),
                  ),
                  const SizedBox(width: 16),
                  const Text(
                    'Review as Borrower',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
                  if (_error != null && _completed.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Failed to load: $_error'),
                          const SizedBox(height: 8),
                          ElevatedButton(
                            onPressed: () => _refresh(),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    );
                  }

                  if (_completed.isEmpty) {
                    return RefreshIndicator(
                      onRefresh: () => _refresh(silent: true),
                      child: ListView(
                        children: const [
                          SizedBox(height: 200),
                          Center(child: Text('No completed rentals to review yet')),
                        ],
                      ),
                    );
                  }

                  return RefreshIndicator(
                    onRefresh: () => _refresh(silent: true),
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _completed.length,
                      itemBuilder: (context, index) {
                        final req = _completed[index];
                        final requestId = (req['id'] as num?)?.toInt();
                        final lenderId = (req['owner_id'] as num?)?.toInt();
                        final itemTitle = req['item_title']?.toString() ?? 'Item';
                        final lender = req['owner_name']?.toString() ?? 'Lender';
                        final dates = '${req['start_date'] ?? ''} - ${req['end_date'] ?? ''}';

                        return Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.grey[50],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 50,
                                    height: 50,
                                    decoration: BoxDecoration(
                                      color: Colors.grey[300],
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(Icons.build, color: Colors.grey[500]),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(itemTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
                                        Text('from $lender', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                                        Text(dates, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: requestId == null || lenderId == null
                                      ? null
                                      : () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) => LeaveReviewPage(
                                                requestId: requestId,
                                                revieweeId: lenderId,
                                                reviewType: 'lender',
                                                targetName: lender,
                                              ),
                                            ),
                                          );
                                        },
                                  child: const Text('Review Lender'),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
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
}



