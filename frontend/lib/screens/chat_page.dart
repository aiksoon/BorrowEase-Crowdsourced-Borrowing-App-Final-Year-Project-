import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../services/api.dart';
import '../services/api_client.dart' show defaultBaseUrl;
import 'screens.dart';

// ==================== CHAT PAGE (List) ====================
class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  static const Color _ecoTeal = Color(0xFF0D9488);

  bool _loading = true;
  bool _deleting = false;
  bool _polling = false;
  List<Map<String, dynamic>> _chats = [];
  int _chatListVersion = 0;
  String _chatSignature = '';
  final Set<int> _selectedChatIds = <int>{};
  Timer? _poller;

  bool get _isSelectionMode => _selectedChatIds.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _loadChats();
    _startPolling();
  }

  @override
  void dispose() {
    _poller?.cancel();
    super.dispose();
  }

  void _startPolling() {
    _poller?.cancel();
    _poller = Timer.periodic(const Duration(seconds: 3), (_) {
      _loadChats(silent: true);
    });
  }

  Future<void> _loadChats({bool silent = false}) async {
    if (_polling || _deleting) return;
    _polling = true;
    try {
      final results = await api.getChats();
      if (!mounted) return;
      final mapped = results.cast<Map<String, dynamic>>();
      final deduped = _dedupeChats(mapped);
      final signature = _chatListSignature(deduped);

      setState(() {
        _chats = deduped;
        if (_chatSignature != signature) {
          _chatSignature = signature;
          _chatListVersion++;
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load chats: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } finally {
      _polling = false;
    }
  }

  List<Map<String, dynamic>> _dedupeChats(List<Map<String, dynamic>> chats) {
    final ordered = [...chats]
      ..sort((a, b) {
        final aTime = _activityTime(a);
        final bTime = _activityTime(b);
        return bTime.compareTo(aTime);
      });

    final byKey = <String, Map<String, dynamic>>{};
    for (final chat in ordered) {
      final key = _chatKey(chat);
      final existing = byKey[key];
      if (existing == null) {
        byKey[key] = Map<String, dynamic>.from(chat);
        continue;
      }

      final existingUnread = _toInt(existing['unread_count']) ?? 0;
      final currentUnread = _toInt(chat['unread_count']) ?? 0;
      existing['unread_count'] = existingUnread + currentUnread;

      final existingHasPreview =
          (existing['last_message'] ?? '').toString().trim().isNotEmpty;
      final currentHasPreview =
          (chat['last_message'] ?? '').toString().trim().isNotEmpty;
      if (!existingHasPreview && currentHasPreview) {
        existing['last_message'] = chat['last_message'];
        existing['last_message_type'] = chat['last_message_type'];
        existing['last_message_at'] = chat['last_message_at'] ?? chat['created_at'];
      }
    }

    final deduped = byKey.values.toList()
      ..sort((a, b) {
        final aUnread = _toInt(a['unread_count']) ?? 0;
        final bUnread = _toInt(b['unread_count']) ?? 0;
        if (aUnread != bUnread) {
          return bUnread.compareTo(aUnread);
        }
        return _activityTime(b).compareTo(_activityTime(a));
      });
    return deduped;
  }

  String _chatListSignature(List<Map<String, dynamic>> chats) {
    return chats
        .map((c) {
          final id = _toInt(c['id']) ?? -1;
          final unread = _toInt(c['unread_count']) ?? 0;
          final t = _activityTime(c);
          return '$id:$unread:$t';
        })
        .join('|');
  }

  String _chatKey(Map<String, dynamic> chat) {
    final peerId = _toInt(chat['peer_user_id']);
    if (peerId == null) {
      return 'chat-${chat['id']}';
    }
    return 'peer-$peerId';
  }

  int _activityTime(Map<String, dynamic> chat) {
    final raw = (chat['last_message_at'] ?? chat['created_at'])?.toString();
    return DateTime.tryParse(raw ?? '')?.toLocal().millisecondsSinceEpoch ?? 0;
  }

  void _toggleSelection(int chatId) {
    setState(() {
      if (_selectedChatIds.contains(chatId)) {
        _selectedChatIds.remove(chatId);
      } else {
        _selectedChatIds.add(chatId);
      }
    });
  }

  void _clearSelection() {
    if (_selectedChatIds.isEmpty) return;
    setState(_selectedChatIds.clear);
  }

  Future<void> _deleteSelectedChats() async {
    if (_selectedChatIds.isEmpty || _deleting) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete selected chats?'),
        content: Text(
          'This will delete ${_selectedChatIds.length} chat(s) and their messages.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    setState(() => _deleting = true);
    try {
      for (final chatId in _selectedChatIds.toList()) {
        await api.deleteChat(chatId);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selected chats deleted')),
      );
      _clearSelection();
      await _loadChats();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  String _buildPreviewText(Map<String, dynamic> chat, String fallback) {
    final type = (chat['last_message_type'] ?? 'text').toString();
    if (fallback.isEmpty) return fallback;
    if (type == 'image') return '[Photo]';
    if (type == 'video') return '[Video]';
    return fallback;
  }

  String? _resolveMediaUrl(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final value = raw.trim();
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    if (value.startsWith('/')) return '$defaultBaseUrl$value';
    return '$defaultBaseUrl/$value';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: _isSelectionMode,
        leading: _isSelectionMode
            ? IconButton(
                onPressed: _clearSelection,
                icon: const Icon(Icons.close),
              )
            : null,
        title: Text(
          _isSelectionMode ? '${_selectedChatIds.length} selected' : 'Messages',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: _isSelectionMode
            ? [
                IconButton(
                  onPressed: _deleting ? null : _deleteSelectedChats,
                  icon: _deleting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delete_outline, color: Colors.red),
                ),
              ]
            : null,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadChats,
              child: _chats.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 120),
                        Center(
                          child: Text(
                            'No chats yet. Start a conversation from an item page.',
                          ),
                        ),
                      ],
                    )
                  : _buildChatListView(),
            ),
    );
  }

  Widget _buildChatListView() {
    final list = ListView.builder(
      key: ValueKey('chat-list-$_chatListVersion'),
      itemCount: _chats.length,
      itemBuilder: (context, index) {
        final chat = _chats[index];
        final chatId = _toInt(chat['id']);
        final peerName = (chat['peer_name'] ?? 'User').toString();
        final peerUserId = _toInt(chat['peer_user_id']);
        final peerAvatarUrl = _resolveMediaUrl(chat['peer_avatar_url']?.toString());
        final itemTitle = (chat['item_title'] ?? 'Item').toString();
        final status = (chat['request_status'] ?? '').toString();
        final createdAt =
            (chat['last_message_at'] ?? chat['created_at'])?.toString();
        final rawLastMessage = (chat['last_message'] ?? '').toString().trim();
        final lastMessage = _buildPreviewText(chat, rawLastMessage);
        final unreadCount = _toInt(chat['unread_count']) ?? 0;
        final isSelected = chatId != null && _selectedChatIds.contains(chatId);
        final statusLabel = status.isEmpty ? 'Direct chat' : 'Status: $status';
        final relativeTime = _formatRelativeTime(createdAt);
        final isOnline = _isOnline(chat);

        return ListTile(
          onTap: () {
            if (chatId == null) return;
            if (_isSelectionMode) {
              _toggleSelection(chatId);
              return;
            }
            _openChat(chat, peerName, peerUserId, peerAvatarUrl);
          },
          onLongPress: () {
            if (chatId == null) return;
            _toggleSelection(chatId);
          },
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: _isSelectionMode
              ? Icon(
                  isSelected
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  color: isSelected
                      ? const Color(0xFF0F766E)
                      : Colors.grey[400],
                )
              : SizedBox(
                  width: 50,
                  height: 50,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: _ecoTeal.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                          image: peerAvatarUrl != null
                              ? DecorationImage(
                                  image: NetworkImage(peerAvatarUrl),
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        alignment: Alignment.center,
                        child: peerAvatarUrl == null
                            ? Text(
                                _avatarInitial(peerName),
                                style: const TextStyle(
                                  color: _ecoTeal,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 18,
                                ),
                              )
                            : null,
                      ),
                      if (isOnline)
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: const Color(0xFF22C55E),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
          title: Text(
            peerName,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                itemTitle,
                style: const TextStyle(fontSize: 13, color: Colors.black87),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                lastMessage.isNotEmpty ? lastMessage : statusLabel,
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
            ],
          ),
          trailing: _isSelectionMode
              ? null
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      relativeTime,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[500],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (unreadCount > 0)
                          Container(
                            constraints: const BoxConstraints(minWidth: 20),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              unreadCount > 99 ? '99+' : '$unreadCount',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        if (unreadCount > 0) const SizedBox(width: 8),
                        const Icon(Icons.chevron_right, color: Colors.grey, size: 18),
                      ],
                    ),
                  ],
                ),
        );
      },
    );

    if (!kIsWeb) return list;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: list,
    );
  }

  bool _isOnline(Map<String, dynamic> chat) {
    final raw = (chat['last_message_at'] ?? chat['created_at'])?.toString();
    final dt = DateTime.tryParse(raw ?? '')?.toLocal();
    if (dt == null) return false;
    final diff = DateTime.now().difference(dt);
    return diff.inMinutes <= 5;
  }

  String _avatarInitial(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    final match = RegExp(r'[A-Za-z0-9]').firstMatch(trimmed);
    if (match != null) {
      return (match.group(0) ?? '?').toUpperCase();
    }
    return trimmed.characters.first.toUpperCase();
  }

  Future<void> _openChat(
    Map<String, dynamic> chat,
    String peerName,
    int? peerUserId,
    String? peerAvatarUrl,
  ) async {
    final chatId = _toInt(chat['id']);
    if (chatId == null) return;

    try {
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatConversationPage(
            chatId: chatId,
            peerName: peerName,
            peerRating: '5.0',
            peerUserId: peerUserId,
            peerAvatarUrl: peerAvatarUrl,
          ),
        ),
      );
      if (!mounted) return;
      await _loadChats();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to open chat: $e'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  String _formatRelativeTime(String? timestamp) {
    if (timestamp == null || timestamp.isEmpty) return 'Just now';
    try {
      final dt = DateTime.tryParse(timestamp)?.toLocal();
      if (dt == null) return 'Just now';
      final diff = DateTime.now().difference(dt);
      if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (_) {
      return 'Just now';
    }
  }

  int? _toInt(dynamic value) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}
