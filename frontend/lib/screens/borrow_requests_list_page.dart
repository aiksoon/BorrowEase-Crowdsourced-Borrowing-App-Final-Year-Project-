import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:dio/dio.dart';
import '../services/api.dart';
import '../services/api_client.dart' show defaultBaseUrl;
import 'screens.dart';

class BorrowRequestsListPage extends StatefulWidget {
  final int? filterItemId;
  final String? filterItemTitle;

  const BorrowRequestsListPage({
    super.key,
    this.filterItemId,
    this.filterItemTitle,
  });

  @override
  State<BorrowRequestsListPage> createState() => _BorrowRequestsListPageState();
}

class _BorrowRequestsListPageState extends State<BorrowRequestsListPage> {
  List<dynamic> _requests = <dynamic>[];
  bool _loadingRequests = true;
  String? _loadError;
  int? _userId;
  bool _loadingUser = true;
  int? _updatingId;
  Timer? _autoRefreshTimer;
  bool _polling = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    _loadUser();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadUser() async {
    final user = await api.getStoredUser();
    if (!mounted) return;
    setState(() {
      _userId = (user?['id'] as num?)?.toInt();
      _loadingUser = false;
    });
  }

  int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  Future<void> _refresh({bool silent = false}) async {
    if (_polling) return;
    _polling = true;
    try {
      final latest = await api.getRequests(role: 'owner');
      if (!mounted) return;
      setState(() {
        _requests = latest;
        _loadError = null;
        _loadingRequests = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (!silent) {
        setState(() {
          _loadError = _friendlyError(e);
          _loadingRequests = false;
        });
      }
    } finally {
      _polling = false;
    }
  }

  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      _refreshSilently();
    });
  }

  Future<void> _refreshSilently() async {
    if (!mounted || _loadingUser || _updatingId != null || _polling) return;
    await _refresh(silent: true);
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

  Future<void> _updateStatus(int requestId, String nextStatus) async {
    setState(() {
      _updatingId = requestId;
    });
    try {
      final res = await api.updateRequestStatus(
        requestId: requestId,
        nextStatus: nextStatus,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Status updated to ${res['status'] ?? nextStatus}'),
        ),
      );
      await _refresh(silent: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Update failed: ${_friendlyError(e)}')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _updatingId = null;
        });
      }
    }
  }

  String _friendlyError(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['message'] != null) {
        return data['message'].toString();
      }
      if (error.message != null && error.message!.trim().isNotEmpty) {
        return error.message!.trim();
      }
      return 'Network request failed';
    }
    return error.toString();
  }

  bool _isBusyFor(int id) => _updatingId == id;

  Future<Map<String, dynamic>?> _findReusableChat({
    int? requestId,
    int? peerUserId,
  }) async {
    final chats = await api.getChats();
    Map<String, dynamic>? requestChat;
    Map<String, dynamic>? latestPeerChat;
    int latestPeerTs = -1;

    for (final raw in chats) {
      if (raw is! Map<String, dynamic>) continue;
      if (_toInt(raw['id']) == null) continue;

      final chatRequestId = _toInt(raw['request_id']);
      if (requestId != null && chatRequestId == requestId) {
        requestChat = raw;
      }

      final chatPeerId = _toInt(raw['peer_user_id']);
      if (peerUserId != null && chatPeerId == peerUserId) {
        final timeRaw = (raw['last_message_at'] ?? raw['created_at'])?.toString();
        final ts = DateTime.tryParse(timeRaw ?? '')?.millisecondsSinceEpoch ?? 0;
        if (ts >= latestPeerTs) {
          latestPeerTs = ts;
          latestPeerChat = raw;
        }
      }
    }

    return latestPeerChat ?? requestChat;
  }

  Future<void> _openChat(Map<String, dynamic> req) async {
    final int? requestId = _toInt(req['id']);
    if (requestId == null) return;
    final String borrower = req['borrower_name']?.toString() ?? 'Borrower';
    final String owner = req['owner_name']?.toString() ?? 'Owner';
    final bool isOwner = _userId != null && _toInt(req['owner_id']) == _userId;
    final String peerName = isOwner ? borrower : owner;
    final int? peerUserId = isOwner
        ? _toInt(req['borrower_id'])
        : _toInt(req['owner_id']);
    try {
      Map<String, dynamic>? chat = await _findReusableChat(
        requestId: requestId,
        peerUserId: peerUserId,
      );

      if (chat == null && peerUserId != null) {
        chat = await api.getOrCreateDirectChat(peerUserId: peerUserId);
      }

      chat ??= await api.createChat(requestId);

      if (!mounted) return;
      final chatId = _toInt(chat['id']);
      if (chatId == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Chat not available')));
        return;
      }
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => ChatConversationPage(
            chatId: chatId,
            peerName: peerName,
            peerRating: '4.8',
            peerUserId: peerUserId,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Open chat failed: $e')));
    }
  }

  Future<void> _handleAction(Map<String, dynamic> req, _Action action) async {
    final id = _toInt(req['id']);
    if (id == null) return;
    switch (action.type) {
      case _ActionType.status:
        if (action.next != null) {
          await _updateStatus(id, action.next!);
        }
        break;
      case _ActionType.pay:
        final itemTitle = req['item_title']?.toString() ?? 'Item';
        final itemImageUrl = _resolveMediaUrl(
          req['item_image_url'] ?? req['image_url'],
        );
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => PaymentPage(
              requestId: id,
              itemName: itemTitle,
              itemImageUrl: itemImageUrl,
            ),
          ),
        );
        await _refresh(silent: true);
        break;
      case _ActionType.chat:
        await _openChat(req);
        break;
      case _ActionType.handoverFlow:
        final itemTitle = req['item_title']?.toString() ?? 'Item';
        final itemImageUrl = _resolveMediaUrl(
          req['item_image_url'] ?? req['image_url'],
        );
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => HandoverPage(
              itemName: itemTitle,
              itemImageUrl: itemImageUrl,
              isPickup: action.isPickupFlow ?? true,
              isLender: true,
              requestId: id,
              onConfirmed: () => _refresh(silent: true),
            ),
          ),
        );
        await _refresh(silent: true);
        break;
    }
  }

  List<_Action> _actionsFor(Map<String, dynamic> req) {
    final status = req['status']?.toString() ?? '';
    final int? borrowerId = _toInt(req['borrower_id']);
    final int? ownerId = _toInt(req['owner_id']);
    final bool isOwner = _userId != null && ownerId == _userId;
    final bool isBorrower = _userId != null && borrowerId == _userId;

    final List<_Action> base = [];
    if (isOwner || isBorrower) {
      base.add(const _Action(label: 'Chat', type: _ActionType.chat));
    }

    switch (status) {
      case 'pending':
        if (isOwner) {
          return [
            ...base,
            const _Action(label: 'Accept', next: 'accepted'),
            const _Action(label: 'Reject', next: 'rejected'),
          ];
        }
        break;
      case 'accepted':
        if (isOwner) {
          final paymentStatus = (req['payment_status'] ?? '')
              .toString()
              .toLowerCase();
          final canConfirmHandover =
              paymentStatus == 'paid' || paymentStatus == 'settled';
          return [
            ...base,
            if (!canConfirmHandover)
              const _Action(label: 'Cancel Request', next: 'cancelled'),
            _Action(
              label: 'Confirm Handover',
              type: _ActionType.handoverFlow,
              isPickupFlow: true,
              enabled: canConfirmHandover,
            ),
          ];
        }
        break;
      case 'return_pending':
        if (isOwner) {
          return [
            ...base,
            const _Action(
              label: 'Confirm Received',
              type: _ActionType.handoverFlow,
              isPickupFlow: false,
            ),
          ];
        }
        break;
      default:
        break;
    }
    return base;
  }

  @override
  Widget build(BuildContext context) {
    final hasFilter = widget.filterItemId != null;
    final title = hasFilter
        ? 'Requests for ${widget.filterItemTitle ?? 'Item #${widget.filterItemId}'}'
        : 'Requests for My Items';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: () => _refresh(silent: true),
        child: Builder(
          builder: (context) {
            if (_loadingUser || _loadingRequests) {
              return const Center(child: CircularProgressIndicator());
            }
            if (_loadError != null && _requests.isEmpty) {
              return ListView(
                children: [
                  const SizedBox(height: 200),
                  Center(child: Text('Failed to load: $_loadError')),
                ],
              );
            }
            final rawData = _requests;
            final data = hasFilter
                ? rawData.where((raw) {
                    if (raw is! Map<String, dynamic>) return false;
                    final itemId = raw['item_id'];
                    final parsed = itemId is num
                        ? itemId.toInt()
                        : int.tryParse(itemId.toString());
                    return parsed == widget.filterItemId;
                  }).toList()
                : rawData;
            if (data.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 200),
                  Center(child: Text('No requests yet')),
                ],
              );
            }
            return ListView.builder(
              itemCount: data.length,
              itemBuilder: (context, index) {
                final req = data[index] as Map<String, dynamic>;
                final requestId = _toInt(req['id']);
                final status = req['status']?.toString() ?? '';
                final itemTitle =
                    req['item_title']?.toString() ??
                    'Item #${req['item_id'] ?? ''}';
                final borrower = req['borrower_name']?.toString() ?? '-';
                final owner = req['owner_name']?.toString() ?? '-';
                final itemImageUrl = _resolveMediaUrl(
                  req['item_image_url'] ?? req['image_url'],
                );

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

                final actions = _actionsFor(req);
                return Container(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              width: 58,
                              height: 58,
                              color: Colors.grey[200],
                              child: itemImageUrl == null
                                  ? Icon(Icons.image, color: Colors.grey[500])
                                  : Image.network(
                                      itemImageUrl,
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (context, error, stackTrace) {
                                            return Icon(
                                              Icons.image,
                                              color: Colors.grey[500],
                                            );
                                          },
                                    ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  itemTitle,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Borrower: $borrower | Owner: $owner',
                                  style: TextStyle(
                                    color: Colors.grey[700],
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  dates,
                                  style: TextStyle(
                                    color: Colors.grey[700],
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(status),
                          ),
                        ],
                      ),
                      if (actions.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: actions
                                .map(
                                  (a) => SizedBox(
                                    height: 34,
                                    child: OutlinedButton(
                                      onPressed:
                                          requestId == null ||
                                              _isBusyFor(requestId) ||
                                              !a.enabled
                                          ? null
                                          : () => _handleAction(req, a),
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                        ),
                                      ),
                                      child:
                                          requestId != null &&
                                              _isBusyFor(requestId)
                                          ? const SizedBox(
                                              width: 12,
                                              height: 12,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : Text(
                                              a.label,
                                              style: const TextStyle(
                                                fontSize: 12,
                                              ),
                                            ),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      ],
                    ],
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

class _Action {
  final String label;
  final String? next;
  final _ActionType type;
  final bool? isPickupFlow;
  final bool enabled;
  const _Action({
    required this.label,
    this.next,
    this.type = _ActionType.status,
    this.isPickupFlow,
    this.enabled = true,
  });
}

enum _ActionType { status, pay, chat, handoverFlow }

