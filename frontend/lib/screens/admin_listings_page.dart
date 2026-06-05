import 'package:flutter/material.dart';

import '../services/api.dart';
import '../services/api_client.dart' show defaultBaseUrl;

class AdminActiveListingsPage extends StatelessWidget {
  const AdminActiveListingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminListingsPage(
      title: 'Active Listings',
      availability: 'available',
    );
  }
}

class AdminUnavailableListingsPage extends StatelessWidget {
  const AdminUnavailableListingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminListingsPage(
      title: 'Unavailable Listings',
      availability: 'unavailable',
    );
  }
}

class AdminListingsPage extends StatefulWidget {
  final String title;
  final String availability;

  const AdminListingsPage({
    super.key,
    required this.title,
    required this.availability,
  });

  @override
  State<AdminListingsPage> createState() => _AdminListingsPageState();
}

class _AdminListingsPageState extends State<AdminListingsPage> {
  static const Color _ecoTeal = Color(0xFF0D9488);

  List<Map<String, dynamic>> _listings = <Map<String, dynamic>>[];
  final Set<int> _selectedIds = <int>{};
  bool _loading = true;
  bool _deleting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadListings();
  }

  Future<void> _loadListings() async {
    setState(() {
      _loading = true;
      _error = null;
      _selectedIds.clear();
    });

    try {
      final rows = await api.getAdminListings(
        availability: widget.availability,
      );
      if (!mounted) return;

      setState(() {
        _listings = rows
            .whereType<Map<String, dynamic>>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  int _itemId(Map<String, dynamic> item) => (item['id'] as num).toInt();

  String? _resolveMediaUrl(dynamic raw) {
    final value = (raw ?? '').toString().trim();
    if (value.isEmpty) return null;
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    if (value.startsWith('/')) return '$defaultBaseUrl$value';
    return '$defaultBaseUrl/$value';
  }

  int _gridColumns(double width) {
    if (width >= 1200) return 3;
    if (width >= 900) return 2;
    return 1;
  }

  double _cardHeight(double width) {
    if (width >= 1200) return 132;
    if (width >= 900) return 126;
    return 120;
  }

  String _normalizeLabel(dynamic raw) {
    return (raw ?? '').toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _formatUpdatedDate(dynamic raw) {
    final value = (raw ?? '').toString().trim();
    if (value.isEmpty) return '';
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return value;
    final year = parsed.year.toString().padLeft(4, '0');
    final month = parsed.month.toString().padLeft(2, '0');
    final day = parsed.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  String _availabilityLabel(String raw) {
    final value = raw.trim().toLowerCase();
    if (value.isEmpty) return '';
    if (value.length == 1) return value.toUpperCase();
    return '${value[0].toUpperCase()}${value.substring(1)}';
  }

  void _toggleSelection(int id, bool selected) {
    setState(() {
      if (selected) {
        _selectedIds.add(id);
      } else {
        _selectedIds.remove(id);
      }
    });
  }

  Future<void> _confirmDeleteAll() async {
    final count = _selectedIds.length;
    if (count == 0) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Selected Listings'),
          content: Text(
            'Are you sure you want to delete $count items? This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete All'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    await _deleteSelected();
  }

  Future<void> _deleteSelected() async {
    if (_deleting || _selectedIds.isEmpty) return;

    setState(() {
      _deleting = true;
    });

    try {
      final result = await api.deleteAdminListingsBulk(_selectedIds.toList());
      final deletedIds =
          (result['deleted_ids'] as List<dynamic>? ?? <dynamic>[])
              .whereType<num>()
              .map((id) => id.toInt())
              .toSet();
      final skippedCount = (result['skipped_count'] as num?)?.toInt() ?? 0;
      final notificationsSent =
          (result['notifications_sent'] as num?)?.toInt() ?? 0;

      if (!mounted) return;

      setState(() {
        _listings.removeWhere((item) => deletedIds.contains(_itemId(item)));
        _selectedIds.clear();
      });

      final message = skippedCount > 0
          ? '${deletedIds.length} items deleted, $skippedCount skipped (linked to existing orders). Owners notified: $notificationsSent.'
          : '${deletedIds.length} items deleted successfully. Owners notified: $notificationsSent.';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: skippedCount > 0
              ? Colors.orange[700]
              : Colors.green[700],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Failed to delete selected items.'),
          backgroundColor: Colors.red[700],
        ),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _deleting = false;
      });
    }
  }

  Widget _buildItemCard(Map<String, dynamic> item) {
    final id = _itemId(item);
    final selected = _selectedIds.contains(id);
    final rawTitle = _normalizeLabel(item['title']);
    final title = rawTitle.isEmpty ? 'Untitled' : rawTitle;
    final imageUrl = _resolveMediaUrl(item['image_url']);
    final ownerName = _normalizeLabel(item['owner_name']);
    final availability = _availabilityLabel((item['availability'] ?? '').toString());
    final updatedLabel = _formatUpdatedDate(item['updated_at']);
    final metaParts = <String>[];
    if (ownerName.isNotEmpty) {
      metaParts.add('Owner: $ownerName');
    }
    if (updatedLabel.isNotEmpty) {
      metaParts.add('Updated: $updatedLabel');
    }
    final metaText = metaParts.join(' | ');
    final isAvailable = availability.toLowerCase() == 'available';

    return GestureDetector(
      onTap: () => _toggleSelection(id, !selected),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFF0FBFA) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? _ecoTeal : Colors.grey.withValues(alpha: 0.2),
            width: selected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 84,
                  height: 84,
                  color: Colors.grey[200],
                  child: imageUrl == null
                      ? const Icon(
                          Icons.image_not_supported_outlined,
                          size: 36,
                          color: Colors.grey,
                        )
                      : Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) {
                            return const Icon(
                              Icons.broken_image_outlined,
                              size: 36,
                              color: Colors.grey,
                            );
                          },
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[900],
                              height: 1.3,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 26,
                          height: 26,
                          child: Checkbox(
                            value: selected,
                            activeColor: _ecoTeal,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                            onChanged: (checked) =>
                                _toggleSelection(id, checked ?? false),
                          ),
                        ),
                      ],
                    ),
                    if (metaText.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        metaText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                    if (availability.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: isAvailable
                              ? const Color(0xFFE6F6F4)
                              : Colors.grey[200],
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          availability,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isAvailable ? _ecoTeal : Colors.grey[700],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4FBFA),
      appBar: AppBar(
        backgroundColor: _ecoTeal,
        foregroundColor: Colors.white,
        title: Text(widget.title),
        actions: [
          IconButton(
            onPressed: _loading ? null : _loadListings,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: _ecoTeal,
        onRefresh: _loadListings,
        child: Builder(
          builder: (context) {
            if (_loading) {
              return const Center(child: CircularProgressIndicator());
            }

            if (_error != null) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 120),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        children: [
                          const Icon(Icons.error_outline, color: Colors.red),
                          const SizedBox(height: 10),
                          Text(
                            'Failed to load listings\n$_error',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: _loadListings,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _ecoTeal,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            }

            if (_listings.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 120),
                  Center(
                    child: Text('No listings available in this category.'),
                  ),
                ],
              );
            }

            return LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final crossAxisCount = _gridColumns(width);
                final cardHeight = _cardHeight(width);

                return GridView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    16,
                    16,
                    16,
                    _selectedIds.isEmpty ? 20 : 100,
                  ),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    mainAxisExtent: cardHeight,
                  ),
                  itemCount: _listings.length,
                  itemBuilder: (context, index) =>
                      _buildItemCard(_listings[index]),
                );
              },
            );
          },
        ),
      ),
      bottomNavigationBar: _selectedIds.isEmpty
          ? null
          : SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    top: BorderSide(color: Colors.grey.withValues(alpha: 0.25)),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_selectedIds.length} items selected',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: _ecoTeal,
                        ),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: _deleting ? null : _confirmDeleteAll,
                      icon: _deleting
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.delete_outline),
                      label: const Text('Delete All'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
