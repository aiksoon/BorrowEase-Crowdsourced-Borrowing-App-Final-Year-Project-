import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/api.dart';
import '../services/api_client.dart' show defaultBaseUrl;
import 'screens.dart';

/// Order status enum used for UI state
enum OrderStatus {
  pending,
  approved,
  rejected,
  paid,
  handoverPending,
  active,
  returnPending,
  completed,
}

class OrderDetailPage extends StatefulWidget {
  final int? requestId;
  final int? lenderId;
  final int? borrowerId;
  final int? itemId;
  final int? chatId;
  final String itemName;
  final String? itemImageUrl;
  final String lenderName;
  final String borrowerName;
  final String dates;
  final String price;
  final OrderStatus status;
  final String? statusLabel;
  final String? paymentStatus;
  final bool isLender;

  const OrderDetailPage({
    super.key,
    this.requestId,
    this.lenderId,
    this.borrowerId,
    this.itemId,
    required this.itemName,
    this.itemImageUrl,
    required this.lenderName,
    required this.borrowerName,
    required this.dates,
    required this.price,
    required this.status,
    this.statusLabel,
    this.paymentStatus,
    required this.isLender,
    this.chatId,
  });

  @override
  State<OrderDetailPage> createState() => _OrderDetailPageState();
}

class _OrderDetailPageState extends State<OrderDetailPage> {
  late OrderStatus _currentStatus;
  String? _statusLabel;
  String? _paymentStatus;
  bool _updating = false;
  bool _checkingReview = false;
  bool _hasSubmittedReview = false;
  String? _itemImageUrl;
  late String _displayDates;

  @override
  void initState() {
    super.initState();
    _statusLabel = widget.statusLabel;
    _paymentStatus = widget.paymentStatus;
    _itemImageUrl = _resolveMediaUrl(widget.itemImageUrl);
    _displayDates = widget.dates;
    _currentStatus = _mapStatus(
      widget.statusLabel ?? _statusToBackend(widget.status),
      paymentStatus: widget.paymentStatus,
    );
    _refreshOrderState();
    _refreshReviewStatus();
  }

  String _statusToBackend(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return 'pending';
      case OrderStatus.approved:
        return 'accepted';
      case OrderStatus.rejected:
        return 'rejected';
      case OrderStatus.paid:
        return 'paid';
      case OrderStatus.handoverPending:
        return 'handover';
      case OrderStatus.active:
        return 'in_use';
      case OrderStatus.returnPending:
        return 'return_pending';
      case OrderStatus.completed:
        return 'completed';
    }
  }

  OrderStatus _mapStatus(String status, {String? paymentStatus}) {
    final normalized = status.toLowerCase();
    if (normalized == 'pending') return OrderStatus.pending;
    if (normalized == 'accepted' || normalized == 'approved') {
      if (paymentStatus == 'paid' || paymentStatus == 'settled') {
        return OrderStatus.paid;
      }
      return OrderStatus.approved;
    }
    if (normalized == 'rejected' || normalized == 'cancelled') {
      return OrderStatus.rejected;
    }
    if (normalized == 'paid') return OrderStatus.paid;
    if (normalized == 'handover' || normalized == 'handover_pending') {
      return OrderStatus.handoverPending;
    }
    if (normalized == 'in_use') return OrderStatus.active;
    if (normalized == 'return_pending') return OrderStatus.returnPending;
    if (normalized == 'completed') return OrderStatus.completed;
    return OrderStatus.pending;
  }

  String _getStatusText(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return 'Pending Approval';
      case OrderStatus.approved:
        return 'Awaiting Payment';
      case OrderStatus.rejected:
        return 'Declined';
      case OrderStatus.paid:
        return 'Paid - To Collect';
      case OrderStatus.handoverPending:
        return 'Handover Pending';
      case OrderStatus.active:
        return 'Active - Borrowing';
      case OrderStatus.returnPending:
        return 'Return Pending';
      case OrderStatus.completed:
        return 'Completed';
    }
  }

  String _getStatusDescription(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return 'Request submitted, waiting for lender review.';
      case OrderStatus.approved:
        return widget.isLender
            ? 'Awaiting borrower payment to proceed.'
            : 'Please complete payment to secure the booking.';
      case OrderStatus.rejected:
        return 'This request was declined or cancelled.';
      case OrderStatus.paid:
        return widget.isLender
            ? 'Payment received. Start handover when ready.'
            : 'Payment confirmed. Wait for lender to initiate handover.';
      case OrderStatus.handoverPending:
        return widget.isLender
            ? 'Waiting for borrower pickup confirmation.'
            : 'Lender has confirmed handover. Please verify and confirm receipt.';
      case OrderStatus.active:
        return widget.isLender
            ? 'Borrower is currently using the item.'
            : 'Item is in use. Submit return when ready.';
      case OrderStatus.returnPending:
        return widget.isLender
            ? 'Upload return inspection evidence to complete settlement.'
            : 'Return submitted. Waiting for owner final confirmation.';
      case OrderStatus.completed:
        return 'Order completed. Consider leaving a review.';
    }
  }

  Color _getStatusColor(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return const Color(0xFF0D9488);
      case OrderStatus.approved:
        return Colors.blue;
      case OrderStatus.rejected:
        return Colors.red;
      case OrderStatus.paid:
        return Colors.purple;
      case OrderStatus.handoverPending:
        return const Color(0xFF0F766E);
      case OrderStatus.active:
        return Colors.green;
      case OrderStatus.returnPending:
        return Colors.teal;
      case OrderStatus.completed:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return Icons.hourglass_top;
      case OrderStatus.approved:
        return Icons.assignment_turned_in;
      case OrderStatus.rejected:
        return Icons.cancel_outlined;
      case OrderStatus.paid:
        return Icons.payments_outlined;
      case OrderStatus.handoverPending:
        return Icons.handshake;
      case OrderStatus.active:
        return Icons.play_circle_outline;
      case OrderStatus.returnPending:
        return Icons.assignment_return;
      case OrderStatus.completed:
        return Icons.check_circle_outline;
    }
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

  String _formatPeriodModern(String? rawStart, String? rawEnd) {
    final start = DateTime.tryParse((rawStart ?? '').toString())?.toLocal();
    final end = DateTime.tryParse((rawEnd ?? '').toString())?.toLocal();
    if (start == null || end == null) {
      return _displayDates;
    }

    final nowYear = DateTime.now().year;
    final hideYear = start.year == end.year && start.year == nowYear;

    if (start.year == end.year &&
        start.month == end.month &&
        start.day == end.day) {
      return hideYear
          ? DateFormat('MMM d').format(start)
          : DateFormat('MMM d, yyyy').format(start);
    }

    if (hideYear) {
      return '${DateFormat('MMM d').format(start)} - ${DateFormat('MMM d').format(end)}';
    }

    return '${DateFormat('MMM d, yyyy').format(start)} - ${DateFormat('MMM d, yyyy').format(end)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        title: const Text('Order Details'),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: _refreshOrderState,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            _buildStatusCard(),
            _buildInfoCard(),
            _buildTimelineCard(),
            if (widget.chatId != null) _buildChatButton(),
            _buildActionButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    final color = _getStatusColor(_currentStatus);
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(_getStatusIcon(_currentStatus), size: 48, color: color),
          const SizedBox(height: 12),
          Text(
            _getStatusText(_currentStatus),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _getStatusDescription(_currentStatus),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey[700]),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Order Information',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 64,
                  height: 64,
                  color: Colors.grey[200],
                  child: _itemImageUrl == null
                      ? Icon(Icons.image, color: Colors.grey[500])
                      : Image.network(
                          _itemImageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Icon(Icons.image, color: Colors.grey[500]);
                          },
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.itemName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          _buildInfoRow(
            'Order ID',
            widget.requestId != null ? '#${widget.requestId}' : '-',
          ),
          _buildInfoRow('Lender', widget.lenderName),
          if (widget.isLender) _buildInfoRow('Borrower', widget.borrowerName),
          _buildInfoRow('Period', _displayDates),
          _buildInfoRow('Total', widget.price),
        ],
      ),
    );
  }

  Widget _buildTimelineCard() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Order Progress',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          ..._buildTimeline(),
        ],
      ),
    );
  }

  List<Widget> _buildTimeline() {
    final steps = [
      {'title': 'Pending'},
      {'title': 'Approved'},
      {'title': 'Paid'},
      {'title': 'Handover'},
      {'title': 'Active'},
      {'title': 'Return Pending'},
      {'title': 'Completed'},
    ];
    final statusOrder = {
      OrderStatus.pending: 0,
      OrderStatus.approved: 1,
      OrderStatus.paid: 2,
      OrderStatus.handoverPending: 3,
      OrderStatus.active: 4,
      OrderStatus.returnPending: 5,
      OrderStatus.completed: 6,
      OrderStatus.rejected: -1,
    };
    final currentIndex = statusOrder[_currentStatus] ?? 0;

    return List.generate(steps.length, (index) {
      final isDone =
          currentIndex >= index && _currentStatus != OrderStatus.rejected;
      final isLast = index == steps.length - 1;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              CircleAvatar(
                radius: 10,
                backgroundColor: isDone ? Colors.green : Colors.grey[300],
                child: Icon(
                  isDone ? Icons.check : Icons.radio_button_unchecked,
                  size: 12,
                  color: Colors.white,
                ),
              ),
              if (!isLast)
                Container(
                  width: 2,
                  height: 30,
                  color: isDone ? Colors.green : Colors.grey[300],
                ),
            ],
          ),
          const SizedBox(width: 12),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              steps[index]['title'] as String,
              style: TextStyle(
                fontWeight: isDone ? FontWeight.w600 : FontWeight.normal,
                color: isDone ? Colors.black : Colors.grey[500],
              ),
            ),
          ),
        ],
      );
    });
  }

  Widget _buildChatButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: OutlinedButton.icon(
        onPressed: () {
          if (widget.chatId == null) return;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ChatConversationPage(
                chatId: widget.chatId!,
                peerName: widget.isLender
                    ? widget.borrowerName
                    : widget.lenderName,
                peerRating: '4.8',
              ),
            ),
          );
        },
        icon: const Icon(Icons.chat_bubble_outline),
        label: const Text('Open Chat'),
      ),
    );
  }

  Widget _buildActionButtons() {
    switch (_currentStatus) {
      case OrderStatus.pending:
        return _pendingActions();
      case OrderStatus.approved:
        return _approvedActions();
      case OrderStatus.paid:
        return _paidActions();
      case OrderStatus.handoverPending:
        return _handoverActions();
      case OrderStatus.active:
        return _activeActions();
      case OrderStatus.returnPending:
        return _returnActions();
      case OrderStatus.completed:
        return _completedActions();
      case OrderStatus.rejected:
        return const SizedBox.shrink();
    }
  }

  Widget _pendingActions() {
    if (widget.isLender) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _updating ? null : () => _updateStatus('rejected'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                ),
                child: _updating
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Reject'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: _updating ? null : () => _updateStatus('accepted'),
                child: _updating
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Approve'),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: OutlinedButton(
        onPressed: _updating ? null : () => _updateStatus('cancelled'),
        child: _updating
            ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Cancel Request'),
      ),
    );
  }

  Widget _approvedActions() {
    if (!widget.isLender) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton.icon(
              onPressed: _updating ? null : _openPaymentFlow,
              icon: const Icon(Icons.payment),
              label: _updating
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Pay Now'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _updating ? null : _confirmCancelFromApproved,
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('Cancel Request'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
                minimumSize: const Size(double.infinity, 46),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Waiting for borrower payment',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _updating ? null : _confirmCancelFromApproved,
            icon: const Icon(Icons.cancel_outlined),
            label: _updating
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Cancel Request'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red),
              minimumSize: const Size(double.infinity, 46),
            ),
          ),
        ],
      ),
    );
  }

  Widget _paidActions() {
    if (widget.isLender) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: ElevatedButton.icon(
          onPressed: _updating ? null : () => _openHandoverFlow(isPickup: true),
          icon: const Icon(Icons.handshake),
          label: _updating
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Confirm Handover'),
        ),
      );
    }

    return const Padding(
      padding: EdgeInsets.all(16),
      child: Text(
        'Waiting for lender to start handover',
        style: TextStyle(color: Colors.grey),
      ),
    );
  }

  Widget _handoverActions() {
    if (!widget.isLender) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: ElevatedButton(
          onPressed: _updating ? null : () => _openHandoverFlow(isPickup: true),
          child: _updating
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Yes, I received it in good condition'),
        ),
      );
    }

    return const Padding(
      padding: EdgeInsets.all(16),
      child: Text(
        'Waiting for borrower pickup confirmation',
        style: TextStyle(color: Colors.grey),
      ),
    );
  }

  Widget _activeActions() {
    if (!widget.isLender) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: ElevatedButton(
          onPressed: _updating
              ? null
              : () => _openHandoverFlow(isPickup: false),
          child: _updating
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Submit Return (Photo)'),
        ),
      );
    }

    return const Padding(
      padding: EdgeInsets.all(16),
      child: Text(
        'Waiting for borrower to submit return',
        style: TextStyle(color: Colors.grey),
      ),
    );
  }

  Widget _returnActions() {
    if (widget.isLender) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: ElevatedButton.icon(
          onPressed: _updating
              ? null
              : () => _openHandoverFlow(isPickup: false),
          icon: const Icon(Icons.verified_outlined),
          label: const Text('Confirm Received'),
        ),
      );
    }
    return const Padding(
      padding: EdgeInsets.all(16),
      child: Text(
        'Waiting for owner final confirmation',
        style: TextStyle(color: Colors.grey),
      ),
    );
  }

  Widget _completedActions() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          if (widget.isLender && widget.borrowerId != null)
            ElevatedButton.icon(
              onPressed: _hasSubmittedReview || _checkingReview
                  ? null
                  : () => _openReviewPage(
                        revieweeId: widget.borrowerId,
                        targetName: widget.borrowerName,
                        reviewType: 'borrower',
                      ),
              icon: const Icon(Icons.person_outline),
              label: Text(_hasSubmittedReview ? 'Completed' : 'Review Borrower'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _hasSubmittedReview
                    ? Colors.grey[400]
                    : const Color(0xFF0D9488),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
          if (!widget.isLender && widget.lenderId != null) ...[
            ElevatedButton.icon(
              onPressed: _hasSubmittedReview || _checkingReview
                  ? null
                  : () => _openReviewPage(
                        revieweeId: widget.lenderId,
                        targetName: widget.lenderName,
                        reviewType: 'lender',
                      ),
              icon: const Icon(Icons.person_outline),
              label: Text(_hasSubmittedReview ? 'Completed' : 'Review Lender'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _hasSubmittedReview
                    ? Colors.grey[400]
                    : const Color(0xFF0D9488),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600])),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  void _showReviewDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Order Completed!'),
        content: const Text(
          'Would you like to leave a review for this transaction?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Later'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              if (widget.isLender && widget.borrowerId != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => LeaveReviewPage(
                      requestId: widget.requestId,
                      revieweeId: widget.borrowerId,
                      targetName: widget.borrowerName,
                      reviewType: 'borrower',
                    ),
                  ),
                );
              } else if (widget.lenderId != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => LeaveReviewPage(
                      requestId: widget.requestId,
                      revieweeId: widget.lenderId,
                      targetName: widget.lenderName,
                      reviewType: 'lender',
                    ),
                  ),
                );
              }
            },
            child: const Text('Leave Review'),
          ),
        ],
      ),
    );
  }

  int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  Future<void> _refreshOrderState() async {
    if (widget.requestId == null) return;
    try {
      final list = await api.getRequests();
      final target = list.whereType<Map<String, dynamic>>().firstWhere(
        (r) => _toInt(r['id']) == widget.requestId,
        orElse: () => <String, dynamic>{},
      );
      if (target.isEmpty || !mounted) return;

      final status = target['status']?.toString() ?? _statusLabel ?? 'pending';
      final paymentStatus =
          target['payment_status']?.toString() ?? _paymentStatus;
      final latestItemImage = _resolveMediaUrl(
        target['item_image_url'] ?? target['image_url'],
      );
      final latestDates = _formatPeriodModern(
        target['start_date']?.toString(),
        target['end_date']?.toString(),
      );

      setState(() {
        _statusLabel = status;
        _paymentStatus = paymentStatus;
        _itemImageUrl = latestItemImage ?? _itemImageUrl;
        _displayDates = latestDates;
        _currentStatus = _mapStatus(status, paymentStatus: paymentStatus);
      });
      await _refreshReviewStatus();
    } catch (_) {
      // Best-effort refresh.
    }
  }

  int? _currentRevieweeId() {
    return widget.isLender ? widget.borrowerId : widget.lenderId;
  }

  Future<void> _refreshReviewStatus() async {
    final requestId = widget.requestId;
    final revieweeId = _currentRevieweeId();
    if (requestId == null || revieweeId == null) return;

    if (mounted) {
      setState(() => _checkingReview = true);
    }

    try {
      final me = await api.getStoredUser();
      final reviewerId = _toInt(me?['id']);
      if (reviewerId == null) {
        if (!mounted) return;
        setState(() {
          _hasSubmittedReview = false;
          _checkingReview = false;
        });
        return;
      }

      final reviews = await api.getReviews(userId: revieweeId);
      bool found = false;
      for (final raw in reviews) {
        if (raw is! Map<String, dynamic>) continue;
        if (_toInt(raw['request_id']) != requestId) continue;
        if (_toInt(raw['reviewer_id']) != reviewerId) continue;
        found = true;
        break;
      }

      if (!mounted) return;
      setState(() {
        _hasSubmittedReview = found;
        _checkingReview = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _checkingReview = false);
    }
  }

  Future<void> _openReviewPage({
    required int? revieweeId,
    required String targetName,
    required String reviewType,
  }) async {
    if (revieweeId == null) return;
    final submitted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => LeaveReviewPage(
          requestId: widget.requestId,
          revieweeId: revieweeId,
          targetName: targetName,
          reviewType: reviewType,
        ),
      ),
    );
    if (submitted == true && mounted) {
      setState(() => _hasSubmittedReview = true);
    }
  }

  Future<void> _openPaymentFlow() async {
    if (widget.requestId == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PaymentPage(
          requestId: widget.requestId!,
          itemName: widget.itemName,
          itemImageUrl: _itemImageUrl,
        ),
      ),
    );
    await _refreshOrderState();
  }

  Future<void> _openHandoverFlow({required bool isPickup}) async {
    if (widget.requestId == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => HandoverPage(
          itemName: widget.itemName,
          itemImageUrl: _itemImageUrl,
          isPickup: isPickup,
          isLender: widget.isLender,
          requestId: widget.requestId!,
          onConfirmed: () {
            _refreshOrderState();
          },
        ),
      ),
    );
    await _refreshOrderState();
  }

  Future<void> _updateStatus(String nextStatus) async {
    if (widget.requestId == null) return;
    setState(() => _updating = true);
    try {
      final res = await api.updateRequestStatus(
        requestId: widget.requestId!,
        nextStatus: nextStatus,
      );

      final status = res['status']?.toString() ?? nextStatus;
      final paymentStatus = res['payment_status']?.toString() ?? _paymentStatus;

      if (!mounted) return;
      setState(() {
        _statusLabel = status;
        _paymentStatus = paymentStatus;
        _currentStatus = _mapStatus(status, paymentStatus: paymentStatus);
      });

      _showSnackBar('Status updated to $status');
      if (status == 'cancelled') {
        Navigator.pop(context, {'status': status});
        return;
      }
      if (_currentStatus == OrderStatus.completed) {
        _showReviewDialog();
      }
    } catch (e) {
      _showSnackBar('Update failed: $e');
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  Future<void> _confirmCancelFromApproved() async {
    final isBorrower = !widget.isLender;
    final shouldCancel = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          isBorrower ? 'Cancel this borrow request?' : 'Cancel this request?',
        ),
        content: Text(
          isBorrower
              ? 'This will cancel your borrow request before payment is made.'
              : 'This will cancel the request while waiting for borrower payment.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(isBorrower ? 'Keep Request' : 'Keep Waiting'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              isBorrower ? 'Cancel Borrow Request' : 'Cancel Request',
            ),
          ),
        ],
      ),
    );
    if (shouldCancel == true) {
      await _updateStatus('cancelled');
    }
  }
}


