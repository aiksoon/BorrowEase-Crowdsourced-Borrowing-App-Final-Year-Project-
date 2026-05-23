import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api.dart';
import 'screens.dart';

// ==================== ALERTS PAGE ====================
class AlertsPage extends StatefulWidget {
  const AlertsPage({super.key});

  @override
  State<AlertsPage> createState() => _AlertsPageState();
}

class _AlertsPageState extends State<AlertsPage> {
  static const String _dismissedGlobalKey = 'alerts.dismissed.global';
  static const String _clearedAtGlobalKey = 'alerts.cleared_at.global';

  int selectedTabIndex = 0;
  final List<String> tabs = ['All', 'Requests', 'Messages', 'Reminders'];
  bool _loading = true;
  bool _refreshing = false;
  int? _currentUserId;
  String _currentUserName = 'User';
  List<Map<String, dynamic>> _notifications = [];
  final Set<String> _dismissedIds = <String>{};
  int? _dismissedUserId;
  bool _dismissedLoaded = false;
  DateTime? _clearedAt;
  Timer? _poller;

  @override
  void initState() {
    super.initState();
    _refreshNotifications();
    _startPolling();
  }

  @override
  void dispose() {
    _poller?.cancel();
    super.dispose();
  }

  void _startPolling() {
    _poller?.cancel();
    _poller = Timer.periodic(const Duration(seconds: 6), (_) {
      _refreshNotifications(silent: true);
    });
  }

  Future<void> _refreshNotifications({bool silent = false}) async {
    if (_refreshing) return;
    if (mounted) {
      setState(() {
        _refreshing = true;
        if (_notifications.isEmpty && !silent) {
          _loading = true;
        }
      });
    }
    try {
      final storedUser = await api.getStoredUser();
      int? userId = _toInt(storedUser?['id']);
      if (userId == null) {
        try {
          final me = await api.getMe();
          final meUser = me['user'];
          if (meUser is Map<String, dynamic>) {
            userId = _toInt(meUser['id']);
          }
        } catch (_) {
          // Keep fallback behavior when network is unavailable.
        }
      }
      await _ensureDismissedLoaded(userId);

      final results = await Future.wait<dynamic>([
        api.getRequests(),
        api.getChats(),
        api.getKyc().catchError((_) => <String, dynamic>{}),
        api.getReviews().catchError((_) => <dynamic>[]),
        api.getSystemNotifications().catchError((_) => <dynamic>[]),
      ]);

      final requests = (results[0] as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e.cast<String, dynamic>()))
          .toList();
      final chats = (results[1] as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e.cast<String, dynamic>()))
          .toList();
      final kyc = results[2] is Map<String, dynamic>
          ? Map<String, dynamic>.from(results[2] as Map<String, dynamic>)
          : <String, dynamic>{};
      final reviews = (results[3] as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e.cast<String, dynamic>()))
          .toList();
      final systemNotifs = (results[4] as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e.cast<String, dynamic>()))
          .toList();

      final entries = <Map<String, dynamic>>[];

      for (final req in requests) {
        final requestId = _toInt(req['id']);
        if (requestId == null) continue;

        final ownerId = _toInt(req['owner_id']);
        final borrowerId = _toInt(req['borrower_id']);
        final isOwner = userId != null && ownerId == userId;
        final isBorrower = userId != null && borrowerId == userId;
        final itemTitle = (req['item_title'] ?? 'Item').toString();
        final status = (req['status'] ?? '').toString();
        final paymentStatus = (req['payment_status'] ?? '').toString();
        final updatedAt = req['updated_at']?.toString();
        final createdAt = updatedAt ?? req['created_at']?.toString();
        final paidAt = req['paid_at']?.toString();
        final txUpdatedAt = req['transaction_updated_at']?.toString();
        final paymentEventAt = paidAt ?? txUpdatedAt ?? createdAt;
        final endDate = req['end_date']?.toString();

        final statusLabel = _statusLabel(status);
        final bool hideGenericAcceptedForBorrower =
            isBorrower && status == 'accepted';
        final bool hideGenericCompletedForBorrower =
            isBorrower && status == 'completed';
        final bool hideGenericHandoverForBorrower =
            isBorrower && status == 'handover';
        final bool hideGenericInUseForOwner = isOwner && status == 'in_use';
        final bool shouldShowGenericRequest =
            !hideGenericAcceptedForBorrower &&
            !hideGenericCompletedForBorrower &&
            !hideGenericHandoverForBorrower &&
            !hideGenericInUseForOwner;

        if (shouldShowGenericRequest) {
          final statusVisual = _requestStatusVisual(status);
          final reqNotifId = 'request-$requestId-$status-${createdAt ?? ''}';
          entries.add({
            'id': reqNotifId,
            'type': 'Requests',
            'title': isOwner ? 'Borrow request' : 'Your request',
            'message': '$itemTitle - $statusLabel',
            'timestamp': createdAt,
            'icon': statusVisual['icon'],
            'iconBg': statusVisual['iconBg'],
            'iconColor': statusVisual['iconColor'],
            'action': 'request',
            'payload': req,
          });
        }

        final needsPaymentReminder =
            isBorrower &&
            status == 'accepted' &&
            (paymentStatus.isEmpty || paymentStatus == 'unpaid');
        if (needsPaymentReminder) {
          entries.add({
            'id': 'payment-$requestId-${createdAt ?? ''}',
            'type': 'Reminders',
            'title': 'Payment required',
            'message':
                '$itemTitle accepted. Complete payment to confirm booking.',
            'timestamp': createdAt,
            'icon': Icons.payment,
            'iconBg': const Color(0xFFE3F2FD),
            'action': 'request',
            'payload': req,
          });
        }

        final needsHandoverReminder =
            isOwner &&
            status == 'accepted' &&
            (paymentStatus == 'paid' || paymentStatus == 'settled');
        if (needsHandoverReminder) {
          entries.add({
            'id': 'handover-next-$requestId-${paymentEventAt ?? ''}',
            'type': 'Reminders',
            'title': 'Payment received',
            'message': '$itemTitle is paid. Please proceed with handover.',
            'timestamp': paymentEventAt,
            'icon': Icons.payments_outlined,
            'iconBg': const Color(0xFFE8F5E9),
            'action': 'request',
            'payload': req,
          });
        }

        if (isBorrower && status == 'handover') {
          entries.add({
            'id': 'handover-ready-$requestId-${createdAt ?? ''}',
            'type': 'Reminders',
            'title': 'Handover confirmed',
            'message':
                '$itemTitle handover confirmed by lender. Please confirm receipt.',
            'timestamp': createdAt,
            'icon': Icons.handshake_outlined,
            'iconBg': const Color(0xFFE3F2FD),
            'action': 'request',
            'payload': req,
          });
        }

        if (isOwner && status == 'in_use') {
          entries.add({
            'id': 'handover-ack-$requestId-${createdAt ?? ''}',
            'type': 'Reminders',
            'title': 'Borrower confirmed handover',
            'message': '$itemTitle is now in use.',
            'timestamp': createdAt,
            'icon': Icons.verified_outlined,
            'iconBg': const Color(0xFFE8F5E9),
            'action': 'request',
            'payload': req,
          });
        }

        final end = endDate == null
            ? null
            : DateTime.tryParse(endDate)?.toLocal();
        final activeBorrowingStatus =
            status == 'in_use' || status == 'return_pending';
        if (activeBorrowingStatus && end != null && (isBorrower || isOwner)) {
          final daysLeft = DateTime(end.year, end.month, end.day)
              .difference(
                DateTime(
                  DateTime.now().year,
                  DateTime.now().month,
                  DateTime.now().day,
                ),
              )
              .inDays;
          if (daysLeft <= 2) {
            final dueDate = end.toIso8601String().split('T').first;
            final reminderTitle = daysLeft < 0
                ? 'Return overdue'
                : 'Return reminder';
            final reminderText = daysLeft < 0
                ? '$itemTitle was due on $dueDate'
                : '$itemTitle due by $dueDate';

            entries.add({
              'id': 'reminder-$requestId-$dueDate',
              'type': 'Reminders',
              'title': reminderTitle,
              'message': reminderText,
              'timestamp': end.toIso8601String(),
              'icon': Icons.access_time,
              'iconBg': Colors.grey[100],
              'action': 'request',
              'payload': req,
            });
          }
        }

        if (status == 'completed' && isBorrower) {
          entries.add({
            'id': 'completed-review-$requestId-${createdAt ?? ''}',
            'type': 'Reminders',
            'title': 'Order completed',
            'message': '$itemTitle completed. You can now leave a review.',
            'timestamp': createdAt,
            'icon': Icons.star_border,
            'iconBg': const Color(0xFFE6F4F2),
            'action': 'request',
            'payload': req,
          });
        }
      }

      for (final chat in chats) {
        final chatId = _toInt(chat['id']);
        if (chatId == null) continue;

        final unread = _toInt(chat['unread_count']) ?? 0;
        final lastMessageAt =
            chat['last_message_at']?.toString() ??
            chat['created_at']?.toString();
        final peerName = (chat['peer_name'] ?? 'User').toString();
        final preview = _buildChatPreview(chat);

        // Messages notifications should only appear for unread incoming messages.
        if (unread <= 0) continue;

        entries.add({
          'id': 'chat-$chatId-${lastMessageAt ?? ''}',
          'type': 'Messages',
          'title': unread > 0 ? 'New message' : 'Chat update',
          'message':
              '$peerName - ${preview.isEmpty ? 'Tap to open chat' : preview}',
          'timestamp': lastMessageAt,
          'icon': Icons.chat_bubble_outline,
          'iconBg': const Color(0xFFE8F5E9),
          'action': 'chat',
          'payload': chat,
        });
      }

      for (final review in reviews) {
        final reviewId = _toInt(review['id']);
        if (reviewId == null) continue;
        final reviewerRole = (review['reviewer_role'] ?? '')
            .toString()
            .toLowerCase()
            .trim();
        if (reviewerRole != 'borrower') continue;

        final reviewerName = (review['reviewer_name'] ?? 'Borrower').toString();
        final itemTitle = (review['item_title'] ?? 'your item').toString();
        final rating = _toNum(review['rating'])?.toStringAsFixed(1) ?? '5.0';
        final createdAt = review['created_at']?.toString();

        entries.add({
          'id': 'review-received-$reviewId',
          'type': 'Reminders',
          'title': 'New review received',
          'message':
              '$reviewerName reviewed you for $itemTitle ($rating★). Tap to view profile.',
          'timestamp': createdAt,
          'icon': Icons.rate_review_outlined,
          'iconBg': const Color(0xFFE8F5E9),
          'iconColor': const Color(0xFF1B7F3A),
          'action': 'profile',
        });
      }

      for (final system in systemNotifs) {
        final notifId = _toInt(system['id']);
        if (notifId == null) continue;

        final title = (system['title'] ?? 'System update').toString();
        final message = (system['message'] ?? '').toString();
        final action = (system['action'] ?? 'none').toString();
        final createdAt = system['created_at']?.toString();
        final payload = system['payload'];

        entries.add({
          'id': 'system-$notifId',
          'type': 'Reminders',
          'title': title,
          'message': message,
          'timestamp': createdAt,
          'icon': Icons.admin_panel_settings_outlined,
          'iconBg': const Color(0xFFFFF3E0),
          'iconColor': const Color(0xFFB45309),
          'action': action,
          'payload': payload,
        });
      }

      final kycStatus = (kyc['kyc_status'] ?? '')
          .toString()
          .toLowerCase()
          .trim();
      final kycUserId = userId ?? 0;
      if (kycStatus == 'rejected') {
        final kycTimestamp = await _getKycReminderTimestamp(userId, 'rejected');
        entries.add({
          'id': 'kyc-rejected-$kycUserId',
          'type': 'Reminders',
          'title': 'KYC needs attention',
          'message': 'Your KYC was rejected. Update and submit again.',
          'timestamp': kycTimestamp,
          'icon': Icons.verified_user_outlined,
          'iconBg': const Color(0xFFE3F2FD),
          'action': 'kyc',
        });
      } else if (kycStatus == 'unverified' || kycStatus.isEmpty) {
        final kycTimestamp = await _getKycReminderTimestamp(userId, 'unverified');
        entries.add({
          'id': 'kyc-complete-$kycUserId',
          'type': 'Reminders',
          'title': 'Complete KYC',
          'message': 'Verify identity to unlock full platform trust.',
          'timestamp': kycTimestamp,
          'icon': Icons.verified_user_outlined,
          'iconBg': const Color(0xFFE3F2FD),
          'action': 'kyc',
        });
      }

      entries.sort((a, b) {
        final fallback = DateTime.fromMillisecondsSinceEpoch(0);
        final aTime =
            DateTime.tryParse(a['timestamp']?.toString() ?? '') ?? fallback;
        final bTime =
            DateTime.tryParse(b['timestamp']?.toString() ?? '') ?? fallback;
        return bTime.compareTo(aTime);
      });

      final visibleEntries = entries
          .where((e) => !_dismissedIds.contains((e['id'] ?? '').toString()))
          .where((e) => !_isClearedByTimestamp(e['timestamp']?.toString()))
          .toList();

      if (!mounted) return;
      setState(() {
        _currentUserId = userId;
        _currentUserName = (storedUser?['name'] ?? _currentUserName).toString();
        _notifications = visibleEntries;
        _loading = false;
        _refreshing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _refreshing = false;
      });
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load notifications: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  String _dismissedStorageKey(int? userId) =>
      'alerts.dismissed.user.${userId ?? 0}';

  String _clearedAtStorageKey(int? userId) =>
      'alerts.cleared_at.user.${userId ?? 0}';

    String _kycReminderTimestampKey(int? userId, String status) =>
      'alerts.kyc.reminder.ts.${status}.user.${userId ?? 0}';

  Future<void> _ensureDismissedLoaded(int? userId) async {
    if (_dismissedLoaded && _dismissedUserId == userId) return;
    final prefs = await SharedPreferences.getInstance();
    final userValues =
        prefs.getStringList(_dismissedStorageKey(userId)) ?? const <String>[];
    final globalValues =
        prefs.getStringList(_dismissedGlobalKey) ?? const <String>[];
    final values = <String>{...userValues, ...globalValues}.toList();

    final clearedAtRaw = prefs.getString(_clearedAtStorageKey(userId));
    final clearedAtGlobalRaw = prefs.getString(_clearedAtGlobalKey);
    final userClearedAt = clearedAtRaw == null || clearedAtRaw.isEmpty
        ? null
        : DateTime.tryParse(clearedAtRaw)?.toLocal();
    final globalClearedAt =
        clearedAtGlobalRaw == null || clearedAtGlobalRaw.isEmpty
        ? null
        : DateTime.tryParse(clearedAtGlobalRaw)?.toLocal();

    _dismissedIds
      ..clear()
      ..addAll(values.where((id) => id.trim().isNotEmpty));
    if (userClearedAt == null) {
      _clearedAt = globalClearedAt;
    } else if (globalClearedAt == null) {
      _clearedAt = userClearedAt;
    } else {
      _clearedAt = userClearedAt.isAfter(globalClearedAt)
          ? userClearedAt
          : globalClearedAt;
    }
    _dismissedLoaded = true;
    _dismissedUserId = userId;
  }

  Future<void> _persistDismissedIds() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = _dismissedIds.toList();

    await prefs.setStringList(
      _dismissedStorageKey(_dismissedUserId ?? _currentUserId),
      ids,
    );
    await prefs.setStringList(_dismissedGlobalKey, ids);

    final cleared = _clearedAt;
    if (cleared == null) {
      await prefs.remove(
        _clearedAtStorageKey(_dismissedUserId ?? _currentUserId),
      );
      await prefs.remove(_clearedAtGlobalKey);
    } else {
      final clearedUtc = cleared.toUtc().toIso8601String();
      await prefs.setString(
        _clearedAtStorageKey(_dismissedUserId ?? _currentUserId),
        clearedUtc,
      );
      await prefs.setString(_clearedAtGlobalKey, clearedUtc);
    }
  }

  Future<String> _getKycReminderTimestamp(int? userId, String status) async {
    if (userId == null) return DateTime.now().toIso8601String();
    final prefs = await SharedPreferences.getInstance();
    final key = _kycReminderTimestampKey(userId, status);
    final existing = prefs.getString(key);
    if (existing != null && existing.isNotEmpty) return existing;
    final now = DateTime.now().toIso8601String();
    await prefs.setString(key, now);
    return now;
  }

  bool _isClearedByTimestamp(String? rawTimestamp) {
    final cleared = _clearedAt;
    if (cleared == null) return false;
    final ts = DateTime.tryParse(rawTimestamp ?? '')?.toLocal();
    if (ts == null) return false;
    return !ts.isAfter(cleared);
  }

  int? _toInt(dynamic value) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  num? _toNum(dynamic value) {
    if (value is num) return value;
    if (value is String) return num.tryParse(value);
    return null;
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'pending':
        return 'Pending';
      case 'accepted':
        return 'Accepted';
      case 'handover':
      case 'handover_pending':
        return 'Handover pending';
      case 'in_use':
        return 'In use';
      case 'return_pending':
        return 'Return pending';
      case 'completed':
        return 'Completed';
      case 'rejected':
        return 'Rejected';
      case 'cancelled':
        return 'Cancelled';
      default:
        return status.isEmpty ? 'Update' : status;
    }
  }

  String _buildChatPreview(Map<String, dynamic> chat) {
    final type = (chat['last_message_type'] ?? 'text').toString();
    final raw = (chat['last_message'] ?? '').toString().trim();
    if (type == 'image') return '[Photo]';
    if (type == 'video') return '[Video]';
    return raw;
  }

  OrderStatus _mapOrderStatus(String status, {String? paymentStatus}) {
    final normalized = status.toLowerCase();
    if (normalized == 'pending') return OrderStatus.pending;
    if (normalized == 'accepted' || normalized == 'approved') {
      return OrderStatus.approved;
    }
    if (normalized == 'rejected' || normalized == 'cancelled') {
      return OrderStatus.rejected;
    }
    if (normalized == 'paid' || paymentStatus == 'paid') {
      return OrderStatus.paid;
    }
    if (normalized == 'handover' || normalized == 'handover_pending') {
      return OrderStatus.handoverPending;
    }
    if (normalized == 'in_use') return OrderStatus.active;
    if (normalized == 'return_pending') return OrderStatus.returnPending;
    if (normalized == 'completed') return OrderStatus.completed;
    return OrderStatus.pending;
  }

  String _formatPeriodModern(String? rawStart, String? rawEnd) {
    final start = DateTime.tryParse((rawStart ?? '').toString())?.toLocal();
    final end = DateTime.tryParse((rawEnd ?? '').toString())?.toLocal();
    if (start == null || end == null) {
      return '${rawStart ?? '-'} - ${rawEnd ?? '-'}';
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

  Future<void> _openRequestNotification(Map<String, dynamic> req) async {
    final requestId = _toInt(req['id']);
    final lenderId = _toInt(req['owner_id']);
    final borrowerId = _toInt(req['borrower_id']);
    final itemId = _toInt(req['item_id']);
    final isLender = _currentUserId != null && _currentUserId == lenderId;
    final itemTitle = (req['item_title'] ?? 'Item').toString();
    final itemImageUrl = (req['item_image_url'] ?? req['image_url'])
        ?.toString();
    final statusStr = (req['status'] ?? 'pending').toString();
    final paymentStatus = req['payment_status']?.toString();

    if (isLender) {
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => BorrowRequestsListPage(
            filterItemId: itemId,
            filterItemTitle: itemTitle,
          ),
        ),
      );
      await _refreshNotifications(silent: true);
      return;
    }

    final num? priceValue =
        _toNum(req['total_amount']) ?? _toNum(req['price_per_day']);
    final priceText = priceValue != null
        ? 'RM ${priceValue.toStringAsFixed(2)}'
        : 'RM -';

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => OrderDetailPage(
          requestId: requestId,
          lenderId: lenderId,
          borrowerId: borrowerId,
          itemId: itemId,
          itemName: itemTitle,
          itemImageUrl: itemImageUrl,
          lenderName: (req['owner_name'] ?? 'Lender').toString(),
          borrowerName: (req['borrower_name'] ?? 'Borrower').toString(),
          dates: _formatPeriodModern(
            req['start_date']?.toString(),
            req['end_date']?.toString(),
          ),
          price: priceText,
          status: _mapOrderStatus(statusStr, paymentStatus: paymentStatus),
          statusLabel: statusStr,
          paymentStatus: paymentStatus,
          isLender: isLender,
        ),
      ),
    );
    await _refreshNotifications(silent: true);
  }

  Future<void> _openChatNotification(Map<String, dynamic> chat) async {
    final chatId = _toInt(chat['id']);
    if (chatId == null || !mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatConversationPage(
          chatId: chatId,
          peerName: (chat['peer_name'] ?? 'User').toString(),
          peerRating: '5.0',
          peerUserId: _toInt(chat['peer_user_id']),
          peerAvatarUrl: chat['peer_avatar_url']?.toString(),
        ),
      ),
    );
    await _refreshNotifications(silent: true);
  }

  Future<void> _openNotification(Map<String, dynamic> notif) async {
    try {
      final action = (notif['action'] ?? '').toString();
      final payload = notif['payload'];
      if (action == 'request' && payload is Map<String, dynamic>) {
        await _openRequestNotification(payload);
        return;
      }
      if (action == 'chat' && payload is Map<String, dynamic>) {
        await _openChatNotification(payload);
        return;
      }
      if (action == 'kyc' && mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const KYCVerificationPage()),
        );
        await _refreshNotifications(silent: true);
        return;
      }
      if (action == 'profile' && mounted) {
        final userId = _currentUserId;
        if (userId == null) return;
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => UserProfilePage(
              title: 'User Profile',
              displayName: _currentUserName,
              userId: userId,
            ),
          ),
        );
        await _refreshNotifications(silent: true);
        return;
      }
      if (action == 'listing_removed' && mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MyListingsPage()),
        );
        await _refreshNotifications(silent: true);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Cannot open notification: $e')));
    }
  }

  Future<void> _dismissNotification(Map<String, dynamic> notif) async {
    final id = (notif['id'] ?? '').toString();
    if (id.isEmpty) return;
    setState(() {
      _dismissedIds.add(id);
      _notifications.removeWhere((n) => (n['id'] ?? '').toString() == id);
    });
    await _persistDismissedIds();
  }

  Future<void> _clearAllNotifications() async {
    if (_loading) return;

    final removedCount = _notifications.length;
    if (removedCount == 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No notifications to clear.')),
      );
      return;
    }

    setState(() {
      _dismissedIds.addAll(
        _notifications.map((n) => (n['id'] ?? '').toString()),
      );
      _clearedAt = DateTime.now();
      _notifications = [];
    });
    await _persistDismissedIds();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Clear all successful ($removedCount).')),
    );
  }

  List<Map<String, dynamic>> get _filteredNotifications {
    if (selectedTabIndex == 0) return _notifications;
    final type = tabs[selectedTabIndex];
    return _notifications.where((n) => n['type'] == type).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Notifications',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        _notifications.isEmpty
                            ? 'No unread'
                            : '${_notifications.length} updates',
                        style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                  GestureDetector(
                    onTap: _clearAllNotifications,
                    child: Text(
                      'Clear all',
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(
              height: 36,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: tabs.length,
                itemBuilder: (context, index) {
                  final isSelected = selectedTabIndex == index;
                  return GestureDetector(
                    onTap: () => setState(() => selectedTabIndex = index),
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.grey[900] : Colors.grey[100],
                        borderRadius: BorderRadius.circular(18),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        tabs[index],
                        style: TextStyle(
                          fontSize: 13,
                          color: isSelected ? Colors.white : Colors.grey[700],
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 16),

            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: () => _refreshNotifications(silent: true),
                      child: _filteredNotifications.isEmpty
                          ? ListView(
                              children: const [
                                SizedBox(height: 120),
                                Center(child: Text('No notifications yet.')),
                              ],
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              itemCount: _filteredNotifications.length,
                              itemBuilder: (context, index) {
                                final notif = _filteredNotifications[index];
                                return InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () => _openNotification(notif),
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: Colors.grey[50],
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: Colors.grey[200]!,
                                      ),
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          width: 44,
                                          height: 44,
                                          decoration: BoxDecoration(
                                            color:
                                                (notif['iconBg'] as Color?) ??
                                                Colors.grey[100],
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          child: Icon(
                                            notif['icon'] as IconData? ??
                                                Icons.notifications,
                                            color:
                                                (notif['iconColor']
                                                    as Color?) ??
                                                const Color(0xFF0F766E),
                                            size: 22,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                (notif['title'] ?? 'Update')
                                                    .toString(),
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 15,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                (notif['message'] ?? '')
                                                    .toString(),
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: Colors.grey[600],
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              Text(
                                                _formatRelativeTime(
                                                  notif['timestamp']
                                                      ?.toString(),
                                                ),
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey[400],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Column(
                                          children: [
                                            IconButton(
                                              visualDensity:
                                                  VisualDensity.compact,
                                              onPressed: () async {
                                                await _dismissNotification(
                                                  notif,
                                                );
                                              },
                                              icon: Icon(
                                                Icons.close,
                                                size: 18,
                                                color: Colors.grey[500],
                                              ),
                                            ),
                                            Icon(
                                              Icons.chevron_right,
                                              size: 18,
                                              color: Colors.grey[400],
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
            ),
          ],
        ),
      ),
    );
  }

  Map<String, Object> _requestStatusVisual(String status) {
    final normalized = status.toLowerCase();
    if (normalized == 'completed') {
      return {
        'icon': Icons.check_circle_outline,
        'iconBg': const Color(0xFFE8F5E9),
        'iconColor': const Color(0xFF1B7F3A),
      };
    }
    if (normalized == 'cancelled' || normalized == 'rejected') {
      return {
        'icon': Icons.cancel_outlined,
        'iconBg': const Color(0xFFFFEBEE),
        'iconColor': const Color(0xFFC62828),
      };
    }
    return {
      'icon': Icons.swap_horiz,
      'iconBg': const Color(0xFFE6F4F2),
      'iconColor': const Color(0xFF0F766E),
    };
  }

  String _formatRelativeTime(String? timestamp) {
    if (timestamp == null || timestamp.isEmpty) return 'Just now';
    try {
      final dt = DateTime.tryParse(timestamp)?.toLocal();
      if (dt == null) return 'Just now';
      final now = DateTime.now();
      if (dt.isAfter(now)) {
        final ahead = dt.difference(now);
        if (ahead.inSeconds < 5) return 'Just now';
        if (ahead.inSeconds < 60) return 'in ${ahead.inSeconds}s';
        if (ahead.inMinutes < 60) return 'in ${ahead.inMinutes}m';
        if (ahead.inHours < 24) return 'in ${ahead.inHours}h';
        return 'in ${ahead.inDays}d';
      }

      final diff = now.difference(dt);
      if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (_) {
      return 'Just now';
    }
  }
}
