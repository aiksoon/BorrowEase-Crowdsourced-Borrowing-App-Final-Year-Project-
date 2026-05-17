import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';

import '../services/api.dart';
import '../services/api_client.dart' show defaultBaseUrl;
import '../widgets/web_inline_video_player.dart';
import 'screens.dart';

// ==================== CHAT CONVERSATION PAGE ====================
class ChatConversationPage extends StatefulWidget {
  final int chatId;
  final String peerName;
  final String peerRating;
  final int? peerUserId;
  final String? peerAvatarUrl;

  const ChatConversationPage({
    super.key,
    required this.chatId,
    required this.peerName,
    required this.peerRating,
    this.peerUserId,
    this.peerAvatarUrl,
  });

  @override
  State<ChatConversationPage> createState() => _ChatConversationPageState();
}

class _ChatConversationPageState extends State<ChatConversationPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();
  final List<Map<String, dynamic>> _messages = [];
  int? _currentUserId;
  bool _loading = true;
  bool _sendingMedia = false;
  bool _fetching = false;
  String? _peerAvatarUrl;
  Timer? _poller;

  @override
  void initState() {
    super.initState();
    _peerAvatarUrl = _resolveMediaUrl(widget.peerAvatarUrl);
    _loadUserAndMessages();
    _poller = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _fetchMessages(silent: true),
    );
  }

  @override
  void dispose() {
    _poller?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadUserAndMessages() async {
    final user = await api.getStoredUser();
    if (!mounted) return;
    setState(() {
      _currentUserId = (user?['id'] as num?)?.toInt();
    });
    await Future.wait<void>([
      _fetchMessages(),
      _loadPeerAvatarIfNeeded(),
    ]);
  }

  Future<void> _loadPeerAvatarIfNeeded() async {
    if (_peerAvatarUrl != null) return;
    try {
      final chats = await api.getChats();
      String? avatar;
      for (final raw in chats) {
        if (raw is! Map<String, dynamic>) continue;
        if (_toInt(raw['id']) != widget.chatId) continue;
        avatar = _resolveMediaUrl(raw['peer_avatar_url']?.toString());
        break;
      }
      if (!mounted || avatar == null) return;
      setState(() {
        _peerAvatarUrl = avatar;
      });
    } catch (_) {
      // Keep placeholder avatar on best-effort failure.
    }
  }

  Widget _buildPeerAvatar() {
    if (_peerAvatarUrl == null) {
      return Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: const Color(0xFF0D9488).withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Text(
          _avatarInitial(widget.peerName),
          style: const TextStyle(
            color: Color(0xFF0F766E),
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
      );
    }

    return ClipOval(
      child: Image.network(
        _peerAvatarUrl!,
        width: 40,
        height: 40,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) {
          return Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF0D9488).withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              _avatarInitial(widget.peerName),
              style: const TextStyle(
                color: Color(0xFF0F766E),
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          );
        },
      ),
    );
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

  Future<void> _fetchMessages({bool silent = false}) async {
    if (_fetching) return;
    _fetching = true;
    try {
      final msgs = await api.getMessages(widget.chatId);
      if (!mounted) return;
      final oldLastId = _toInt(
        _messages.isNotEmpty ? _messages.last['id'] : null,
      );
      final incoming = msgs.cast<Map<String, dynamic>>();
      final newLastId = _toInt(
        incoming.isNotEmpty ? incoming.last['id'] : null,
      );
      final hasNewMessages =
          incoming.length != _messages.length || oldLastId != newLastId;
      setState(() {
        _messages
          ..clear()
          ..addAll(incoming);
        _loading = false;
      });
      if (hasNewMessages || !silent) {
        _scrollToBottom();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      if (!silent) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Load messages failed: $e')));
      }
    } finally {
      _fetching = false;
    }
  }

  int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    try {
      await api.sendMessage(chatId: widget.chatId, content: text);
      _messageController.clear();
      await _fetchMessages();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Send failed: $e')));
    }
  }

  Future<void> _pickAndSendImage() async {
    final file = await _picker.pickImage(source: ImageSource.gallery);
    if (!mounted || file == null) return;
    await _uploadAndSendMedia(file: file, messageType: 'image');
  }

  Future<void> _pickAndSendVideo() async {
    final file = await _picker.pickVideo(source: ImageSource.gallery);
    if (!mounted || file == null) return;
    await _uploadAndSendMedia(file: file, messageType: 'video');
  }

  Future<void> _uploadAndSendMedia({
    required XFile file,
    required String messageType,
  }) async {
    if (_sendingMedia) return;
    setState(() => _sendingMedia = true);
    try {
      final files = <MultipartFile>[
        MultipartFile.fromBytes(await file.readAsBytes(), filename: file.name),
      ];
      final uploadedUrls = await api.uploadFiles(files);
      if (uploadedUrls.isEmpty) {
        throw Exception('Upload returned no file URL');
      }
      await api.sendMessage(
        chatId: widget.chatId,
        content: uploadedUrls.first,
        messageType: messageType,
      );
      await _fetchMessages();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Send media failed: $e')));
    } finally {
      if (mounted) setState(() => _sendingMedia = false);
    }
  }

  void _openProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UserProfilePage(
          userId: widget.peerUserId,
          title: 'User Profile',
          displayName: widget.peerName,
        ),
      ),
    );
  }

  Future<void> _showAttachmentPicker() async {
    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_outlined),
                  title: const Text('Send photo'),
                  onTap: () {
                    Navigator.pop(context);
                    _pickAndSendImage();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.videocam_outlined),
                  title: const Text('Send video'),
                  onTap: () {
                    Navigator.pop(context);
                    _pickAndSendVideo();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  String _formatMessageTime(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '';
    final dt = DateTime.tryParse(raw.trim())?.toLocal();
    if (dt == null) return '';
    return DateFormat('h:mm a').format(dt);
  }

  String _formatDateHeader(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '';
    final dt = DateTime.tryParse(raw.trim())?.toLocal();
    if (dt == null) return '';

    final now = DateTime.now();
    final msgDate = DateTime(dt.year, dt.month, dt.day);
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    if (msgDate == today) return 'Today';
    if (msgDate == yesterday) return 'Yesterday';
    return DateFormat('MMM d, yyyy').format(dt);
  }

  void _openImagePreview(String imageUrl) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      builder: (context) {
        return GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Stack(
            children: [
              Center(
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 5,
                  child: Image.network(imageUrl, fit: BoxFit.contain),
                ),
              ),
              const Positioned(
                top: 16,
                right: 16,
                child: Icon(Icons.close, color: Colors.white),
              ),
            ],
          ),
        );
      },
    );
  }

  String? _resolveMediaUrl(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return null;
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    if (value.startsWith('/')) return '$defaultBaseUrl$value';
    return '$defaultBaseUrl/$value';
  }

  Widget _buildMessageContent({
    required String type,
    required String content,
    required bool isMe,
  }) {
    if (type == 'image') {
      final imageUrl = _resolveMediaUrl(content);
      if (imageUrl == null) {
        return Container(
          width: 210,
          height: 120,
          color: Colors.grey[300],
          alignment: Alignment.center,
          child: const Text('Photo unavailable'),
        );
      }
      return GestureDetector(
        onTap: () => _openImagePreview(imageUrl),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(
            imageUrl,
            width: 210,
            height: 170,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) {
              return Container(
                width: 210,
                height: 120,
                color: Colors.grey[300],
                alignment: Alignment.center,
                child: const Text('Photo unavailable'),
              );
            },
          ),
        ),
      );
    }

    if (type == 'video') {
      final videoUrl = _resolveMediaUrl(content);
      if (videoUrl == null) {
        return Container(
          width: 210,
          height: 120,
          decoration: BoxDecoration(
            color: isMe ? Colors.black87 : Colors.grey[300],
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Text(
            'Video unavailable',
            style: TextStyle(color: isMe ? Colors.white70 : Colors.black54),
          ),
        );
      }
      return _ChatInlineVideoPlayer(url: videoUrl, isMe: isMe);
    }

    return Text(
      content,
      style: TextStyle(
        color: isMe ? Colors.white : Colors.black87,
        fontSize: 14,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.arrow_back),
                  ),
                  const SizedBox(width: 12),
                  _buildPeerAvatar(),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.peerName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Row(
                          children: [
                            const Icon(
                              Icons.star,
                              size: 14,
                              color: Color(0xFFF4B400),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              widget.peerRating,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: _openProfile,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'Profile',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Messages
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final message = _messages[index];
                        final senderId = (message['sender_id'] as num?)
                            ?.toInt();
                        final isMe =
                            senderId != null && senderId == _currentUserId;
                        final content = message['content']?.toString() ?? '';
                        final messageTimeRaw = message['created_at']
                            ?.toString();
                        final createdAt = _formatMessageTime(messageTimeRaw);
                        final messageType = (message['message_type'] ?? 'text')
                            .toString();

                        final currentDt = messageTimeRaw != null
                            ? DateTime.tryParse(messageTimeRaw)?.toLocal()
                            : null;

                        final prevMessage = index > 0
                            ? _messages[index - 1]
                            : null;
                        final nextMessage = index < _messages.length - 1
                            ? _messages[index + 1]
                            : null;

                        final prevDt = prevMessage != null
                            ? DateTime.tryParse(
                                prevMessage['created_at']?.toString() ?? '',
                              )?.toLocal()
                            : null;
                        final nextDt = nextMessage != null
                            ? DateTime.tryParse(
                                nextMessage['created_at']?.toString() ?? '',
                              )?.toLocal()
                            : null;

                        bool showDateHeader = false;
                        if (currentDt != null) {
                          if (prevDt == null) {
                            showDateHeader = true;
                          } else {
                            showDateHeader =
                                currentDt.year != prevDt.year ||
                                currentDt.month != prevDt.month ||
                                currentDt.day != prevDt.day;
                          }
                        }

                        final prevSenderId = prevMessage != null
                            ? (prevMessage['sender_id'] as num?)?.toInt()
                            : null;
                        final nextSenderId = nextMessage != null
                            ? (nextMessage['sender_id'] as num?)?.toInt()
                            : null;

                        final bool isFirstInGroup =
                            prevSenderId != senderId ||
                            showDateHeader ||
                            (currentDt != null &&
                                prevDt != null &&
                                currentDt.difference(prevDt).inMinutes >= 1);
                        final bool isLastInGroup =
                            nextSenderId != senderId ||
                            (nextDt != null &&
                                currentDt != null &&
                                nextDt.difference(currentDt).inMinutes >= 1) ||
                            (nextDt != null &&
                                currentDt != null &&
                                currentDt.day != nextDt.day);

                        return Padding(
                          padding: EdgeInsets.only(
                            bottom: isLastInGroup ? 12 : 2,
                          ),
                          child: Column(
                            crossAxisAlignment: isMe
                                ? CrossAxisAlignment.end
                                : CrossAxisAlignment.start,
                            children: [
                              if (showDateHeader)
                                Container(
                                  width: double.infinity,
                                  margin: const EdgeInsets.symmetric(
                                    vertical: 20,
                                  ),
                                  child: Center(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.grey[300],
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        _formatDateHeader(messageTimeRaw),
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.grey[700],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              Container(
                                constraints: BoxConstraints(
                                  maxWidth:
                                      MediaQuery.of(context).size.width * 0.75,
                                ),
                                padding: EdgeInsets.symmetric(
                                  horizontal: messageType == 'text' ? 14 : 0,
                                  vertical: messageType == 'text' ? 10 : 0,
                                ),
                                decoration: BoxDecoration(
                                  color: messageType == 'text'
                                      ? (isMe ? Colors.grey[900] : Colors.white)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.only(
                                    topLeft: Radius.circular(
                                      isMe || !isFirstInGroup ? 16 : 0,
                                    ),
                                    topRight: Radius.circular(
                                      !isMe || !isFirstInGroup ? 16 : 0,
                                    ),
                                    bottomLeft: const Radius.circular(16),
                                    bottomRight: const Radius.circular(16),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: isMe
                                      ? CrossAxisAlignment.end
                                      : CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _buildMessageContent(
                                      type: messageType,
                                      content: content,
                                      isMe: isMe,
                                    ),
                                    if (isLastInGroup && createdAt.isNotEmpty)
                                      Padding(
                                        padding: EdgeInsets.only(
                                          top: messageType == 'text' ? 4 : 4,
                                          bottom: messageType == 'text' ? 0 : 0,
                                        ),
                                        child: Text(
                                          createdAt,
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: messageType == 'text'
                                                ? (isMe
                                                      ? Colors.white70
                                                      : Colors.grey[500])
                                                : Colors.grey[600],
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),

            // Input Area
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_sendingMedia)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: LinearProgressIndicator(),
                    ),
                  Row(
                    children: [
                      IconButton(
                        onPressed: _sendingMedia ? null : _showAttachmentPicker,
                        icon: const Icon(Icons.attach_file),
                        color: Colors.grey[700],
                      ),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: TextField(
                            controller: _messageController,
                            decoration: const InputDecoration(
                              hintText: 'Type a message...',
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                vertical: 12,
                              ),
                            ),
                            onSubmitted: (_) => _sendMessage(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: _sendMessage,
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.grey[900],
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.send,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatInlineVideoPlayer extends StatefulWidget {
  const _ChatInlineVideoPlayer({required this.url, required this.isMe});

  final String url;
  final bool isMe;

  @override
  State<_ChatInlineVideoPlayer> createState() => _ChatInlineVideoPlayerState();
}

class _ChatInlineVideoPlayerState extends State<_ChatInlineVideoPlayer> {
  VideoPlayerController? _controller;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initController();
  }

  @override
  void didUpdateWidget(covariant _ChatInlineVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _initController();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initController() async {
    if (kIsWeb) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = null;
        });
      }
      return;
    }

    final previous = _controller;
    _controller = null;
    if (mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }
    if (previous != null) {
      await previous.dispose();
    }

    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    try {
      await controller.initialize().timeout(const Duration(seconds: 12));
      await controller.setLooping(false);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _isLoading = false;
        _error = null;
      });
    } catch (_) {
      await controller.dispose();
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Video unavailable';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 210,
          height: 170,
          child: InlineWebVideoPlayer(url: widget.url),
        ),
      );
    }

    if (_isLoading) {
      return Container(
        width: 210,
        height: 170,
        decoration: BoxDecoration(
          color: Colors.black12,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (_error != null ||
        _controller == null ||
        !_controller!.value.isInitialized) {
      return Container(
        width: 210,
        height: 120,
        decoration: BoxDecoration(
          color: widget.isMe ? Colors.black87 : Colors.grey[300],
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Text(
          _error ?? 'Video unavailable',
          style: TextStyle(
            color: widget.isMe ? Colors.white70 : Colors.black54,
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: () {
        if (_controller!.value.isPlaying) {
          _controller!.pause();
        } else {
          _controller!.play();
        }
        setState(() {});
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 210,
          height: 170,
          child: Stack(
            fit: StackFit.expand,
            children: [
              VideoPlayer(_controller!),
              Align(
                alignment: Alignment.center,
                child: Icon(
                  _controller!.value.isPlaying
                      ? Icons.pause_circle
                      : Icons.play_circle,
                  color: Colors.white.withValues(alpha: 0.9),
                  size: 44,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


