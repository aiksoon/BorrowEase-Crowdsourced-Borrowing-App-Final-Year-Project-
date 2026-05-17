import 'package:flutter/material.dart';

import '../services/api.dart';
import '../services/api_client.dart' show defaultBaseUrl;

// ==================== ADMIN KYC REVIEW PAGE ====================
class AdminKYCReviewPage extends StatefulWidget {
  final int userId;
  final String userName;

  const AdminKYCReviewPage({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<AdminKYCReviewPage> createState() => _AdminKYCReviewPageState();
}

class _AdminKYCReviewPageState extends State<AdminKYCReviewPage> {
  Map<String, dynamic>? _kyc;
  bool _loading = true;
  String? _error;
  bool _updating = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<Map<String, dynamic>> _load() async {
    return api.getKycByUserId(widget.userId);
  }

  Future<void> _refresh({bool silent = false}) async {
    try {
      final data = await _load();
      if (!mounted) return;
      setState(() {
        _kyc = data;
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

  String? _resolveMediaUrl(dynamic raw) {
    final value = (raw ?? '').toString().trim();
    if (value.isEmpty) return null;
    if (value.startsWith('http://') || value.startsWith('https://'))
      return value;
    if (value.startsWith('/')) return '$defaultBaseUrl$value';
    return '$defaultBaseUrl/$value';
  }

  String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'U';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }

  Future<void> _openImagePreview(String imageUrl) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _KycImagePreviewPage(imageUrl: imageUrl),
      ),
    );
  }

  Future<void> _updateStatus(String status) async {
    if (_updating) return;
    setState(() => _updating = true);
    try {
      await api.adminUpdateKyc(userId: widget.userId, status: status);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('KYC status updated to $status')));
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Update failed: $e')));
    } finally {
      if (mounted) {
        setState(() => _updating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: SafeArea(
        child: Builder(
          builder: (context) {
            if (_loading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (_error != null && _kyc == null) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Failed to load: $_error'),
                    const SizedBox(height: 10),
                    ElevatedButton(
                      onPressed: () => _refresh(),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              );
            }

            final data = _kyc ?? <String, dynamic>{};
            final name = (data['name'] ?? widget.userName).toString();
            final email = (data['email'] ?? '-').toString();
            final phone = (data['phone'] ?? '-').toString();
            final docType = (data['kyc_doc_type'] ?? '-').toString();
            final status = (data['kyc_status'] ?? 'unverified').toString();
            final avatarUrl = _resolveMediaUrl(data['avatar_url']);
            final idImageUrl = _resolveMediaUrl(data['kyc_id_image_url']);
            final selfieImageUrl = _resolveMediaUrl(
              data['kyc_selfie_image_url'],
            );

            return Column(
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
                      const Text(
                        'KYC Review',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      _statusChip(status),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.grey[50],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 60,
                                height: 60,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE6F4F2),
                                  shape: BoxShape.circle,
                                  image: avatarUrl == null
                                      ? null
                                      : DecorationImage(
                                          image: NetworkImage(avatarUrl),
                                          fit: BoxFit.cover,
                                        ),
                                ),
                                child: avatarUrl == null
                                    ? Center(
                                        child: Text(
                                          _initials(name),
                                          style: const TextStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF0D9488),
                                          ),
                                        ),
                                      )
                                    : null,
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      email,
                                      style: TextStyle(color: Colors.grey[600]),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'ID Document',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        _buildImageBlock(
                          imageUrl: idImageUrl,
                          placeholderIcon: Icons.credit_card,
                          placeholderText: 'No ID image uploaded',
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'Selfie with ID',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        _buildImageBlock(
                          imageUrl: selfieImageUrl,
                          placeholderIcon: Icons.person,
                          placeholderText: 'No selfie image uploaded',
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'User Details',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        _buildDetailRow('Full Name', name),
                        _buildDetailRow('Email', email),
                        _buildDetailRow('Phone', phone),
                        _buildDetailRow('Document Type', docType),
                        _buildDetailRow('Current Status', status),
                      ],
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _updating
                              ? null
                              : () => _updateStatus('rejected'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                          ),
                          child: _updating
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Reject'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: _updating
                              ? null
                              : () => _updateStatus('verified'),
                          child: _updating
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
                              : const Text('Approve'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildImageBlock({
    required String? imageUrl,
    required IconData placeholderIcon,
    required String placeholderText,
  }) {
    return Container(
      width: double.infinity,
      height: 220,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
      ),
      child: imageUrl == null
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(placeholderIcon, size: 50, color: Colors.grey[400]),
                const SizedBox(height: 8),
                Text(
                  placeholderText,
                  style: TextStyle(color: Colors.grey[500]),
                ),
              ],
            )
          : InkWell(
              onTap: () => _openImagePreview(imageUrl),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.broken_image,
                            size: 50,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Failed to load image',
                            style: TextStyle(color: Colors.grey[500]),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(
                          Icons.open_in_full,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _statusChip(String status) {
    final normalized = status.toLowerCase();
    Color color;
    if (normalized == 'verified') {
      color = Colors.green;
    } else if (normalized == 'pending') {
      color = const Color(0xFF0D9488);
    } else if (normalized == 'rejected') {
      color = Colors.red;
    } else {
      color = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        normalized,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600])),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

class _KycImagePreviewPage extends StatelessWidget {
  final String imageUrl;

  const _KycImagePreviewPage({required this.imageUrl});

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
