import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/api.dart';

// ==================== TRANSACTION HISTORY PAGE ====================
class TransactionHistoryPage extends StatefulWidget {
  const TransactionHistoryPage({super.key});

  @override
  State<TransactionHistoryPage> createState() => _TransactionHistoryPageState();
}

class _TransactionHistoryPageState extends State<TransactionHistoryPage> {
  List<_TxEntry> _entries = <_TxEntry>[];
  bool _loading = true;
  String? _error;
  int? _userId;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<List<_TxEntry>> _load() async {
    final user = await api.getStoredUser();
    _userId = (user?['id'] as num?)?.toInt();
    final requests = await api.getRequests();

    final entries = <_TxEntry>[];
    final seenRequestIds = <int>{};
    for (final raw in requests) {
      if (raw is! Map<String, dynamic>) continue;
      final req = raw;
      final int? requestId = _toInt(req['id']);
      if (requestId == null) continue;
      if (seenRequestIds.contains(requestId)) continue;
      seenRequestIds.add(requestId);

      final title = req['item_title']?.toString() ?? 'Request #$requestId';

      final startDt = DateTime.tryParse(req['start_date']?.toString() ?? '');
      final endDt = DateTime.tryParse(req['end_date']?.toString() ?? '');
      final fromStr = startDt != null
          ? DateFormat('dd MMM yyyy').format(startDt)
          : '';
      final toStr = endDt != null
          ? DateFormat('dd MMM yyyy').format(endDt)
          : '';
      final dates = (fromStr.isNotEmpty && toStr.isNotEmpty)
          ? '$fromStr - $toStr'
          : '$fromStr$toStr';

      final paymentStatus =
          (req['payment_status'] ?? 'unpaid').toString().toLowerCase().trim();
      final settlementStatus = (req['settlement_status'] ?? 'pending')
          .toString()
          .toLowerCase()
          .trim();
        final requestStatus =
          (req['status'] ?? '').toString().toLowerCase().trim();
      if (!_isRealTransaction(req, paymentStatus, settlementStatus)) continue;

      final num total = _toNum(req['total_amount']) ?? _estimateAmount(req);
        final num rentalAmount = _toNum(req['rental_amount']) ?? 0;
        final num serviceFeeAmount = _toNum(req['service_fee_amount']) ?? 0;
        final num ownerPayoutRaw = _toNum(req['owner_payout_amount']) ?? 0;
        final num ownerPayout = ownerPayoutRaw > 0
          ? ownerPayoutRaw
          : (rentalAmount > 0
            ? (rentalAmount - serviceFeeAmount).clamp(0, rentalAmount)
            : 0);
        final num depositRefundRaw = _toNum(req['deposit_refund_amount']) ?? 0;
        final num depositAmount = _toNum(req['deposit_amount']) ?? 0;
        final num depositRefund = depositRefundRaw > 0
          ? depositRefundRaw
          : depositAmount;
      final bool depositConfiscated = _toInt(req['deposit_confiscated']) == 1;
      final String confiscationReason =
          (req['confiscation_reason'] ?? '').toString().trim();
      final num damageCompensation =
          _toNum(req['damage_compensation_amount']) ?? 0;

      final int? ownerId = _toInt(req['owner_id']);
      final int? borrowerId = _toInt(req['borrower_id']);
      final bool isOwner = _userId != null && ownerId == _userId;
      final bool isBorrower = _userId != null && borrowerId == _userId;
      final DateTime eventPaidAt =
          _eventDate(req, <String>['paid_at', 'transaction_updated_at', 'updated_at']);
        final DateTime eventCompletedAt =
          _eventDate(req, <String>['updated_at', 'transaction_updated_at', 'paid_at']);
      final DateTime eventSettledAt =
          _eventDate(req, <String>['settled_at', 'transaction_updated_at', 'updated_at']);
      final DateTime eventConfiscatedAt =
          _eventDate(req, <String>['confiscated_at', 'settled_at', 'updated_at']);

      if (isBorrower && paymentStatus == 'paid') {
        final num paidAmount = total > 0 ? total : _estimateAmount(req);
        entries.add(
          _TxEntry(
            title: title,
            subtitle: dates,
            amount: paidAmount,
            paymentStatus: paymentStatus,
            flowStatus: 'paid',
            isPositive: false,
            counterparty: req['owner_name']?.toString() ?? 'Lender',
            requestId: requestId,
            borrowerId: borrowerId,
            ownerId: ownerId,
            eventAt: eventPaidAt,
            rentalAmount: rentalAmount > 0 ? rentalAmount : null,
            depositAmount: depositAmount > 0 ? depositAmount : null,
            depositForfeited: depositConfiscated,
          ),
        );
      }

      if (isBorrower && paymentStatus == 'refunded') {
        final num refundAmount = total > 0 ? total : _estimateAmount(req);
        entries.add(
          _TxEntry(
            title: title,
            subtitle: dates,
            amount: refundAmount,
            paymentStatus: paymentStatus,
            flowStatus: 'received',
            isPositive: true,
            counterparty: req['owner_name']?.toString() ?? 'Lender',
            requestId: requestId,
            borrowerId: borrowerId,
            ownerId: ownerId,
            eventAt: eventSettledAt,
          ),
        );
      }

      if (isBorrower &&
          requestStatus == 'completed' &&
          paymentStatus == 'paid' &&
          depositRefund > 0) {
        entries.add(
          _TxEntry(
            title: title,
            subtitle: dates,
            amount: depositRefund,
            paymentStatus: paymentStatus,
            flowStatus: depositConfiscated
                ? 'forfeited'
                : (settlementStatus == 'settled' ? 'received' : 'pending'),
            isPositive: true,
            counterparty: req['owner_name']?.toString() ?? 'Lender',
            requestId: requestId,
            borrowerId: borrowerId,
            ownerId: ownerId,
            eventAt: eventCompletedAt,
            note: depositConfiscated
                ? (confiscationReason.isNotEmpty
                    ? 'Reason: $confiscationReason'
                    : 'Deposit forfeited by admin decision.')
                : null,
          ),
        );
      }

      if (isOwner &&
          requestStatus == 'completed' &&
          paymentStatus == 'paid' &&
          ownerPayout > 0) {
        final baseOwnerRental = (ownerPayout - damageCompensation).clamp(0, ownerPayout);
        if (baseOwnerRental > 0) {
          entries.add(
            _TxEntry(
              title: title,
              subtitle: dates,
              amount: baseOwnerRental,
              paymentStatus: paymentStatus,
              flowStatus: 'received',
              isPositive: true,
              counterparty: req['borrower_name']?.toString() ?? 'Borrower',
              requestId: requestId,
              borrowerId: borrowerId,
              ownerId: ownerId,
              eventAt: eventCompletedAt,
            ),
          );
        }

        if (depositConfiscated && damageCompensation > 0) {
          entries.add(
            _TxEntry(
              title: '$title - Damage Compensation',
              subtitle: dates,
              amount: damageCompensation,
              paymentStatus: paymentStatus,
              flowStatus: 'compensated',
              isPositive: true,
              counterparty: req['borrower_name']?.toString() ?? 'Borrower',
              requestId: requestId,
              borrowerId: borrowerId,
              ownerId: ownerId,
              eventAt: eventConfiscatedAt,
            ),
          );
        }
      }


    }

    entries.sort((a, b) {
      final cmp = b.eventAt.compareTo(a.eventAt);
      if (cmp != 0) return cmp;
      return b.requestId.compareTo(a.requestId);
    });
    return entries;
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

  num _estimateAmount(Map<String, dynamic> req) {
    final price = _toNum(req['price_per_day']) ?? 0;
    final start = DateTime.tryParse((req['start_date'] ?? '').toString());
    final end = DateTime.tryParse((req['end_date'] ?? '').toString());
    if (start == null || end == null) return price;
    final days = end.difference(start).inDays + 1;
    final safeDays = days < 1 ? 1 : days;
    return price * safeDays;
  }

  DateTime _eventDate(Map<String, dynamic> req, List<String> candidates) {
    for (final key in candidates) {
      final raw = req[key];
      if (raw == null) continue;
      final parsed = DateTime.tryParse(raw.toString());
      if (parsed != null) return parsed;
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  bool _isRealTransaction(
    Map<String, dynamic> req,
    String paymentStatus,
    String settlementStatus,
  ) {
    final normalized = paymentStatus.toLowerCase().trim();
    if (normalized == 'paid' || normalized == 'refunded') {
      return true;
    }

    if (settlementStatus == 'settled') {
      return true;
    }

    final paidAt = (req['paid_at'] ?? '').toString().trim();
    final settledAt = (req['settled_at'] ?? '').toString().trim();
    return paidAt.isNotEmpty || settledAt.isNotEmpty;
  }

  Future<void> _refresh({bool silent = false}) async {
    try {
      final latest = await _load();
      if (!mounted) return;
      setState(() {
        _entries = latest;
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
              decoration: BoxDecoration(color: Colors.grey[100]),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.arrow_back),
                  ),
                  const SizedBox(width: 16),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Transactions',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Payment history',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
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
                  if (_error != null && _entries.isEmpty) {
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

                  return RefreshIndicator(
                    onRefresh: () => _refresh(silent: true),
                    child: _entries.isEmpty
                        ? ListView(
                            children: const [
                              SizedBox(height: 200),
                              Center(child: Text('No transactions yet')),
                            ],
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _entries.length,
                            itemBuilder: (context, index) {
                              final tx = _entries[index];
                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.grey[50],
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            tx.title,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            tx.subtitle,
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: Colors.grey[500],
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Order #${tx.requestId}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey[600],
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.person,
                                                size: 14,
                                                color: Colors.grey[500],
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                tx.counterparty,
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: Colors.grey[600],
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                          if (tx.rentalAmount != null || tx.depositAmount != null) ...[
                                            const SizedBox(height: 6),
                                            if (tx.rentalAmount != null)
                                              Text(
                                                'Rental Fee: RM${tx.rentalAmount!.toStringAsFixed(2)}',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey[700],
                                                ),
                                              ),
                                            if (tx.depositAmount != null)
                                              Text(
                                                'Security Deposit: RM${tx.depositAmount!.toStringAsFixed(2)}',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: tx.depositForfeited
                                                      ? const Color(0xFFB91C1C)
                                                      : Colors.grey[700],
                                                  decoration: tx.depositForfeited
                                                      ? TextDecoration.lineThrough
                                                      : TextDecoration.none,
                                                ),
                                              ),
                                          ],
                                          if ((tx.note ?? '').isNotEmpty) ...[
                                            const SizedBox(height: 6),
                                            Text(
                                              tx.note!,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: tx.flowStatus == 'forfeited' || tx.depositForfeited
                                                    ? const Color(0xFFB91C1C)
                                                    : Colors.grey[700],
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          _formatAmount(
                                            tx.amount,
                                            tx.isPositive,
                                          ),
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: tx.flowStatus == 'forfeited'
                                                ? Colors.red[700]
                                                : (tx.isPositive
                                                    ? Colors.green[700]
                                                    : Colors.black87),
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: _statusBgColor(
                                              tx.flowStatus,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                          child: Text(
                                            _statusLabel(tx.flowStatus),
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: _statusTextColor(
                                                tx.flowStatus,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
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

  String _formatAmount(num amount, bool positive) {
    final prefix = positive ? '+' : '-';
    return '$prefix RM${amount.toStringAsFixed(2)}';
  }

  String _capitalize(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1);
  }

  String _statusLabel(String status) {
    if (status == 'forfeited') return 'Deposit Forfeited';
    return _capitalize(status);
  }

  Color _statusTextColor(String status) {
    if (status == 'received') return Colors.green[800]!;
    if (status == 'paid') return Colors.blue[800]!;
    if (status == 'pending') return Colors.orange[900]!;
    if (status == 'forfeited') return const Color(0xFFB91C1C);
    if (status == 'compensated') return const Color(0xFF065F46);
    return Colors.grey[800]!;
  }

  Color _statusBgColor(String status) {
    if (status == 'received') return Colors.green[100]!;
    if (status == 'paid') return Colors.blue[100]!;
    if (status == 'pending') return Colors.orange[100]!;
    if (status == 'forfeited') return const Color(0xFFFDECEC);
    if (status == 'compensated') return const Color(0xFFE6F4F2);
    return Colors.grey[200]!;
  }
}

class _TxEntry {
  final String title;
  final String subtitle;
  final num amount;
  final String paymentStatus;
  final String flowStatus;
  final bool isPositive;
  final String counterparty;
  final int requestId;
  final int? borrowerId;
  final int? ownerId;
  final DateTime eventAt;
  final num? rentalAmount;
  final num? depositAmount;
  final bool depositForfeited;
  final String? note;

  _TxEntry({
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.paymentStatus,
    required this.flowStatus,
    required this.isPositive,
    required this.counterparty,
    required this.requestId,
    this.borrowerId,
    this.ownerId,
    required this.eventAt,
    this.rentalAmount,
    this.depositAmount,
    this.depositForfeited = false,
    this.note,
  });
}

