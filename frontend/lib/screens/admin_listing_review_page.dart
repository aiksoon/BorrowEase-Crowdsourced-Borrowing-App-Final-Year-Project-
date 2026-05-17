import 'package:flutter/material.dart';

// ==================== ADMIN LISTING REVIEW PAGE ====================
class AdminListingReviewPage extends StatelessWidget {
  final String title;
  final String owner;
  final String price;

  const AdminListingReviewPage({
    super.key,
    required this.title,
    required this.owner,
    required this.price,
  });

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
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.arrow_back),
                  ),
                  const SizedBox(width: 16),
                  const Text(
                    'Review Listing',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Item Images
                    Container(
                      height: 200,
                      color: Colors.grey[300],
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.image, size: 48, color: Colors.grey[500]),
                            const SizedBox(height: 8),
                            Text('Item Photos (3)', style: TextStyle(color: Colors.grey[600])),
                          ],
                        ),
                      ),
                    ),

                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Title and Price
                          Text(
                            title,
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            price,
                            style: TextStyle(fontSize: 18, color: Colors.green[600], fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          Text(owner, style: TextStyle(color: Colors.grey[600])),

                          const SizedBox(height: 24),

                          // Listing Details Section
                          _buildSectionTitle('Listing Details'),
                          const SizedBox(height: 12),
                          _buildDetailRow('Category', 'Electronics'),
                          _buildDetailRow('Condition', 'Like New'),
                          _buildDetailRow('Location', 'Kuala Lumpur, MY'),
                          _buildDetailRow('Submitted', '1 hour ago'),

                          const SizedBox(height: 24),

                          // Description
                          _buildSectionTitle('Description'),
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'Professional-grade camera kit including camera body, two lenses (18-55mm and 55-200mm), tripod, and carrying case. Perfect for events, photography sessions, and video production. All equipment is well-maintained and in excellent working condition.',
                              style: TextStyle(height: 1.5),
                            ),
                          ),

                          const SizedBox(height: 24),

                          // Lender Information
                          _buildSectionTitle('Lender Information'),
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 50,
                                  height: 50,
                                  decoration: BoxDecoration(
                                    color: Colors.grey[200],
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(Icons.person, color: Colors.grey[400]),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(owner.replaceFirst('by ', ''), style: const TextStyle(fontWeight: FontWeight.w600)),
                                      Row(
                                        children: [
                                          Icon(Icons.verified, size: 14, color: Colors.green[600]),
                                          const SizedBox(width: 4),
                                          Text('KYC Verified', style: TextStyle(fontSize: 12, color: Colors.green[600])),
                                        ],
                                      ),
                                      Text('Member since Jan 2024', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 24),

                          // Moderation Notes
                          _buildSectionTitle('Moderation Notes (Optional)'),
                          const SizedBox(height: 12),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: TextField(
                              maxLines: 3,
                              decoration: InputDecoration(
                                hintText: 'Add notes or reason for rejection...',
                                hintStyle: TextStyle(color: Colors.grey[400]),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                                filled: true,
                                fillColor: Colors.white,
                              ),
                            ),
                          ),

                          const SizedBox(height: 32),

                          // Action Buttons
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () {
                                    _showConfirmationDialog(
                                      context,
                                      'Reject Listing',
                                      'Are you sure you want to reject this listing? The lender will be notified.',
                                      Colors.red,
                                      'Rejected',
                                    );
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red[50],
                                    foregroundColor: Colors.red,
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    elevation: 0,
                                  ),
                                  child: const Text('Reject'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () {
                                    _showConfirmationDialog(
                                      context,
                                      'Request Changes',
                                      'Send feedback to the lender requesting modifications to this listing?',
                                      const Color(0xFF0D9488),
                                      'Changes Requested',
                                    );
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFE6F4F2),
                                    foregroundColor: const Color(0xFF0D9488),
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    elevation: 0,
                                  ),
                                  child: const Text('Request Changes'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () {
                                _showConfirmationDialog(
                                  context,
                                  'Approve Listing',
                                  'Are you sure you want to approve this listing? It will be visible to all users.',
                                  Colors.green,
                                  'Approved',
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text('Approve Listing'),
                            ),
                          ),

                          const SizedBox(height: 16),
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

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600])),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  void _showConfirmationDialog(BuildContext context, String title, String message, Color color, String action) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[600])),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              // Show success message
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Listing $action successfully'),
                  backgroundColor: color,
                ),
              );
              Navigator.pop(context); // Go back to dashboard
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('Confirm'),
          ),
        ],
      ),
    );
  }
}


