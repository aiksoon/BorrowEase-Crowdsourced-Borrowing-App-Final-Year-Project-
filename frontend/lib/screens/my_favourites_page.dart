import 'package:flutter/material.dart';

import '../services/api.dart';
import '../services/api_client.dart' show defaultBaseUrl;
import '../services/favorites_events.dart';
import 'screens.dart';

class MyFavouritesPage extends StatefulWidget {
  const MyFavouritesPage({super.key});

  @override
  State<MyFavouritesPage> createState() => _MyFavouritesPageState();
}

class _MyFavouritesPageState extends State<MyFavouritesPage> {
  List<Map<String, dynamic>> _items = <Map<String, dynamic>>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final list = await api.getFavorites();
    return list.cast<Map<String, dynamic>>();
  }

  Future<void> _refresh({bool silent = false}) async {
    try {
      final latest = await _load();
      if (!mounted) return;
      setState(() {
        _items = latest;
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

  Future<void> _remove(int id) async {
    try {
      await api.removeFavorite(id);
      notifyFavoritesChanged();
      if (!mounted) return;
      await _refresh(silent: true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Removed from favourites'),
          duration: Duration(seconds: 1),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to remove: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.arrow_back),
                  ),
                  const SizedBox(width: 16),
                  const Text(
                    'My Favourites',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => _refresh(silent: true),
                child: Builder(
                  builder: (context) {
                    if (_loading) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (_error != null && _items.isEmpty) {
                      return ListView(
                        children: [
                          const SizedBox(height: 160),
                          Center(
                            child: Column(
                              children: [
                                Text('Failed to load favourites: $_error'),
                                const SizedBox(height: 8),
                                ElevatedButton(
                                  onPressed: () => _refresh(),
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    }

                    if (_items.isEmpty) {
                      return ListView(
                        children: const [
                          SizedBox(height: 160),
                          Center(child: Text('No favourites yet')),
                        ],
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _items.length,
                      itemBuilder: (context, index) {
                        final item = _items[index];
                        return _buildFavouriteItem(context, item);
                      },
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

  Widget _buildFavouriteItem(BuildContext context, Map<String, dynamic> item) {
    final title = item['title']?.toString() ?? 'Item';
    final priceValue = item['price_per_day'];
    final depositValue = item['deposit_amount'];
    final num? rental = priceValue is num ? priceValue : num.tryParse('$priceValue');
    final num? deposit = depositValue is num ? depositValue : num.tryParse('$depositValue');
    final price = rental == null ? 'RM -' : 'RM${rental.toStringAsFixed(2)} / day';
    final depositText = 'Deposit RM${(deposit ?? 0).toStringAsFixed(2)}';
    final rating = _toDouble(item['rating'], fallback: 5.0);
    final reviewCount = _toInt(item['review_count'], fallback: 0);
    final lender = item['owner_name']?.toString() ?? 'Lender';
    final id = _toIntOrNull(item['id']);
    final imageUrl = _resolveMediaUrl(item['image_url']);

    return GestureDetector(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => ItemDetailsPage(item: item)),
        );
        if (!mounted) return;
        await _refresh(silent: true);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                ),
              ),
              child: imageUrl == null
                  ? Icon(Icons.image, size: 40, color: Colors.grey[400])
                  : ClipRRect(
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(12),
                        bottomLeft: Radius.circular(12),
                      ),
                      child: Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Icon(
                          Icons.broken_image_outlined,
                          size: 40,
                          color: Colors.grey[400],
                        ),
                      ),
                    ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      price,
                      style: TextStyle(
                        color: Colors.green[600],
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      depositText,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.star,
                          size: 14,
                          color: Color(0xFFF4B400),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${rating.toStringAsFixed(1)} ($reviewCount)',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '• $lender',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: GestureDetector(
                onTap: id == null ? null : () => _remove(id),
                child: const Icon(Icons.favorite, color: Colors.red, size: 24),
              ),
            ),
          ],
        ),
      ),
    );
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

  double _toDouble(dynamic value, {double fallback = 0}) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? fallback;
    return fallback;
  }

  int _toInt(dynamic value, {int fallback = 0}) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  int? _toIntOrNull(dynamic value) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}
