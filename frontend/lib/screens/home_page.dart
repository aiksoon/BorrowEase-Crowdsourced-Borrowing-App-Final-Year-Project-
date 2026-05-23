import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../services/api.dart';
import '../services/api_client.dart' show defaultBaseUrl;
import 'screens.dart';

const Color _ecoTeal = Color(0xFF0D9488);

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int selectedCategoryIndex = 0;
  bool _isLoading = false;
  bool _refreshing = false;
  String? _error;
  String _userLocation = '';
  List<dynamic> items = [];
  int? _hoveredCardIndex;

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _minPriceController = TextEditingController();
  final TextEditingController _maxPriceController = TextEditingController();

  String? _currentQuery;
  String? _currentCategory;
  double? _minRating;

  final List<Map<String, dynamic>> categories = const [
    {'icon': Icons.all_inclusive, 'label': 'All'},
    {'icon': Icons.build, 'label': 'Tools'},
    {'icon': Icons.devices, 'label': 'Electronics'},
    {'icon': Icons.menu_book, 'label': 'Books'},
    {'icon': Icons.chair_alt, 'label': 'Furniture'},
    {'icon': Icons.sports_soccer, 'label': 'Sports'},
    {'icon': Icons.directions_car_filled, 'label': 'Automotive'},
    {'icon': Icons.style, 'label': 'Fashion'},
    {'icon': Icons.music_note, 'label': 'Music'},
  ];

  bool get _hasFilters =>
      _minRating != null ||
      _minPriceController.text.isNotEmpty ||
      _maxPriceController.text.isNotEmpty;

  List<dynamic> get _filteredItems {
    final minPrice = double.tryParse(_minPriceController.text.trim());
    final maxPrice = double.tryParse(_maxPriceController.text.trim());

    return items.where((item) {
      final price = (item['price_per_day'] is num)
          ? (item['price_per_day'] as num).toDouble()
          : double.tryParse('${item['price_per_day']}');

      if (minPrice != null && (price == null || price < minPrice)) {
        return false;
      }
      if (maxPrice != null && (price == null || price > maxPrice)) {
        return false;
      }

      if (_minRating != null) {
        final ratingValue = (item['rating'] is num)
            ? (item['rating'] as num).toDouble()
            : double.tryParse('${item['rating']}');
        if (ratingValue == null || ratingValue < _minRating!) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _loadUserLocation();
    _loadItems();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _minPriceController.dispose();
    _maxPriceController.dispose();
    super.dispose();
  }

  Future<void> _loadItems({
    String? query,
    String? category,
    bool silent = false,
  }) async {
    final effectiveQuery = query ?? _currentQuery;
    final effectiveCategory =
        category ??
        _currentCategory ??
        categories[selectedCategoryIndex]['label'] as String?;

    _currentQuery = effectiveQuery;
    _currentCategory = effectiveCategory;

    final hasContent = items.isNotEmpty;
    setState(() {
      if (!silent && !hasContent) {
        _isLoading = true;
      } else {
        _refreshing = true;
      }
      _error = null;
    });

    try {
      final results = await api.getItems(
        query: (effectiveQuery != null && effectiveQuery.isNotEmpty)
            ? effectiveQuery
            : null,
        category: (effectiveCategory != null && effectiveCategory != 'All')
            ? effectiveCategory
            : null,
        availableOnly: true,
      );

      if (!mounted) return;
      setState(() {
        items = results;
      });
    } catch (e) {
      if (!mounted) return;
      String errorMsg = e.toString();
      if (e is DioException) {
        errorMsg = 'HTTP ${e.response?.statusCode ?? "Error"}: ${e.message}\n${e.response?.data}';
      }
      print('[HomePageError] $errorMsg'); // Debug log
      setState(() {
        _error = errorMsg;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _refreshing = false;
        });
      }
    }
  }

  Future<void> _loadUserLocation() async {
    final cachedUser = await api.getStoredUser();
    if (!mounted) return;

    setState(() {
      _userLocation = (cachedUser?['location'] ?? '').toString().trim();
    });

    try {
      final data = await api.getMe();
      if (!mounted) return;
      final latestUser = data['user'] as Map<String, dynamic>?;
      setState(() {
        _userLocation = (latestUser?['location'] ?? '').toString().trim();
      });
    } catch (_) {
      // Keep cached location when profile refresh fails.
    }
  }

  String? _resolveMediaUrl(dynamic rawUrl) {
    final value = (rawUrl ?? '').toString().trim();
    if (value.isEmpty) return null;
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    // Remove leading slash to avoid double slashes
    final cleanValue = value.startsWith('/') ? value.substring(1) : value;
    final baseUrl = defaultBaseUrl.endsWith('/') 
        ? defaultBaseUrl.substring(0, defaultBaseUrl.length - 1)
        : defaultBaseUrl;
    return '$baseUrl/$cleanValue';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final created = await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const ListItemPage()),
          );
          if (created == true) {
            await _loadItems(silent: true);
          }
        },
        backgroundColor: _ecoTeal,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'BorrowEase',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.location_on, size: 14, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          _userLocation.isEmpty ? 'Location not set' : _userLocation,
                          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: TextField(
                        controller: _searchController,
                        textInputAction: TextInputAction.search,
                        textAlignVertical: TextAlignVertical.center,
                        style: const TextStyle(fontSize: 14),
                        onSubmitted: (value) => _loadItems(
                          query: value.trim(),
                          category: _currentCategory ??
                              categories[selectedCategoryIndex]['label'] as String?,
                          silent: true,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Search items by keywords',
                          hintStyle: TextStyle(fontSize: 14, color: Colors.grey[600]),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 14),
                          prefixIcon: const Icon(Icons.search, color: Colors.grey),
                          suffixIcon: _searchController.text.isNotEmpty ||
                                  (_currentQuery != null && _currentQuery!.isNotEmpty)
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  color: Colors.grey[600],
                                  onPressed: () {
                                    _searchController.clear();
                                    _loadItems(
                                      query: '',
                                      category: _currentCategory ??
                                          categories[selectedCategoryIndex]['label']
                                              as String?,
                                      silent: true,
                                    );
                                  },
                                )
                              : null,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    height: 48,
                    width: 48,
                    decoration: BoxDecoration(
                      color: _hasFilters ? _ecoTeal : _ecoTeal.withValues(alpha: 0.88),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.tune, color: Colors.white),
                      onPressed: () => _showFilterDialog(context),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            SizedBox(
              height: 40,
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(
                  dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse},
                ),
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: categories.length,
                  itemBuilder: (context, index) {
                    final isSelected = selectedCategoryIndex == index;
                    return GestureDetector(
                      onTap: () {
                        setState(() => selectedCategoryIndex = index);
                        _loadItems(
                          query: _currentQuery,
                          category: categories[index]['label'] as String,
                          silent: true,
                        );
                      },
                      child: Container(
                        margin: const EdgeInsets.only(right: 12),
                        padding:
                            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected ? _ecoTeal.withValues(alpha: 0.12) : Colors.grey[100],
                          borderRadius: BorderRadius.circular(12),
                          border: isSelected
                              ? Border.all(
                                  color: _ecoTeal.withValues(alpha: 0.35),
                                  width: 1,
                                )
                              : null,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              categories[index]['icon'] as IconData,
                              size: 18,
                              color: isSelected ? _ecoTeal : Colors.grey[600],
                            ),
                            const SizedBox(width: 8),
                            Text(
                              categories[index]['label'] as String,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: isSelected ? _ecoTeal : Colors.grey[700],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            const SizedBox(height: 20),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'All Items',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  Text(
                    _isLoading ? 'Loading...' : '${_filteredItems.length} items',
                    style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            if (_refreshing && !_isLoading)
              const LinearProgressIndicator(minHeight: 2),

            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildItemsContent(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemsContent() {
    if (_isLoading && items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Failed to load items', style: TextStyle(color: Colors.red[400])),
            const SizedBox(height: 8),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _loadItems,
              child: const Text('Retry', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    }

    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('No items yet'),
            const SizedBox(height: 8),
            Text('Tap + to list an item', style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _loadItems, child: const Text('Refresh')),
          ],
        ),
      );
    }

    final visibleItems = _filteredItems;
    if (visibleItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('No items match your filter'),
            const SizedBox(height: 8),
            Text(
              'Adjust price range or rating and try again',
              style: TextStyle(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadItems(silent: true),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          mainAxisExtent: 276,
        ),
        itemCount: visibleItems.length,
        itemBuilder: (context, index) {
          return _buildItemCard(
            visibleItems[index] as Map<String, dynamic>,
            index: index,
          );
        },
      ),
    );
  }

  Widget _buildItemCard(Map<String, dynamic> item, {required int index}) {
    final pricePerDay = item['price_per_day'];
    final depositAmount = item['deposit_amount'];
    final title = (item['title'] ?? '') as String;
    final location = (item['location_text'] ?? 'Location unavailable').toString();
    final imageUrl = _resolveMediaUrl(item['image_url']);
    final rating = item['rating']?.toString() ?? '-';

    final num? rental =
        pricePerDay is num ? pricePerDay : num.tryParse('$pricePerDay');
    final num? deposit =
        depositAmount is num ? depositAmount : num.tryParse('$depositAmount');

    final priceText =
        rental != null ? 'RM${rental.toStringAsFixed(0)} / day' : 'No price';
    final depositText = 'Deposit RM${(deposit ?? 0).toStringAsFixed(0)}';
    final placeholderLabel = item['id'] != null ? 'Item ${item['id']}' : 'No image';
    final isHovered = _hoveredCardIndex == index;

    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredCardIndex = index),
      onExit: (_) {
        if (_hoveredCardIndex == index) {
          setState(() => _hoveredCardIndex = null);
        }
      },
      child: GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => ItemDetailsPage(item: item)),
          );
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          transform: Matrix4.translationValues(0, isHovered ? -4 : 0, 0),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isHovered ? _ecoTeal.withValues(alpha: 0.35) : Colors.grey[200]!,
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isHovered ? 0.11 : 0.05),
                blurRadius: isHovered ? 16 : 10,
                offset: Offset(0, isHovered ? 6 : 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 140,
                width: double.infinity,
                child: Stack(
                  children: [
                    if (imageUrl != null)
                      ClipRRect(
                        borderRadius:
                            const BorderRadius.vertical(top: Radius.circular(12)),
                        child: Image.network(
                          imageUrl,
                          width: double.infinity,
                          height: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) {
                            return Container(
                              width: double.infinity,
                              color: Colors.grey[200],
                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.broken_image_outlined,
                                      size: 34,
                                      color: Colors.grey[400],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Image unavailable',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      )
                    else
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius:
                              const BorderRadius.vertical(top: Radius.circular(12)),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.image, size: 40, color: Colors.grey[400]),
                              const SizedBox(height: 4),
                              Text(
                                placeholderLabel,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          item['category']?.toString() ?? 'General',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        priceText,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey[900],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        depositText,
                        style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                      ),
                      const Spacer(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Icon(
                                  Icons.location_on,
                                  size: 14,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    location,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Row(
                            children: [
                              const Icon(
                                Icons.star,
                                size: 14,
                                color: Color(0xFFF4B400),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                rating,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey[700],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showFilterDialog(BuildContext context) {
    final ratings = [4.5, 4.0, 3.5, null];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        double? localRating = _minRating;
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: StatefulBuilder(
            builder: (context, setModalState) {
              return SingleChildScrollView(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Filter Items',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Price Range (per day)',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _minPriceController,
                              decoration: InputDecoration(
                                hintText: 'Min',
                                prefixText: 'RM ',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              keyboardType: const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _maxPriceController,
                              decoration: InputDecoration(
                                hintText: 'Max',
                                prefixText: 'RM ',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              keyboardType: const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Minimum rating',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        children: ratings.map((rating) {
                          final label =
                              rating == null ? 'Any' : '>= ${rating.toStringAsFixed(1)}';
                          final selected = localRating == rating;
                          return ChoiceChip(
                            label: Text(label),
                            selected: selected,
                            onSelected: (_) {
                              setModalState(() {
                                localRating = rating;
                              });
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                setState(() {
                                  _minPriceController.clear();
                                  _maxPriceController.clear();
                                  _minRating = null;
                                });
                                Navigator.pop(context);
                                _loadItems(silent: true);
                              },
                              child: const Text('Clear'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  _minRating = localRating;
                                });
                                Navigator.pop(context);
                              },
                              child: const Text('Apply'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
