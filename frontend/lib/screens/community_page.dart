import 'package:flutter/material.dart';
import 'screens.dart';
import '../services/api.dart';
import '../services/api_client.dart' show defaultBaseUrl;

// ==================== COMMUNITY PAGE ====================
class CommunityPage extends StatefulWidget {
  const CommunityPage({super.key});

  @override
  State<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends State<CommunityPage> {
  int selectedTabIndex = 0;
  bool _loading = true;
  bool _refreshing = false;
  int? _currentUserId;
  String? _currentUserAvatarUrl;
  List<Map<String, dynamic>> _allPosts = [];
  List<Map<String, dynamic>> _nearbyPosts = [];

  @override
  void initState() {
    super.initState();
    _loadPosts();
  }

  Future<void> _loadPosts({bool silent = false}) async {
    if (_refreshing) return;
    if (mounted) {
      setState(() {
        _refreshing = true;
        if (_allPosts.isEmpty && _nearbyPosts.isEmpty && !silent) {
          _loading = true;
        }
      });
    }

    try {
      final user = await api.getStoredUser();
      int? userId = _toInt(user?['id']);
      String? avatarUrl = user?['avatar_url']?.toString();
      try {
        final me = await api.getMe();
        final meUser = me['user'];
        if (meUser is Map<String, dynamic>) {
          userId = _toInt(meUser['id']);
          final latestAvatar = meUser['avatar_url']?.toString().trim();
          if (latestAvatar != null && latestAvatar.isNotEmpty) {
            avatarUrl = latestAvatar;
          }
        }
      } catch (_) {
        // Keep stored user fallback when /auth/me is unavailable.
      }
      final allFuture = api.getCommunityPosts();
      final nearbyFuture = api.getCommunityPosts(nearby: true);
      final results = await Future.wait([allFuture, nearbyFuture]);

      if (!mounted) return;
      setState(() {
        _currentUserId = userId;
        _currentUserAvatarUrl = avatarUrl;
        _allPosts = _toMapList(results[0]);
        _nearbyPosts = _toMapList(results[1]);
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
            content: Text('Failed to load posts: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  List<Map<String, dynamic>> get _activePosts =>
      selectedTabIndex == 0 ? _allPosts : _nearbyPosts;

  List<Map<String, dynamic>> _toMapList(dynamic raw) {
    if (raw is! List) return <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e.cast<String, dynamic>()))
        .toList();
  }

  int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  Future<void> _openCreatePost() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (context) => const CreatePostPage()),
    );
    if (created == true && mounted) {
      await _loadPosts(silent: true);
    }
  }

  Future<void> _openEditPost(Map<String, dynamic> post) async {
    final postId = _toInt(post['id']);
    if (postId == null) return;

    final updated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => EditPostPage(
          postId: postId,
          initialContent: (post['content'] ?? '').toString(),
          initialImageUrl: (post['image_url'] ?? '').toString(),
          displayName: (post['owner_name'] ?? 'User').toString(),
          location: (post['owner_location'] ?? 'Unknown location').toString(),
        ),
      ),
    );

    if (updated == true && mounted) {
      await _loadPosts(silent: true);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Post updated')));
    }
  }

  String? _resolveMediaUrl(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final value = raw.trim();
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    final cleanValue = value.startsWith('/') ? value.substring(1) : value;
    final baseUrl = defaultBaseUrl.endsWith('/')
        ? defaultBaseUrl.substring(0, defaultBaseUrl.length - 1)
        : defaultBaseUrl;
    return '$baseUrl/$cleanValue';
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

  void _openImagePreview(String imageUrl) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.9),
      builder: (context) {
        return GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: SafeArea(
              child: Stack(
                children: [
                  Center(
                    child: InteractiveViewer(
                      minScale: 0.8,
                      maxScale: 4,
                      child: Image.network(imageUrl, fit: BoxFit.contain),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _deletePost(int postId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete post'),
          content: const Text('This action cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await api.deleteCommunityPost(postId);
      if (!mounted) return;
      await _loadPosts(silent: true);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Post deleted')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to delete post: $e')));
    }
  }

  Future<void> _openUserProfile({
    required int? userId,
    required String displayName,
  }) async {
    if (userId == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UserProfilePage(
          userId: userId,
          title: 'User Profile',
          displayName: displayName,
        ),
      ),
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
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Community',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  GestureDetector(
                    onTap: _openCreatePost,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.grey[900],
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.add,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Tab Bar
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(16),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => selectedTabIndex = 0),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: selectedTabIndex == 0
                                ? Colors.white
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: selectedTabIndex == 0
                                ? [
                                    BoxShadow(
                                      color: Colors.grey.withValues(alpha: 0.2),
                                      blurRadius: 4,
                                    ),
                                  ]
                                : null,
                          ),
                          child: Text(
                            'All Posts',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: selectedTabIndex == 0
                                  ? Colors.black
                                  : Colors.grey[600],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => selectedTabIndex = 1),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: selectedTabIndex == 1
                                ? Colors.white
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: selectedTabIndex == 1
                                ? [
                                    BoxShadow(
                                      color: Colors.grey.withValues(alpha: 0.2),
                                      blurRadius: 4,
                                    ),
                                  ]
                                : null,
                          ),
                          child: Text(
                            'Nearby',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: selectedTabIndex == 1
                                  ? Colors.black
                                  : Colors.grey[600],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Posts List
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: () => _loadPosts(silent: true),
                      child: _activePosts.isEmpty
                          ? ListView(
                              children: [
                                const SizedBox(height: 120),
                                Center(
                                  child: Text(
                                    selectedTabIndex == 0
                                        ? 'No posts yet.'
                                        : 'No nearby posts in your registered area yet.',
                                  ),
                                ),
                              ],
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              itemCount: _activePosts.length,
                              itemBuilder: (context, index) {
                                return _buildPostCard(_activePosts[index]);
                              },
                            ),
                    ),
            ),

            if (_refreshing && !_loading)
              const LinearProgressIndicator(minHeight: 2),
          ],
        ),
      ),
    );
  }

  Widget _buildPostCard(Map<String, dynamic> item) {
    final ownerId = _toInt(item['user_id']);
    final isMine = ownerId != null && ownerId == _currentUserId;
    final ownerName = (item['owner_name'] ?? 'Owner').toString();
    final rawOwnerAvatar =
      (isMine && (_currentUserAvatarUrl ?? '').trim().isNotEmpty)
        ? _currentUserAvatarUrl
        : item['owner_avatar_url']?.toString();
    final ownerAvatarUrl = _resolveMediaUrl(rawOwnerAvatar);
    final content = (item['content'] ?? '').toString().trim();
    final imageUrl = _resolveMediaUrl(item['image_url']?.toString());
    final location = (item['owner_location'] ?? 'Location not provided')
        .toString();
    final createdAt = item['created_at']?.toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            spreadRadius: 0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              children: [
                GestureDetector(
                  onTap: ownerId == null
                      ? null
                      : () => _openUserProfile(
                          userId: ownerId,
                          displayName: ownerName,
                        ),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: ownerAvatarUrl == null
                          ? const Color(0xFF0D9488).withValues(alpha: 0.12)
                          : Colors.grey[200],
                      shape: BoxShape.circle,
                      image: ownerAvatarUrl != null
                          ? DecorationImage(
                              image: NetworkImage(ownerAvatarUrl),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: ownerAvatarUrl == null
                        ? Center(
                            child: Text(
                              _avatarInitial(ownerName),
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0F766E),
                                height: 1,
                              ),
                            ),
                          )
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: ownerId == null
                            ? null
                            : () => _openUserProfile(
                                userId: ownerId,
                                displayName: ownerName,
                              ),
                        child: Text(
                          ownerName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            _formatRelativeTime(createdAt),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            width: 4,
                            height: 4,
                            decoration: const BoxDecoration(
                              color: Color(0xFF2DA69A),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              location,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[500],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (isMine)
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_horiz),
                    onSelected: (value) async {
                      if (value == 'edit') {
                        await _openEditPost(item);
                        return;
                      }
                      if (value == 'delete') {
                        final postId = _toInt(item['id']);
                        if (postId != null) {
                          await _deletePost(postId);
                        }
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit post')),
                      PopupMenuItem(value: 'delete', child: Text('Delete post')),
                    ],
                  ),
              ],
            ),
          ),
          if (imageUrl != null) ...[
            GestureDetector(
              onTap: () => _openImagePreview(imageUrl),
              child: Image.network(
                imageUrl,
                height: 210,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) {
                  return Container(
                    height: 210,
                    width: double.infinity,
                    color: Colors.grey[200],
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: Colors.grey[400],
                      size: 30,
                    ),
                  );
                },
              ),
            ),
          ],
          Padding(
            padding: EdgeInsets.fromLTRB(14, imageUrl != null ? 12 : 0, 14, 14),
            child: Text(
              content.isEmpty ? '(No content)' : content,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.black87,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
      ),
    );
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
}



