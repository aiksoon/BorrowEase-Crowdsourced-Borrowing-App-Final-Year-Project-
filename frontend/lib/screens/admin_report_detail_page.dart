import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';

import '../services/api.dart';
import '../services/api_client.dart' show defaultBaseUrl;
import '../widgets/web_inline_video_player.dart';
import 'screens.dart';

class AdminReportDetailPage extends StatefulWidget {
  final int reportId;

  const AdminReportDetailPage({super.key, required this.reportId});

  @override
  State<AdminReportDetailPage> createState() => _AdminReportDetailPageState();
}

class _AdminReportDetailPageState extends State<AdminReportDetailPage> {
  static const Color _ecoTeal = Color(0xFF0D9488);

  bool _loading = true;
  bool _resolving = false;
  String? _error;
  Map<String, dynamic>? _detail;

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

  String? _resolveUrl(dynamic raw) {
    final value = (raw ?? '').toString().trim();
    if (value.isEmpty) return null;
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    if (value.startsWith('/')) return '$defaultBaseUrl$value';
    return '$defaultBaseUrl/$value';
  }

  String _formatDate(dynamic raw) {
    final dt = DateTime.tryParse((raw ?? '').toString());
    if (dt == null) return '-';
    return DateFormat('dd MMM yyyy, HH:mm').format(dt.toLocal());
  }

  bool _isVideoUrl(String url) {
    final clean = url.split('?').first.toLowerCase();
    return clean.endsWith('.mp4') ||
        clean.endsWith('.mov') ||
        clean.endsWith('.webm') ||
        clean.endsWith('.m4v');
  }

  Future<void> _openMediaPreview({
    required String url,
    required bool isVideo,
  }) async {
    if (isVideo) {
      await showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          insetPadding: const EdgeInsets.all(16),
          backgroundColor: Colors.black,
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: _ReportVideoPreviewPlayer(url: url),
          ),
        ),
      );
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _ReportImagePreviewPage(imageUrl: url)),
    );
  }

  Future<void> _contactUsers() async {
    final detail = _detail ?? <String, dynamic>{};
    final candidates = <Map<String, dynamic>>[];

    final reporterId = _toInt(detail['reporter_id']);
    if (reporterId > 0) {
      candidates.add({
        'id': reporterId,
        'label': 'Reporter',
        'name': (detail['reporter_name'] ?? 'Reporter').toString(),
        'avatar': detail['reporter_avatar'],
      });
    }

    final reportedUserId = _toInt(detail['reported_user_id']);
    if (reportedUserId > 0) {
      candidates.add({
        'id': reportedUserId,
        'label': 'Reported User',
        'name': (detail['reported_user_name'] ?? 'User').toString(),
        'avatar': detail['reported_user_avatar'],
      });
    }

    final unique = <int, Map<String, dynamic>>{};
    for (final user in candidates) {
      unique[user['id'] as int] = user;
    }
    final options = unique.values.toList();

    if (options.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No users available to contact.')),
      );
      return;
    }

    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: options.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final user = options[index];
              final name = (user['name'] ?? 'User').toString();
              final role = (user['label'] ?? 'User').toString();
              final avatar = _resolveUrl(user['avatar']);
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFFE6F4F2),
                  backgroundImage: avatar == null ? null : NetworkImage(avatar),
                  child: avatar == null
                      ? Text(
                          name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: const TextStyle(
                            color: _ecoTeal,
                            fontWeight: FontWeight.w700,
                          ),
                        )
                      : null,
                ),
                title: Text(name),
                subtitle: Text(role),
                onTap: () => Navigator.pop(context, user),
              );
            },
          ),
        );
      },
    );

    if (selected == null) return;

    final peerUserId = selected['id'] as int;
    final peerName = (selected['name'] ?? 'User').toString();
    final peerAvatar = _resolveUrl(selected['avatar']);

    try {
      final chat = await api.getOrCreateDirectChat(peerUserId: peerUserId);
      final chatId = _toInt(chat['id']);
      if (!mounted) return;
      if (chatId <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to open chat right now.')),
        );
        return;
      }

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatConversationPage(
            chatId: chatId,
            peerName: peerName,
            peerRating: '5.0',
            peerUserId: peerUserId,
            peerAvatarUrl: peerAvatar,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to open chat: $e')));
    }
  }

  Future<void> _load() async {
    try {
      final data = await api.getAdminReportDetails(widget.reportId);
      if (!mounted) return;
      setState(() {
        _detail = data;
        _loading = false;
        _error = null;
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

  Widget _buildUserTile({
    required String label,
    required String name,
    String? avatar,
  }) {
    final resolvedAvatar = _resolveUrl(avatar);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFE6F4F2),
                image: resolvedAvatar == null
                    ? null
                    : DecorationImage(
                        image: NetworkImage(resolvedAvatar),
                        fit: BoxFit.cover,
                      ),
              ),
              child: resolvedAvatar == null
                  ? Center(
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: _ecoTeal,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaGrid(List<dynamic> mediaUrls) {
    if (mediaUrls.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Column(
          children: [
            Icon(Icons.photo_library_outlined, color: Colors.grey[500]),
            const SizedBox(height: 6),
            Text(
              'No media uploaded',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: mediaUrls.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1,
      ),
      itemBuilder: (context, index) {
        final raw = mediaUrls[index];
        final url = _resolveUrl(raw);
        final isVideo = url != null && _isVideoUrl(url);
        return InkWell(
          onTap: url == null
              ? null
              : () => _openMediaPreview(url: url, isVideo: isVideo),
          borderRadius: BorderRadius.circular(10),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              color: const Color(0xFFF1F5F9),
              child: url == null
                  ? const Icon(Icons.broken_image_outlined)
                  : isVideo
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        Container(color: const Color(0xFF111827)),
                        const Center(
                          child: Icon(
                            Icons.play_circle_fill,
                            color: Colors.white,
                            size: 38,
                          ),
                        ),
                      ],
                    )
                  : Image.network(
                      url,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.broken_image_outlined),
                    ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _markResolved() async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark as Resolved'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Resolution Note',
            hintText: 'Describe final action taken...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Mark Resolved'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _resolving = true);
    try {
      await api.updateAdminReportStatus(
        reportId: widget.reportId,
        status: 'resolved',
        resolutionNote: controller.text.trim(),
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Report marked as resolved.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to resolve report: $e')));
    } finally {
      if (mounted) {
        setState(() => _resolving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail ?? <String, dynamic>{};
    final status = (detail['status'] ?? 'open').toString().toLowerCase();
    final mediaUrls = (detail['media_urls'] as List?) ?? const <dynamic>[];
    final requestId = _toInt(detail['request_id']);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      appBar: AppBar(
        title: const Text('Report Details'),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text('Failed to load details: $_error'))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Report #${_toInt(detail['id'])}',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _formatDate(detail['created_at']),
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
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
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Parties Involved',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            _buildUserTile(
                              label: 'Reporter',
                              name: (detail['reporter_name'] ?? 'Reporter')
                                  .toString(),
                              avatar: detail['reporter_avatar']?.toString(),
                            ),
                            const SizedBox(width: 8),
                            _buildUserTile(
                              label: 'Reported User',
                              name: (detail['reported_user_name'] ?? 'User')
                                  .toString(),
                              avatar: detail['reported_user_avatar']
                                  ?.toString(),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Issue Description',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE5E7EB)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (detail['reason_category'] ?? 'Issue')
                                    .toString(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFB91C1C),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                (detail['description'] ??
                                        detail['reason'] ??
                                        '-')
                                    .toString(),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Order #$requestId - ${(detail['item_title'] ?? 'Item').toString()}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[700],
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Attached Media',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 10),
                        _buildMediaGrid(mediaUrls),
                        const SizedBox(height: 10),
                        if (requestId > 0)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => AdminTransactionDetailsPage(
                                      requestId: requestId,
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.compare),
                              label: const Text('Open Transaction Evidence'),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _contactUsers,
                icon: const Icon(Icons.chat_bubble_outline),
                label: const Text('Contact Users'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                onPressed: status == 'resolved' || _resolving
                    ? null
                    : _markResolved,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _ecoTeal,
                  foregroundColor: Colors.white,
                ),
                child: _resolving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : const Text('Mark as Resolved'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportImagePreviewPage extends StatelessWidget {
  final String imageUrl;

  const _ReportImagePreviewPage({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: Image.network(
            imageUrl,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Failed to load image',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReportVideoPreviewPlayer extends StatefulWidget {
  final String url;

  const _ReportVideoPreviewPlayer({required this.url});

  @override
  State<_ReportVideoPreviewPlayer> createState() =>
      _ReportVideoPreviewPlayerState();
}

class _ReportVideoPreviewPlayerState extends State<_ReportVideoPreviewPlayer> {
  VideoPlayerController? _controller;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    if (kIsWeb) {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
      return;
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
        _loading = false;
      });
    } catch (_) {
      await controller.dispose();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Video unavailable';
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return InlineWebVideoPlayer(url: widget.url);
    }

    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    if (_error != null ||
        _controller == null ||
        !_controller!.value.isInitialized) {
      return Center(
        child: Text(
          _error ?? 'Video unavailable',
          style: const TextStyle(color: Colors.white70),
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
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: _controller!.value.aspectRatio,
              child: VideoPlayer(_controller!),
            ),
          ),
          Align(
            alignment: Alignment.center,
            child: Icon(
              _controller!.value.isPlaying
                  ? Icons.pause_circle
                  : Icons.play_circle,
              color: Colors.white.withValues(alpha: 0.9),
              size: 54,
            ),
          ),
        ],
      ),
    );
  }
}
