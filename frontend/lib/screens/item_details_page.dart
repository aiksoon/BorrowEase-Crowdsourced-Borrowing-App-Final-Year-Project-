import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:video_player/video_player.dart';

import '../services/api.dart';
import '../services/api_client.dart' show defaultBaseUrl;
import '../services/favorites_events.dart';
import '../widgets/web_inline_video_player.dart';
import 'screens.dart';

class ItemDetailsPage extends StatefulWidget {
  final Map<String, dynamic> item;

  const ItemDetailsPage({super.key, required this.item});

  @override
  State<ItemDetailsPage> createState() => _ItemDetailsPageState();
}

class _ItemDetailsPageState extends State<ItemDetailsPage> {
  late Map<String, dynamic> _item;
  int? _itemId;
  bool _isFavorite = false;
  bool _loading = false;
  String? _error;
  double _ownerRating = 5.0;
  int _ownerReviewCount = 0;
  VideoPlayerController? _videoController;
  String? _videoControllerUrl;
  bool _isVideoLoading = false;
  String? _videoError;
  late final VoidCallback _favoritesListener;

  @override
  void initState() {
    super.initState();
    _favoritesListener = () => _syncFavorite();
    favoritesRevision.addListener(_favoritesListener);
    _item = Map<String, dynamic>.from(widget.item);
    _itemId = _toInt(widget.item['id']);
    _configureVideoController(_resolveMediaUrl(widget.item['video_url']));
    _syncFavorite();
    if (_itemId != null) {
      _fetchDetail();
    }
  }

  @override
  void dispose() {
    favoritesRevision.removeListener(_favoritesListener);
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _syncFavorite() async {
    if (_itemId == null) return;
    try {
      final favorites = await api.getFavorites();
      final exists = favorites.any((f) {
        if (f is! Map<String, dynamic>) return false;
        return _toInt(f['id']) == _itemId;
      });
      if (mounted) setState(() => _isFavorite = exists);
    } catch (_) {
      // best-effort sync; ignore errors
    }
  }

  Future<void> _fetchDetail() async {
    if (_itemId == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await api.getItemDetail(_itemId!);
      if (!mounted) return;
      setState(() => _item = detail);
      await _configureVideoController(_resolveMediaUrl(detail['video_url']));
      await _loadOwnerRatingStats((detail['owner_id'] as num?)?.toInt());
      await _syncFavorite();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _configureVideoController(
    String? videoUrl, {
    bool forceRetry = false,
  }) async {
    if (kIsWeb) {
      final previous = _videoController;
      _videoController = null;
      _videoControllerUrl = videoUrl;
      if (previous != null) {
        await previous.dispose();
      }
      if (mounted) {
        setState(() {
          _isVideoLoading = false;
          _videoError = null;
        });
      }
      return;
    }

    if (!forceRetry && videoUrl == _videoControllerUrl) return;

    final previous = _videoController;
    _videoController = null;
    _videoControllerUrl = videoUrl;

    if (mounted) {
      setState(() {
        _isVideoLoading = videoUrl != null;
        _videoError = null;
      });
    }

    if (previous != null) {
      await previous.dispose();
    }

    if (videoUrl == null) {
      if (mounted) {
        setState(() {
          _isVideoLoading = false;
        });
      }
      return;
    }

    final controller = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
    try {
      await controller.initialize().timeout(const Duration(seconds: 12));
      await controller.setLooping(true);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _videoController = controller;
        _isVideoLoading = false;
        _videoError = null;
      });
    } catch (_) {
      await controller.dispose();
      if (!mounted) return;
      setState(() {
        _isVideoLoading = false;
        _videoError =
            'Unable to load video. Please try another file (MP4 H.264/AAC).';
      });
    }
  }

  Future<void> _loadOwnerRatingStats(int? ownerId) async {
    if (ownerId == null) {
      if (!mounted) return;
      setState(() {
        _ownerRating = 5.0;
        _ownerReviewCount = 0;
      });
      return;
    }

    try {
      final reviews = await api.getReviews(userId: ownerId);
      final ratings = reviews
          .map((r) => (r['rating'] as num?)?.toDouble())
          .whereType<double>()
          .toList();
      final count = ratings.length;
      final avg = count == 0 ? 5.0 : ratings.reduce((a, b) => a + b) / count;

      if (!mounted) return;
      setState(() {
        _ownerRating = avg;
        _ownerReviewCount = count;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _ownerRating = 5.0;
        _ownerReviewCount = 0;
      });
    }
  }

  Future<void> _toggleFavorite() async {
    if (_itemId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Missing item id; cannot save to favourites'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final user = await api.getStoredUser();
    final currentUserId = (user?['id'] as num?)?.toInt();
    if (currentUserId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please sign in first'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final nextValue = !_isFavorite;
    if (mounted) {
      setState(() => _isFavorite = nextValue);
    }

    try {
      if (nextValue) {
        await api.addFavorite(_itemId!);
      } else {
        await api.removeFavorite(_itemId!);
      }
      notifyFavoritesChanged();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nextValue ? 'Added to favourites' : 'Removed from favourites',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isFavorite = !nextValue);
      }
      if (!mounted) return;
      final isUnauthorized = e is DioException && e.response?.statusCode == 401;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isUnauthorized
                ? 'Please sign in first'
                : 'Favourite update failed: $e',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _openDirectMessage() async {
    final int? itemId = (_item['id'] as num?)?.toInt() ?? _itemId;
    final int? ownerId = (_item['owner_id'] as num?)?.toInt();
    final String ownerName = (_item['owner_name'] ?? 'Lender').toString();

    if (itemId == null || ownerId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Item info is incomplete'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    try {
      final user = await api.getStoredUser();
      final currentUserId = (user?['id'] as num?)?.toInt();
      if (currentUserId == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please sign in first'),
            duration: Duration(seconds: 2),
          ),
        );
        return;
      }

      if (currentUserId == ownerId) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This is your own item'),
            duration: Duration(seconds: 2),
          ),
        );
        return;
      }

      final chat = await api.getOrCreateDirectChat(
        peerUserId: ownerId,
        itemId: itemId,
      );

      final chatId = (chat['id'] as num?)?.toInt();
      if (chatId == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to open chat now'),
            duration: Duration(seconds: 2),
          ),
        );
        return;
      }

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatConversationPage(
            chatId: chatId,
            peerName: ownerName,
            peerRating: _ownerRating.toStringAsFixed(1),
            peerAvatarUrl: _item['owner_avatar_url']?.toString(),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Open chat failed: $e'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _openBorrowRequest() async {
    final int? ownerId = (_item['owner_id'] as num?)?.toInt();

    try {
      final user = await api.getStoredUser();
      final currentUserId = (user?['id'] as num?)?.toInt();

      if (ownerId != null &&
          currentUserId != null &&
          ownerId == currentUserId) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This is your own item'),
            duration: Duration(seconds: 2),
          ),
        );
        return;
      }

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => BorrowingRequestPage(item: _item),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => BorrowingRequestPage(item: _item),
        ),
      );
    }
  }

  String? _optionalText(dynamic value) {
    final text = (value ?? '').toString().trim();
    return text.isEmpty ? null : text;
  }

  int? _toInt(dynamic value) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  String? _resolveMediaUrl(dynamic rawUrl) {
    final value = (rawUrl ?? '').toString().trim();
    if (value.isEmpty) return null;
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

  Future<void> _openImagePreview(String imageUrl, {int? itemId}) async {
    if (!mounted) return;
    final heroTag = 'item-image-${itemId ?? 'unknown'}';
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        pageBuilder: (context, animation, secondaryAnimation) {
          return _ImagePreviewPage(imageUrl: imageUrl, heroTag: heroTag);
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  Widget _buildVideoPlayerSection(String videoUrl) {
    if (kIsWeb) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Container(
          color: Colors.black,
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: InlineWebVideoPlayer(url: videoUrl),
          ),
        ),
      );
    }

    final controller = _videoController;
    final initialized = controller != null && controller.value.isInitialized;

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        color: Colors.black,
        child: AspectRatio(
          aspectRatio: initialized ? controller.value.aspectRatio : 16 / 9,
          child: _isVideoLoading
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                )
              : initialized
              ? Stack(
                  children: [
                    Positioned.fill(
                      child: GestureDetector(
                        onTap: () {
                          if (controller.value.isPlaying) {
                            controller.pause();
                          } else {
                            controller.play();
                          }
                          setState(() {});
                        },
                        child: VideoPlayer(controller),
                      ),
                    ),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: AnimatedOpacity(
                          opacity: controller.value.isPlaying ? 0 : 1,
                          duration: const Duration(milliseconds: 180),
                          child: const Center(
                            child: Icon(
                              Icons.play_circle_fill,
                              color: Colors.white,
                              size: 64,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: VideoProgressIndicator(
                        controller,
                        allowScrubbing: true,
                        colors: const VideoProgressColors(
                          playedColor: Colors.white,
                          bufferedColor: Colors.white38,
                          backgroundColor: Colors.white24,
                        ),
                      ),
                    ),
                  ],
                )
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _videoError ?? 'Unable to load this video',
                        style: const TextStyle(color: Colors.white),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: () => _configureVideoController(
                          videoUrl,
                          forceRetry: true,
                        ),
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Retry'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white54),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final int? itemId = _itemId;
    final String title = (_item['title'] ?? 'Item').toString();
    final dynamic pricePerDay = _item['price_per_day'];
    final dynamic depositAmount = _item['deposit_amount'];
    final num? rentalValue = pricePerDay is num ? pricePerDay : num.tryParse('$pricePerDay');
    final num? depositValue = depositAmount is num ? depositAmount : num.tryParse('$depositAmount');
    final String priceText = rentalValue != null ? 'RM${rentalValue.toStringAsFixed(2)}' : 'Price not set';
    final String depositText = depositValue != null ? 'RM${depositValue.toStringAsFixed(2)}' : 'RM0.00';
    final String? location = _optionalText(_item['location_text']);
    final String? category = _optionalText(_item['category']);
    final String? description = _optionalText(_item['description']);
    final String ownerName = (_item['owner_name'] ?? 'Lender').toString();
    final String? ownerAvatarUrl = _resolveMediaUrl(_item['owner_avatar_url']);
    final int? ownerId = (_item['owner_id'] as num?)?.toInt();
    final String ratingText = _ownerRating.toStringAsFixed(1);
    final String reviewCountText = '($_ownerReviewCount reviews)';
    final String? imageUrl = _resolveMediaUrl(_item['image_url']);
    final String? videoUrl = _resolveMediaUrl(_item['video_url']);

    final body = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      children: [
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        _buildHeader(itemId, imageUrl),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _buildOverviewCard(
            title: title,
            priceText: priceText,
            depositText: depositText,
            location: location,
            category: category,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildLenderCard(
                ownerName,
                ratingText,
                reviewCountText,
                ownerId,
                ownerAvatarUrl,
              ),
              const SizedBox(height: 12),
              if (description != null)
                _buildSectionBlock(
                  title: 'Description',
                  child: Text(
                    description,
                    style: TextStyle(
                      fontSize: 15,
                      color: Colors.grey[700],
                      height: 1.55,
                    ),
                  ),
                ),
              if (description != null && videoUrl != null)
                const SizedBox(height: 12),
              if (videoUrl != null)
                _buildSectionBlock(
                  title: 'Video',
                  child: _buildVideoPlayerSection(videoUrl),
                ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ],
    );

    return Scaffold(
      backgroundColor: Colors.grey[50],
      bottomNavigationBar: _buildBorrowButton(),
      body: _error != null
          ? SafeArea(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Failed to load item: $_error',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: _fetchDetail,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator(onRefresh: _fetchDetail, child: body),
    );
  }

  Widget _buildOverviewCard({
    required String title,
    required String priceText,
    required String depositText,
    required String? location,
    required String? category,
  }) {
    return Transform.translate(
      offset: const Offset(0, -30),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (location != null)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.location_on,
                              size: 16,
                              color: Colors.grey[500],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              location,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[700],
                              ),
                            ),
                          ],
                        ),
                      if (category != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0D9488).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            category,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF0D9488),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  priceText,
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0D9488),
                    height: 1,
                  ),
                ),
                Text(
                  '/ day',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Deposit',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[500],
                  ),
                ),
                Text(
                  depositText,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[800],
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionBlock({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8ECEF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.grey[850],
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildHeader(int? itemId, String? imageUrl) {
    final topInset = MediaQuery.of(context).padding.top;
    final heroTag = 'item-image-${itemId ?? 'unknown'}';
    return AspectRatio(
      aspectRatio: 16 / 10,
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              width: double.infinity,
              color: Colors.grey[200],
              child: imageUrl != null
                  ? GestureDetector(
                      onTap: () => _openImagePreview(imageUrl, itemId: itemId),
                      child: Hero(
                        tag: heroTag,
                        child: Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.broken_image_outlined,
                                    size: 48,
                                    color: Colors.grey[400],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Image unavailable',
                                    style: TextStyle(color: Colors.grey[500]),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    )
                  : Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.image, size: 60, color: Colors.grey[400]),
                          const SizedBox(height: 8),
                          Text(
                            itemId != null ? 'Item #$itemId' : 'Item Image',
                            style: TextStyle(color: Colors.grey[500]),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Container(
                height: topInset + 96,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.48),
                      Colors.black.withValues(alpha: 0.18),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: topInset + 8,
            left: 8,
            child: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_rounded),
              color: Colors.white,
              iconSize: 28,
              splashRadius: 22,
            ),
          ),
          Positioned(
            top: topInset + 8,
            right: 8,
            child: IconButton(
              onPressed: _toggleFavorite,
              icon: Icon(
                _isFavorite ? Icons.favorite : Icons.favorite_border,
              ),
              color: _isFavorite ? const Color(0xFFFF4D6D) : Colors.white,
              iconSize: 28,
              splashRadius: 22,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLenderCard(
    String ownerName,
    String ratingText,
    String reviewCountText,
    int? ownerId,
    String? ownerAvatarUrl,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 360;
        final profileLabel = isCompact ? 'Profile' : 'View Profile';

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE8ECEF)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: ownerAvatarUrl == null
                      ? const Color(0xFF0D9488).withValues(alpha: 0.12)
                      : Colors.grey[300],
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
                          ),
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ownerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 4,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Icon(
                          Icons.star,
                          size: 14,
                          color: Color(0xFFF4B400),
                        ),
                        Text(ratingText, style: const TextStyle(fontSize: 13)),
                        Text(
                          reviewCountText,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                    Text(
                      'Lender',
                      style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: ownerId == null
                    ? null
                    : () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => UserProfilePage(
                              userId: ownerId,
                              title: 'User Profile',
                              displayName: ownerName,
                            ),
                          ),
                        );
                      },
                child: Container(
                  constraints: BoxConstraints(maxWidth: isCompact ? 76 : 110),
                  padding: EdgeInsets.symmetric(
                    horizontal: isCompact ? 10 : 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    profileLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBorrowButton() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 18,
            spreadRadius: 1,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            height: 52,
            child: OutlinedButton(
              onPressed: _openDirectMessage,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.black87,
                side: BorderSide(color: Colors.grey[300]!),
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Icon(Icons.chat_bubble_outline, size: 22),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _openBorrowRequest,
                child: const Text(
                  'Request to Borrow',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImagePreviewPage extends StatelessWidget {
  const _ImagePreviewPage({required this.imageUrl, required this.heroTag});

  final String imageUrl;
  final String heroTag;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Center(
                  child: Hero(
                    tag: heroTag,
                    child: Image.network(
                      imageUrl,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return const Center(
                          child: Icon(
                            Icons.broken_image_outlined,
                            color: Colors.white70,
                            size: 56,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
                color: Colors.white,
                iconSize: 28,
                splashRadius: 22,
              ),
            ),
          ],
        ),
      ),
    );
  }
}




