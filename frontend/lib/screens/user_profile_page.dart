import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import '../services/api_client.dart' show ApiClient, defaultBaseUrl;
import 'screens.dart';

// ==================== USER PROFILE PAGE ====================
class UserProfilePage extends StatefulWidget {
  final String title;
  final String displayName;
  final int? userId;

  const UserProfilePage({
    super.key,
    this.title = 'User Profile',
    this.displayName = 'John Doe',
    this.userId,
  });

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  final ApiClient _api = ApiClient();
  Map<String, dynamic>? _profileData;
  bool _isLoading = true;
  String? _errorMessage;
  int? _currentUserId;
  bool _isOpeningMessage = false;

  @override
  void initState() {
    super.initState();
    _fetchProfile();
  }

  Future<void> _fetchProfile() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final storedUser = await _api.getStoredUser();
    final viewerId = _toInt(storedUser?['id'], 0);
    if (mounted) {
      setState(() {
        _currentUserId = viewerId > 0 ? viewerId : null;
      });
    }

    if (widget.userId == null) {
      setState(() {
        _profileData = {
          'name': widget.displayName,
          'avatar_url': null,
          'kyc_status': 'pending',
          'stats': {'rating': 5.0, 'itemsLent': 0, 'transactions': 0},
          'reviews': <dynamic>[],
        };
        _isLoading = false;
      });
      return;
    }

    try {
      final data = await _api.getUserProfile(widget.userId!);
      final stats = Map<String, dynamic>.from(
        (data['stats'] as Map<String, dynamic>?) ?? const <String, dynamic>{},
      );

      setState(() {
        _profileData = {
          ...data,
          'stats': {
            'rating': _toDouble(stats['rating'], 5.0),
            'itemsLent': _toInt(stats['itemsLent'], 0),
            'transactions': _toInt(stats['transactions'], 0),
          },
          'reviews': (data['reviews'] as List?) ?? <dynamic>[],
        };
        _isLoading = false;
      });
    } catch (e) {
      String message = 'Could not load profile. Please try again later.';
      if (e is DioException) {
        final status = e.response?.statusCode;
        if (status == 404) {
          message = 'User profile not found.';
        } else if (status == 400) {
          message = 'Invalid profile request.';
        }
      }
      setState(() {
        _errorMessage = message;
        _isLoading = false;
      });
    }
  }

  int _toInt(dynamic value, int fallback) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  double _toDouble(dynamic value, double fallback) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? fallback;
    return fallback;
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

  String _avatarInitial(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    final match = RegExp(r'[A-Za-z0-9]').firstMatch(trimmed);
    if (match != null) {
      return (match.group(0) ?? '?').toUpperCase();
    }
    return trimmed.characters.first.toUpperCase();
  }

  int? _effectiveProfileUserId(Map<String, dynamic> profile) {
    final fromData = _toInt(profile['id'], 0);
    if (fromData > 0) return fromData;
    if ((widget.userId ?? 0) > 0) return widget.userId;
    return null;
  }

  Future<void> _openMessageChat(Map<String, dynamic> profile) async {
    final peerUserId = _effectiveProfileUserId(profile);
    if (peerUserId == null || _isOpeningMessage) return;

    if (_currentUserId != null && _currentUserId == peerUserId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You cannot message yourself.')),
      );
      return;
    }

    setState(() => _isOpeningMessage = true);
    try {
      Map<String, dynamic>? chat = await _findExistingChatWithPeer(peerUserId);
      chat ??= await _api.getOrCreateDirectChat(peerUserId: peerUserId);
      final chatId = _toInt(chat['id'], 0);
      if (chatId <= 0) {
        throw StateError('Invalid chat id');
      }

      final stats = Map<String, dynamic>.from(
        (profile['stats'] as Map<String, dynamic>?) ?? const <String, dynamic>{},
      );
      final rating = _toDouble(stats['rating'], 5.0);
      final displayName =
          (profile['name'] as String?)?.trim().isNotEmpty == true
          ? (profile['name'] as String).trim()
          : widget.displayName;

      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatConversationPage(
            chatId: chatId,
            peerName: displayName,
            peerRating: rating.toStringAsFixed(1),
            peerUserId: peerUserId,
            peerAvatarUrl: profile['avatar_url']?.toString(),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      String message = 'Unable to start message. Please try again.';
      if (e is DioException) {
        final status = e.response?.statusCode;
        final serverMessage = (e.response?.data is Map)
            ? (e.response?.data['message']?.toString() ?? '')
            : '';
        if (serverMessage.isNotEmpty) {
          message = serverMessage;
        } else if (status == 404) {
          message = 'User not found.';
        } else if (status == 400) {
          message = 'Invalid message request.';
        }
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _isOpeningMessage = false);
    }
  }

  Future<Map<String, dynamic>?> _findExistingChatWithPeer(int peerUserId) async {
    final rawChats = await _api.getChats();
    Map<String, dynamic>? latest;
    int latestTs = -1;

    for (final raw in rawChats) {
      if (raw is! Map<String, dynamic>) continue;
      final id = _toInt(raw['id'], 0);
      if (id <= 0) continue;
      if (_toInt(raw['peer_user_id'], 0) != peerUserId) continue;

      final timeRaw = (raw['last_message_at'] ?? raw['created_at'])?.toString();
      final ts = DateTime.tryParse(timeRaw ?? '')?.millisecondsSinceEpoch ?? 0;
      if (ts >= latestTs) {
        latest = raw;
        latestTs = ts;
      }
    }

    return latest;
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profileData ?? const <String, dynamic>{};
    final stats = Map<String, dynamic>.from(
      (profile['stats'] as Map<String, dynamic>?) ?? const <String, dynamic>{},
    );
    final reviews = (profile['reviews'] as List?) ?? <dynamic>[];
    final avatarUrl = _resolveUrl(profile['avatar_url']);
    final displayName =
        (profile['name'] as String?)?.trim().isNotEmpty == true
        ? (profile['name'] as String).trim()
        : widget.displayName;
    final username = displayName.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    final rating = _toDouble(stats['rating'], 5.0);
    final itemsLent = _toInt(stats['itemsLent'], 0);
    final transactions = _toInt(stats['transactions'], 0);
    final kycStatus =
      (profile['kyc_status'] as String?)?.toLowerCase().trim() ?? 'pending';
    final isVerified = kycStatus == 'verified';
    final isPending = kycStatus == 'pending';
    final badgeText = isVerified
      ? 'Verified'
      : isPending
      ? 'Pending Verification'
      : 'Not Verified';
    final badgeIcon = isVerified ? Icons.verified : Icons.gpp_maybe_rounded;
    final badgeBg = isVerified
      ? const Color(0xFFE8F8EE)
      : const Color(0xFFFFF6D8);
    final badgeFg = isVerified
      ? const Color(0xFF1A7F37)
      : const Color(0xFF8A5A00);
    final profileUserId = _effectiveProfileUserId(profile);
    final canMessage =
        !_isLoading &&
        _errorMessage == null &&
        profileUserId != null &&
        (_currentUserId == null || _currentUserId != profileUserId);

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      bottomNavigationBar: canMessage
          ? SafeArea(
              minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isOpeningMessage ? null : () => _openMessageChat(profile),
                  icon: _isOpeningMessage
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : const Icon(Icons.chat_bubble_outline, color: Colors.white),
                  label: Text(_isOpeningMessage ? 'Opening chat...' : 'Message'),
                ),
              ),
            )
          : null,
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
                  Text(
                    widget.title,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),

            if (_isLoading)
              const Expanded(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_errorMessage != null)
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.red, fontSize: 16),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: _fetchProfile,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(24, 18, 24, 22),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0x140D9488), Color(0x00FFFFFF)],
                          ),
                        ),
                        child: Column(
                          children: [
                            Container(
                              width: 92,
                              height: 92,
                              decoration: BoxDecoration(
                                color: avatarUrl == null
                                    ? const Color(0xFF0D9488).withValues(alpha: 0.12)
                                    : Colors.grey[300],
                                shape: BoxShape.circle,
                                image: avatarUrl != null
                                    ? DecorationImage(
                                        image: NetworkImage(avatarUrl),
                                        fit: BoxFit.cover,
                                      )
                                    : null,
                              ),
                              child: avatarUrl == null
                                  ? Center(
                                      child: Text(
                                        _avatarInitial(displayName),
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: Color(0xFF0F766E),
                                          fontSize: 40,
                                          fontWeight: FontWeight.w700,
                                          height: 1,
                                        ),
                                      ),
                                    )
                                  : null,
                            ),
                            const SizedBox(height: 14),
                            Text(
                              displayName,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '@$username',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: badgeBg,
                                border: Border.all(color: badgeFg.withValues(alpha: 0.35)),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    badgeIcon,
                                    size: 16,
                                    color: badgeFg,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    badgeText,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: badgeFg,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 14,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey[200]!),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: _buildStat(
                                      rating.toStringAsFixed(1),
                                      'Rating',
                                      showStar: true,
                                    ),
                                  ),
                                  Container(
                                    width: 1,
                                    height: 36,
                                    color: Colors.grey[200],
                                  ),
                                  Expanded(
                                    child: _buildStat(
                                      itemsLent.toString(),
                                      'Items Lent',
                                    ),
                                  ),
                                  Container(
                                    width: 1,
                                    height: 36,
                                    color: Colors.grey[200],
                                  ),
                                  Expanded(
                                    child: _buildStat(
                                      transactions.toString(),
                                      'Transactions',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(20),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Reviews',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 16),
                            if (reviews.isNotEmpty)
                              ...reviews.map((review) {
                                return _buildReviewItem(
                                  review['reviewer_name'] ?? 'User',
                                  ((review['rating'] as num?)?.toInt() ?? 5)
                                      .clamp(1, 5),
                                  review['comment'] ?? '',
                                  review['created_at'] != null 
                                    ? _formatDate(review['created_at']) 
                                    : '',
                                  review['reviewer_avatar'],
                                  itemName: review['item_title']?.toString(),
                                  reviewerRole: review['reviewer_role']?.toString(),
                                );
                              })
                            else
                              SizedBox(
                                height: 220,
                                child: Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.rate_review_outlined,
                                        size: 22,
                                        color: Colors.grey[400],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'No reviews yet.',
                                        style: TextStyle(
                                          color: Colors.grey[600],
                                          fontSize: 15,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return DateFormat('MMM d, yyyy').format(date);
    } catch (_) {
      return '';
    }
  }

  Widget _buildStat(String value, String label, {bool showStar = false}) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showStar)
              const Icon(Icons.star_rounded, size: 18, color: Color(0xFFF4B400)),
            if (showStar) const SizedBox(width: 3),
            Text(
              value,
              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }

  Widget _buildReviewItem(
    String name,
    int rating,
    String comment,
    String time,
    String? profilePic,
    {String? itemName, String? reviewerRole}
  ) {
    final safeComment = comment.trim().isEmpty
        ? 'Great experience.'
        : comment.trim();
    final borrowedItemName = (itemName ?? '').trim();
    final showBorrowedItem = borrowedItemName.isNotEmpty;
    final itemLabel = 'Borrowed item';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8ECEF)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Builder(
                builder: (context) {
                  final picUrl = _resolveUrl(profilePic);
                  return Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      shape: BoxShape.circle,
                      image: picUrl != null
                          ? DecorationImage(
                              image: NetworkImage(picUrl),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: picUrl == null
                        ? Center(
                            child: Text(
                              name.isNotEmpty ? name[0].toUpperCase() : '?',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.grey[600],
                              ),
                            ),
                          )
                        : null,
                  );
                },
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        ...List.generate(
                          rating,
                          (i) => const Icon(
                            Icons.star,
                            color: Color(0xFFF59E0B),
                            size: 15,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF4D6),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.star_rounded, size: 14, color: Color(0xFFF59E0B)),
                    const SizedBox(width: 4),
                    Text(
                      rating.toStringAsFixed(1),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF92400E),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (time.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              time,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[500],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          if (showBorrowedItem) ...[
            const SizedBox(height: 8),
            Text(
              '$itemLabel: $borrowedItemName',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[700],
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              safeComment,
              style: const TextStyle(
                color: Color(0xFF374151),
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}


