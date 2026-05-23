import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/api.dart';
import '../services/api_client.dart' show defaultBaseUrl;
import 'screens.dart';

// ==================== MY BORROWINGS PAGE ====================
// Borrower views their borrow requests pulled from backend
class MyBorrowingsPage extends StatefulWidget {
  const MyBorrowingsPage({super.key});

  @override
  State<MyBorrowingsPage> createState() => _MyBorrowingsPageState();
}

class _MyBorrowingsPageState extends State<MyBorrowingsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<dynamic> _requests = <dynamic>[];
  Set<int> _reviewedRequestIds = <int>{};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _refresh();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<List<dynamic>> _load() => api.getRequests(role: 'borrower');

  Future<void> _refresh({bool silent = false}) async {
    try {
      final latest = await _load();
      final reviewState = await _resolveReviewedRequestIds(latest);
      if (!mounted) return;
      setState(() {
        _requests = latest;
        _reviewedRequestIds = reviewState.reviewedRequestIds;
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

  Future<_BorrowingReviewState> _resolveReviewedRequestIds(
    List<dynamic> latest,
  ) async {
    final me = await api.getStoredUser();
    final reviewerId = _toInt(me?['id']);
    if (reviewerId == null) {
      return const _BorrowingReviewState(
        reviewedRequestIds: <int>{},
      );
    }

    final completedRequests = latest
        .whereType<Map<String, dynamic>>()
        .where((req) => (req['status'] ?? '').toString() == 'completed')
        .toList();

    final lenderIds = completedRequests
        .map((req) => _toInt(req['owner_id']))
        .whereType<int>()
        .toSet();

    if (lenderIds.isEmpty) {
      return _BorrowingReviewState(
        reviewedRequestIds: const <int>{},
      );
    }

    final reviewMapEntries = await Future.wait(
      lenderIds.map((lenderId) async {
        try {
          final rows = await api.getReviews(userId: lenderId);
          return MapEntry<int, List<dynamic>>(lenderId, rows);
        } catch (_) {
          return MapEntry<int, List<dynamic>>(lenderId, <dynamic>[]);
        }
      }),
    );

    final reviewsByLender = <int, List<dynamic>>{
      for (final entry in reviewMapEntries) entry.key: entry.value,
    };

    final reviewed = <int>{};
    for (final req in completedRequests) {
      final requestId = _toInt(req['id']);
      final lenderId = _toInt(req['owner_id']);
      if (requestId == null || lenderId == null) continue;

      final lenderReviews = reviewsByLender[lenderId] ?? const <dynamic>[];
      final hasReviewed = lenderReviews.any((raw) {
        if (raw is! Map<String, dynamic>) return false;
        return _toInt(raw['request_id']) == requestId &&
            _toInt(raw['reviewer_id']) == reviewerId;
      });

      if (hasReviewed) {
        reviewed.add(requestId);
      }
    }

    return _BorrowingReviewState(
      reviewedRequestIds: reviewed,
    );
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
                    'Items I\'m Borrowing',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),

            // Tab Bar
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: TabBar(
                controller: _tabController,
                indicatorSize: TabBarIndicatorSize.tab,
                splashFactory: NoSplash.splashFactory,
                overlayColor: WidgetStateProperty.all(Colors.transparent),
                indicator: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withValues(alpha: 0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                indicatorPadding: const EdgeInsets.all(4),
                labelColor: Colors.black,
                unselectedLabelColor: Colors.grey[600],
                labelStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                dividerColor: Colors.transparent,
                tabs: const [
                  Tab(text: 'Active'),
                  Tab(text: 'Completed'),
                  Tab(text: 'Cancelled'),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Tab Views
            Expanded(
              child: Builder(
                builder: (context) {
                  if (_loading) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (_error != null && _requests.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Failed to load: $_error', textAlign: TextAlign.center),
                          const SizedBox(height: 8),
                          ElevatedButton(
                            onPressed: () => _refresh(),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    );
                  }

                  final active = _filter(_requests, const [
                    'pending',
                    'accepted',
                    'handover',
                    'in_use',
                    'return_pending',
                  ]);
                  final completed = _filter(_requests, const ['completed']);
                  final cancelled = _filter(_requests, const [
                    'rejected',
                    'cancelled',
                  ]);

                  return TabBarView(
                    controller: _tabController,
                    children: [
                      _buildOrdersList(active, 'active'),
                      _buildOrdersList(completed, 'completed'),
                      _buildOrdersList(cancelled, 'cancelled'),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _filter(
    List<dynamic> data,
    List<String> statuses,
  ) {
    return data
        .whereType<Map<String, dynamic>>()
        .where((req) => statuses.contains(req['status']?.toString()))
        .toList();
  }

  int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  num? _toNum(dynamic value) {
    if (value is num) return value;
    if (value is String) return num.tryParse(value);
    return null;
  }

  String? _resolveMediaUrl(dynamic raw) {
    final value = (raw ?? '').toString().trim();
    if (value.isEmpty) return null;
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    final cleanValue = value.startsWith('/') ? value.substring(1) : value;
    final baseUrl = defaultBaseUrl.endsWith('/') 
        ? defaultBaseUrl.substring(0, defaultBaseUrl.length - 1)
        : defaultBaseUrl;
    return '$baseUrl/$cleanValue';
  }

  Widget _buildOrdersList(List<Map<String, dynamic>> orders, String category) {
    final empty = Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            category == 'active'
                ? Icons.shopping_bag_outlined
                : category == 'completed'
                ? Icons.check_circle_outline
                : Icons.cancel_outlined,
            size: 60,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 16),
          Text(
            'No $category orders',
            style: TextStyle(color: Colors.grey[500], fontSize: 16),
          ),
        ],
      ),
    );

    return RefreshIndicator(
      onRefresh: () => _refresh(silent: true),
      child: orders.isEmpty
          ? ListView(children: [const SizedBox(height: 120), empty])
          : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: orders.length,
              itemBuilder: (context, index) => _buildOrderCard(orders[index]),
            ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> req) {
    final statusStr = req['status']?.toString() ?? 'pending';
    final paymentStatus = req['payment_status']?.toString();
    final status = _mapStatus(statusStr, paymentStatus: paymentStatus);
    final statusInfo = _getStatusInfo(status, backendStatus: statusStr);

    final int? requestId = _toInt(req['id']);
    final int? lenderId = _toInt(req['owner_id']);
    final int? borrowerId = _toInt(req['borrower_id']);
    final int? itemId = _toInt(req['item_id']);
    final int? chatId = _toInt(req['chat_id']);

    final itemTitle = req['item_title']?.toString() ?? 'Item #${itemId ?? ''}';
    final itemImageUrl = _resolveMediaUrl(
      req['item_image_url'] ?? req['image_url'],
    );
    final lenderName = req['owner_name']?.toString() ?? 'Lender';
    final hasReviewed =
      requestId != null && _reviewedRequestIds.contains(requestId);

    final rawStart = req['start_date']?.toString();
    final rawEnd = req['end_date']?.toString();
    String dates = '-';
    if (rawStart != null && rawEnd != null) {
      try {
        final start = DateTime.parse(rawStart).toLocal();
        final end = DateTime.parse(rawEnd).toLocal();
        if (start.year == end.year && start.month == end.month) {
          dates =
              '${DateFormat('MMM d').format(start)} - ${DateFormat('d, yyyy').format(end)}';
        } else if (start.year == end.year) {
          dates =
              '${DateFormat('MMM d').format(start)} - ${DateFormat('MMM d, yyyy').format(end)}';
        } else {
          dates =
              '${DateFormat('MMM d, yyyy').format(start)} - ${DateFormat('MMM d, yyyy').format(end)}';
        }
      } catch (_) {
        dates = '$rawStart -> $rawEnd';
      }
    }

    final num? priceValue =
        _toNum(req['total_amount']) ?? _toNum(req['price_per_day']);
    final priceText = priceValue != null
        ? 'RM ${priceValue.toStringAsFixed(2)}'
        : 'RM -';

    return GestureDetector(
      onTap: () async {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => OrderDetailPage(
              requestId: requestId,
              itemId: itemId,
              lenderId: lenderId,
              borrowerId: borrowerId,
              itemName: itemTitle,
              itemImageUrl: itemImageUrl,
              lenderName: lenderName,
              borrowerName: 'You',
              dates: dates,
              price: priceText,
              status: status,
              statusLabel: statusStr,
              paymentStatus: paymentStatus,
              isLender: false,
              chatId: chatId,
            ),
          ),
        );
        if (mounted) {
          await _refresh();
          final returnedStatus = result is Map<String, dynamic>
              ? result['status']?.toString().toLowerCase()
              : result?.toString().toLowerCase();
          if (returnedStatus == 'cancelled' || returnedStatus == 'rejected') {
            _tabController.animateTo(2);
          }
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Badge and Date
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusInfo['color'].withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        statusInfo['icon'],
                        size: 14,
                        color: statusInfo['color'],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        statusInfo['label'],
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: statusInfo['color'],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      dates,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Item Info
            Row(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: itemImageUrl == null
                      ? Icon(Icons.image, color: Colors.grey[400])
                      : Image.network(
                          itemImageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Icon(Icons.image, color: Colors.grey[400]);
                          },
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        itemTitle,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Lender: $lenderName',
                        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      priceText,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Icon(Icons.chevron_right, color: Colors.grey[400]),
                  ],
                ),
              ],
            ),

            // Quick Action Button based on status
            if (status == OrderStatus.approved && requestId != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => PaymentPage(
                          requestId: requestId,
                          itemName: itemTitle,
                          itemImageUrl: itemImageUrl,
                        ),
                      ),
                    );
                    if (mounted) {
                      _refresh();
                    }
                  },
                  icon: const Icon(Icons.payment, size: 18),
                  label: const Text('Pay Now'),
                ),
              ),
            ],

            if (status == OrderStatus.paid) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.hourglass_bottom,
                      size: 16,
                      color: Colors.blue[700],
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Payment received. Waiting for lender to prepare handover...',
                        style: TextStyle(fontSize: 12, color: Colors.blue[700]),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (status == OrderStatus.handoverPending) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: requestId == null
                      ? null
                      : () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => HandoverPage(
                                itemName: itemTitle,
                                itemImageUrl: itemImageUrl,
                                isPickup: true,
                                isLender: false,
                                requestId: requestId,
                                onConfirmed: _refresh,
                              ),
                            ),
                          );
                        },
                  icon: const Icon(Icons.check_circle, size: 18),
                  label: const Text('Confirm Receipt'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],

            if (status == OrderStatus.active) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.timer, size: 16, color: Colors.green[700]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Currently borrowing. Enjoy the item!',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.green[700],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: requestId == null
                      ? null
                      : () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => HandoverPage(
                                itemName: itemTitle,
                                itemImageUrl: itemImageUrl,
                                isPickup: false,
                                isLender: false,
                                requestId: requestId,
                                onConfirmed: _refresh,
                              ),
                            ),
                          );
                        },
                  icon: const Icon(Icons.assignment_return, size: 18),
                  label: const Text('Return Item'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.green[800],
                    side: BorderSide(color: Colors.green[300]!),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],

            if (status == OrderStatus.returnPending) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.teal[50],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.pending_actions,
                      size: 16,
                      color: Colors.teal[700],
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Return submitted. Waiting for lender final inspection and settlement.',
                        style: TextStyle(fontSize: 12, color: Colors.teal[700]),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (status == OrderStatus.completed) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: hasReviewed
                      ? null
                      : () async {
                          final submitted = await Navigator.push<bool>(
                            context,
                            MaterialPageRoute(
                              builder: (context) => LeaveReviewPage(
                                requestId: requestId,
                                revieweeId: lenderId,
                                targetName: lenderName,
                                reviewType: 'lender',
                              ),
                            ),
                          );
                          if (submitted == true && mounted && requestId != null) {
                            setState(() {
                              _reviewedRequestIds.add(requestId);
                            });
                          }
                        },
                  icon: const Icon(Icons.person_outline, size: 18),
                  label: Text(hasReviewed ? 'Completed' : 'Review Lender'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: hasReviewed
                        ? Colors.grey[600]
                        : const Color(0xFF0F766E),
                    side: BorderSide(
                      color: hasReviewed
                          ? Colors.grey[300]!
                          : const Color(0xFF0D9488).withValues(alpha: 0.4),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  OrderStatus _mapStatus(String status, {String? paymentStatus}) {
    switch (status) {
      case 'pending':
        return OrderStatus.pending;
      case 'accepted':
        return paymentStatus == 'paid'
            ? OrderStatus.paid
            : OrderStatus.approved;
      case 'handover':
        return OrderStatus.handoverPending;
      case 'in_use':
        return OrderStatus.active;
      case 'return_pending':
        return OrderStatus.returnPending;
      case 'completed':
        return OrderStatus.completed;
      case 'rejected':
      case 'cancelled':
        return OrderStatus.rejected;
      default:
        return OrderStatus.pending;
    }
  }

  Map<String, dynamic> _getStatusInfo(
    OrderStatus status, {
    String? backendStatus,
  }) {
    switch (status) {
      case OrderStatus.pending:
        return {
          'label': 'Pending',
          'color': const Color(0xFF0D9488),
          'icon': Icons.hourglass_empty,
        };
      case OrderStatus.approved:
        return {
          'label': 'Awaiting Payment',
          'color': Colors.blue,
          'icon': Icons.payment,
        };
      case OrderStatus.rejected:
        return {
          'label': backendStatus == 'cancelled' ? 'Cancelled' : 'Declined',
          'color': Colors.red,
          'icon': Icons.cancel,
        };
      case OrderStatus.paid:
        return {
          'label': 'Paid - Handover',
          'color': Colors.purple,
          'icon': Icons.local_shipping,
        };
      case OrderStatus.handoverPending:
        return {
          'label': 'Handover Pending',
          'color': const Color(0xFF0F766E),
          'icon': Icons.handshake,
        };
      case OrderStatus.active:
        return {
          'label': 'Active',
          'color': Colors.green,
          'icon': Icons.access_time,
        };
      case OrderStatus.returnPending:
        return {
          'label': 'Return Pending',
          'color': Colors.teal,
          'icon': Icons.assignment_return,
        };
      case OrderStatus.completed:
        return {
          'label': 'Completed',
          'color': Colors.grey,
          'icon': Icons.check_circle,
        };
    }
  }
}

class _BorrowingReviewState {
  const _BorrowingReviewState({
    required this.reviewedRequestIds,
  });

  final Set<int> reviewedRequestIds;
}



