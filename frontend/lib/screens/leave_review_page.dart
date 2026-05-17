import 'package:flutter/material.dart';
import 'package:dio/dio.dart';

import '../services/api.dart';

// ==================== LEAVE REVIEW PAGE ====================
class LeaveReviewPage extends StatefulWidget {
  final String reviewType; // 'lender', 'borrower', or 'item'
  final String targetName;
  final int? requestId;
  final int? revieweeId;

  const LeaveReviewPage({
    super.key,
    this.requestId,
    this.revieweeId,
    this.reviewType = 'lender',
    this.targetName = 'John Doe',
  });

  @override
  State<LeaveReviewPage> createState() => _LeaveReviewPageState();
}

class _LeaveReviewPageState extends State<LeaveReviewPage> {
  int selectedRating = 0;
  final TextEditingController _commentController = TextEditingController();
  final Set<String> _selectedQuickTags = <String>{};
  bool _submitting = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  String get titleText {
    switch (widget.reviewType) {
      case 'item':
        return 'How was the item?';
      case 'borrower':
        return 'How was the borrower?';
      default:
        return 'How was your experience with';
    }
  }

  List<String> get quickTags {
    switch (widget.reviewType) {
      case 'item':
        return ['As described', 'Good condition', 'Clean', 'Easy to use', 'Worth the price'];
      case 'borrower':
        return ['Respectful', 'On time', 'Good communication', 'Returned in good condition', 'Trustworthy'];
      default:
        return ['Great communication', 'On time', 'Item as described', 'Friendly', 'Would borrow again'];
    }
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
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.arrow_back),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    'Review ${widget.reviewType == 'item' ? 'Item' : widget.reviewType == 'borrower' ? 'Borrower' : 'Lender'}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    // Avatar/Icon
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        shape: widget.reviewType == 'item' ? BoxShape.rectangle : BoxShape.circle,
                        borderRadius: widget.reviewType == 'item' ? BorderRadius.circular(12) : null,
                      ),
                      child: Icon(
                        widget.reviewType == 'item' ? Icons.build : Icons.person,
                        size: 40,
                        color: Colors.grey[500],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      titleText,
                      style: const TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    Text(
                      '${widget.targetName}?',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),

                    const SizedBox(height: 24),

                    // Star Rating
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(5, (index) {
                        return GestureDetector(
                          onTap: () => setState(() => selectedRating = index + 1),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Icon(
                              index < selectedRating ? Icons.star : Icons.star_outline,
                              size: 40,
                              color: const Color(0xFFF4B400),
                            ),
                          ),
                        );
                      }),
                    ),

                    const SizedBox(height: 8),
                    Text(
                      selectedRating == 0
                          ? 'Tap to rate'
                          : selectedRating == 5
                              ? 'Excellent!'
                              : selectedRating == 4
                                  ? 'Great!'
                                  : selectedRating == 3
                                      ? 'Good'
                                      : selectedRating == 2
                                          ? 'Fair'
                                          : 'Poor',
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    ),

                    const SizedBox(height: 32),

                    // Review Text Field
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: TextField(
                        controller: _commentController,
                        maxLines: 5,
                        decoration: InputDecoration(
                          hintText: 'Write your review here... (optional)',
                          hintStyle: TextStyle(color: Colors.grey[400]),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.all(16),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Quick Tags
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Quick tags', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: quickTags.map((tag) => _buildTag(tag)).toList(),
                    ),
                  ],
                ),
              ),
            ),

            // Submit Button
            Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                      onPressed: selectedRating > 0 && !_submitting ? _submit : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0D9488),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey[300],
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                      child: Text(
                        _submitting ? 'Submitting...' : 'Submit Review',
                        style: const TextStyle(fontSize: 16),
                      ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTag(String text) {
    final isSelected = _selectedQuickTags.contains(text);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _applyQuickTag(text),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFE6F4F2) : const Color(0xFFF2FBFA),
          borderRadius: BorderRadius.circular(12),
          border: isSelected
              ? Border.all(color: const Color(0xFF7CCFC6), width: 1)
              : null,
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            color: const Color(0xFF0F766E),
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  void _applyQuickTag(String tag) {
    final current = _commentController.text.trim();
    if (current.contains(tag)) {
      setState(() {
        _selectedQuickTags.add(tag);
      });
      return;
    }

    final next = current.isEmpty ? tag : '$current, $tag';
    _commentController
      ..text = next
      ..selection = TextSelection.collapsed(offset: next.length);

    setState(() {
      _selectedQuickTags.add(tag);
    });
  }

  Future<void> _submit() async {
    if (widget.requestId == null || widget.revieweeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Missing request info; cannot submit review yet.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      await api.createReview(
        requestId: widget.requestId!,
        revieweeId: widget.revieweeId!,
        rating: selectedRating,
        comment: _commentController.text.trim().isEmpty ? null : _commentController.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Review submitted'), // success notification
          duration: Duration(seconds: 2),
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      if (e is DioException && e.response?.statusCode == 409) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Review already submitted for this order.'),
            duration: Duration(seconds: 2),
          ),
        );
        Navigator.pop(context, true);
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Submit failed: $e'),
          duration: const Duration(seconds: 2),
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}


