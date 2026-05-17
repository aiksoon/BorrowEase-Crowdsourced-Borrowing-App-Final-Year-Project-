import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../services/api.dart';

// ==================== BORROWING REQUEST PAGE ====================
class BorrowingRequestPage extends StatefulWidget {
  final Map<String, dynamic> item;

  const BorrowingRequestPage({super.key, required this.item});

  @override
  State<BorrowingRequestPage> createState() => _BorrowingRequestPageState();
}

class _BorrowingRequestPageState extends State<BorrowingRequestPage> {
  late TextEditingController startController;
  late TextEditingController endController;
  DateTime? startDate;
  DateTime? endDate;
  List<Map<String, dynamic>> _blockedRanges = <Map<String, dynamic>>[];
  final Set<String> _blockedDateKeys = <String>{};
  bool _loadingBlockedDates = true;

  @override
  void initState() {
    super.initState();
    startDate = DateTime.now();
    endDate = DateTime.now().add(const Duration(days: 1));
    startController = TextEditingController(text: _formatDate(startDate!));
    endController = TextEditingController(text: _formatDate(endDate!));
    _loadBlockedDates();
  }

  @override
  void dispose() {
    startController.dispose();
    endController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  DateTime _normalizeDate(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  String _dateKey(DateTime date) {
    final d = _normalizeDate(date);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  DateTime? _parseDate(dynamic raw) {
    if (raw == null) return null;
    final text = raw.toString().trim();
    if (text.isEmpty) return null;

    final simpleMatch = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(text);
    if (simpleMatch != null) {
      final year = int.tryParse(simpleMatch.group(1) ?? '');
      final month = int.tryParse(simpleMatch.group(2) ?? '');
      final day = int.tryParse(simpleMatch.group(3) ?? '');
      if (year != null && month != null && day != null) {
        return DateTime(year, month, day);
      }
    }

    final parsed = DateTime.tryParse(text);
    if (parsed == null) return null;
    return parsed.toLocal();
  }

  Future<void> _loadBlockedDates() async {
    final int? itemId = (widget.item['id'] as num?)?.toInt();
    if (itemId == null) {
      if (mounted) setState(() => _loadingBlockedDates = false);
      return;
    }

    setState(() => _loadingBlockedDates = true);
    try {
      final ranges = await api.getBlockedDatesForItem(itemId);
      if (!mounted) return;
      setState(() {
        _blockedRanges = ranges;
        _blockedDateKeys
          ..clear()
          ..addAll(_expandBlockedDateKeys(ranges));
        _loadingBlockedDates = false;
      });
      _ensureInitialDatesValid();
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingBlockedDates = false);
    }
  }

  Set<String> _expandBlockedDateKeys(List<Map<String, dynamic>> ranges) {
    final out = <String>{};
    for (final range in ranges) {
      final start = _parseDate(range['start_date']);
      final end = _parseDate(range['end_date']);
      if (start == null || end == null) continue;
      DateTime cursor = _normalizeDate(start);
      final last = _normalizeDate(end);
      while (!cursor.isAfter(last)) {
        out.add(_dateKey(cursor));
        cursor = cursor.add(const Duration(days: 1));
      }
    }
    return out;
  }

  bool _isBlockedDay(DateTime date) {
    return _blockedDateKeys.contains(_dateKey(date));
  }

  DateTime? _findNextAvailableDate(DateTime from) {
    var cursor = _normalizeDate(from);
    for (int i = 0; i <= 365; i++) {
      if (!_isBlockedDay(cursor)) return cursor;
      cursor = cursor.add(const Duration(days: 1));
    }
    return null;
  }

  bool _hasBlockedDayInRange(DateTime start, DateTime end) {
    DateTime cursor = _normalizeDate(start);
    final last = _normalizeDate(end);
    while (!cursor.isAfter(last)) {
      if (_isBlockedDay(cursor)) return true;
      cursor = cursor.add(const Duration(days: 1));
    }
    return false;
  }

  void _ensureInitialDatesValid() {
    if (!mounted) return;
    final now = _normalizeDate(DateTime.now());
    DateTime? newStart = startDate == null ? null : _normalizeDate(startDate!);
    DateTime? newEnd = endDate == null ? null : _normalizeDate(endDate!);

    if (newStart == null || newStart.isBefore(now) || _isBlockedDay(newStart)) {
      newStart = _findNextAvailableDate(now);
    }
    if (newStart == null) return;

    if (newEnd == null || newEnd.isBefore(newStart) || _hasBlockedDayInRange(newStart, newEnd)) {
      newEnd = _findNextAvailableDate(newStart);
    }

    final resolvedStart = newStart;
    final resolvedEnd = newEnd;

    setState(() {
      startDate = resolvedStart;
      startController.text = _formatDate(resolvedStart);
      endDate = resolvedEnd;
      endController.text = resolvedEnd == null ? '' : _formatDate(resolvedEnd);
    });
  }

  num _toNum(dynamic value) {
    if (value is num) return value;
    if (value is String) return num.tryParse(value) ?? 0;
    return 0;
  }

  int get _rentalDays {
    final start = startDate;
    final end = endDate;
    if (start == null || end == null) return 1;
    final days = end.difference(start).inDays + 1;
    return days < 1 ? 1 : days;
  }

  Future<void> _pickDate({required bool isStart}) async {
    if (_loadingBlockedDates) return;

    final now = _normalizeDate(DateTime.now());
    final initial = isStart
        ? (startDate ?? now)
        : (endDate ??
              startDate?.add(const Duration(days: 1)) ??
              now.add(const Duration(days: 1)));
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: now,
      lastDate: DateTime.now().add(const Duration(days: 365)),
      selectableDayPredicate: (day) {
        final normalized = _normalizeDate(day);
        if (normalized.isBefore(now)) return false;
        return !_isBlockedDay(normalized);
      },
    );
    if (picked != null) {
      final selected = _normalizeDate(picked);
      if (isStart) {
        DateTime? newEnd = endDate == null ? null : _normalizeDate(endDate!);
        if (newEnd != null && newEnd.isBefore(selected)) {
          newEnd = selected;
        }
        if (newEnd != null && _hasBlockedDayInRange(selected, newEnd)) {
          newEnd = null;
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Some selected dates are unavailable. Please choose end date again.'),
              ),
            );
          }
        }

        setState(() {
          startDate = selected;
          startController.text = _formatDate(selected);
          endDate = newEnd;
          endController.text = newEnd == null ? '' : _formatDate(newEnd);
        });
      } else {
        final currentStart = startDate == null ? null : _normalizeDate(startDate!);
        if (currentStart == null) {
          setState(() {
            endDate = selected;
            endController.text = _formatDate(selected);
          });
          return;
        }

        if (selected.isBefore(currentStart)) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('End date cannot be before start date.')),
          );
          return;
        }
        if (_hasBlockedDayInRange(currentStart, selected)) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Selected range includes unavailable dates.')),
          );
          return;
        }

        setState(() {
          endDate = selected;
          endController.text = _formatDate(selected);
        });
      }
    }
  }

  Future<void> _submit() async {
    final int? itemId = (widget.item['id'] as num?)?.toInt();
    if (itemId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Item id missing, please reopen this item'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    if (startDate == null || endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select start and end dates'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    if (_hasBlockedDayInRange(startDate!, endDate!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selected dates include unavailable periods. Please choose different dates.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    try {
      await api.createRequest(
        itemId: itemId,
        startDate: _formatDate(startDate!),
        endDate: _formatDate(endDate!),
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Request submitted'),
            duration: Duration(seconds: 2),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (context.mounted) {
        if (e is DioException && e.response?.statusCode == 409) {
          String message = 'Selected dates are no longer available. Please choose another date range.';
          final data = e.response?.data;
          if (data is Map<String, dynamic>) {
            final serverMessage = data['message']?.toString().trim();
            if (serverMessage != null && serverMessage.isNotEmpty) {
              message = serverMessage;
            }
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              duration: const Duration(seconds: 2),
            ),
          );
          return;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Submit failed: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final String itemTitle = (widget.item['title'] ?? '') as String;
    final dynamic pricePerDay = widget.item['price_per_day'];
    final num rentalPerDay = _toNum(pricePerDay);
    final num deposit = _toNum(widget.item['deposit_amount']);
    final num rentalSubtotal = rentalPerDay * _rentalDays;
    final num totalDue = rentalSubtotal + deposit;
    final String priceText = rentalPerDay > 0
        ? 'RM${rentalPerDay.toStringAsFixed(2)} / day'
        : 'Price not set';

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
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
                        'Select Dates',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Choose your rental period',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Item Summary Card
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            itemTitle,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            priceText,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Divider(height: 16),
                          _buildFeeRow('Rental period', '$_rentalDays day(s)'),
                          _buildFeeRow(
                            'Rental subtotal',
                            'RM${rentalSubtotal.toStringAsFixed(2)}',
                          ),
                          _buildFeeRow(
                            'Security deposit',
                            'RM${deposit.toStringAsFixed(2)}',
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Estimated total due',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              Text(
                                'RM${totalDue.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    if (_blockedRanges.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          'Some dates are unavailable due to existing rentals.',
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                      ),

                    // Start Date
                    const Text(
                      'Start Date',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: TextField(
                        controller: startController,
                        readOnly: true,
                        onTap: _loadingBlockedDates
                            ? null
                            : () => _pickDate(isStart: true),
                        decoration: const InputDecoration(
                          hintText: 'YYYY-MM-DD',
                          border: InputBorder.none,
                          suffixIcon: Icon(Icons.date_range),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // End Date
                    const Text(
                      'End Date',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: TextField(
                        controller: endController,
                        readOnly: true,
                        onTap: _loadingBlockedDates
                            ? null
                            : () => _pickDate(isStart: false),
                        decoration: const InputDecoration(
                          hintText: 'YYYY-MM-DD',
                          border: InputBorder.none,
                          suffixIcon: Icon(Icons.date_range),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Continue Button
            Container(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loadingBlockedDates ? null : _submit,
                  child: const Text(
                    'Submit Request',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeeRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[700])),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}


