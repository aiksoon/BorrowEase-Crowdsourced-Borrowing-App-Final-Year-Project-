import 'package:flutter/material.dart';

import '../services/api.dart';

class ItemReviewsPage extends StatefulWidget {
  final int ownerId;
  final String ownerName;
  final String itemTitle;

  const ItemReviewsPage({
    super.key,
    required this.ownerId,
    required this.ownerName,
    required this.itemTitle,
  });

  @override
  State<ItemReviewsPage> createState() => _ItemReviewsPageState();
}

class _ItemReviewsPageState extends State<ItemReviewsPage> {
  List<dynamic> _reviews = <dynamic>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh({bool silent = false}) async {
    try {
      final latest = await api.getReviews(userId: widget.ownerId);
      if (!mounted) return;
      setState(() {
        _reviews = latest;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.arrow_back),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Reviews',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'For ${widget.itemTitle} - Lender ${widget.ownerName}',
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
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
                    if (_error != null && _reviews.isEmpty) {
                      return ListView(
                        children: [
                          const SizedBox(height: 160),
                          Center(
                            child: Column(
                              children: [
                                Text('Failed to load reviews: $_error'),
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

                    if (_reviews.isEmpty) {
                      return ListView(
                        children: const [
                          SizedBox(height: 160),
                          Center(child: Text('No reviews yet')),
                        ],
                      );
                    }

                    final stats = _buildStats(_reviews);
                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _reviews.length + 1,
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return _RatingSummary(stats['average'] as double, stats['count'] as int, stats['distribution'] as Map<int, int>);
                        }
                        final review = _reviews[index - 1] as Map<String, dynamic>;
                        final name = review['reviewer_name']?.toString() ?? 'User';
                        final rating = (review['rating'] as num?)?.toInt() ?? 0;
                        final comment = review['comment']?.toString() ?? '';
                        final createdAt = review['created_at']?.toString() ?? '';
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.grey[50],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: Colors.grey[300],
                                      shape: BoxShape.circle,
                                    ),
                                    child: Center(
                                      child: Text(
                                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[600]),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                        Row(
                                          children: [
                                            ...List.generate(rating, (i) => const Icon(Icons.star, color: Color(0xFFF4B400), size: 14)),
                                            const SizedBox(width: 8),
                                            Text(
                                              createdAt.isNotEmpty ? createdAt.split('T').first : '',
                                              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              if (comment.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Text(comment, style: TextStyle(color: Colors.grey[700], height: 1.4)),
                              ],
                            ],
                          ),
                        );
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

  Map<String, Object> _buildStats(List<dynamic> reviews) {
    if (reviews.isEmpty) {
      return {
        'average': 0.0,
        'count': 0,
        'distribution': {for (var i = 1; i <= 5; i++) i: 0},
      };
    }
    double total = 0;
    final dist = {for (var i = 1; i <= 5; i++) i: 0};
    for (final r in reviews) {
      final rating = (r is Map<String, dynamic> ? (r['rating'] as num?)?.toInt() : null) ?? 0;
      dist[rating] = (dist[rating] ?? 0) + 1;
      total += rating;
    }
    final count = reviews.length;
    return {
      'average': count == 0 ? 0.0 : total / count,
      'count': count,
      'distribution': dist,
    };
  }
}

class _RatingSummary extends StatelessWidget {
  final double average;
  final int count;
  final Map<int, int> distribution;

  const _RatingSummary(this.average, this.count, this.distribution);

  @override
  Widget build(BuildContext context) {
    final avgText = average.toStringAsFixed(1);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFE6F4F2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Column(
            children: [
              Text(avgText, style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold)),
              Row(
                children: List.generate(5, (i) => Icon(
                      i < average.round() ? Icons.star : Icons.star_border,
                      color: const Color(0xFFF4B400),
                      size: 16,
                    )),
              ),
              const SizedBox(height: 4),
              Text('$count reviews', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
            ],
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              children: [
                for (var i = 5; i >= 1; i--)
                  _buildRatingBar(i.toString(), count == 0 ? 0 : (distribution[i] ?? 0) / count),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRatingBar(String label, double value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontSize: 11)),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 6,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(3),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: value.clamp(0, 1),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4B400),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


