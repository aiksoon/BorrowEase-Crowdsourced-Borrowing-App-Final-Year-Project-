import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/api.dart';
import '../services/api_client.dart' show defaultBaseUrl;

class AdminTransactionDetailsPage extends StatefulWidget {
  final int requestId;

  const AdminTransactionDetailsPage({super.key, required this.requestId});

  @override
  State<AdminTransactionDetailsPage> createState() =>
      _AdminTransactionDetailsPageState();
}

class _AdminTransactionDetailsPageState
    extends State<AdminTransactionDetailsPage> {
  bool _loading = true;
  bool _confiscating = false;
  String? _error;
  Map<String, dynamic>? _detail;

  @override
  void initState() {
    super.initState();
    _load();
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  num _toNum(dynamic value) {
    if (value is num) return value;
    if (value is String) return num.tryParse(value) ?? 0;
    return 0;
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

  String _formatDate(dynamic raw) {
    final dt = DateTime.tryParse((raw ?? '').toString());
    if (dt == null) return '-';
    return DateFormat('dd MMM yyyy, HH:mm').format(dt.toLocal());
  }

  Future<void> _openImagePreview(String imageUrl) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _TransactionEvidencePreviewPage(imageUrl: imageUrl),
      ),
    );
  }

  Future<void> _load() async {
    try {
      final data = await api.getAdminTransactionEvidence(widget.requestId);
      if (!mounted) return;
      setState(() {
        _detail = data;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Widget _evidenceCard({
    required String title,
    required String subtitle,
    required String? imageUrl,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: AspectRatio(
                aspectRatio: 4 / 3,
                child: imageUrl == null
                    ? Container(
                        color: const Color(0xFFF1F5F9),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.image_not_supported,
                              color: Colors.grey[500],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Pending upload',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      )
                    : InkWell(
                        onTap: () => _openImagePreview(imageUrl),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.network(
                              imageUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                color: const Color(0xFFF1F5F9),
                                child: const Center(
                                  child: Icon(Icons.broken_image_outlined),
                                ),
                              ),
                            ),
                            Positioned(
                              right: 6,
                              bottom: 6,
                              child: Container(
                                padding: const EdgeInsets.all(4),
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
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmConfiscation() async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Deposit Confiscation'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'This will forfeit the renter\'s deposit and transfer it to the lender as compensation.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Reason for Confiscation',
                hintText: 'Item severely damaged...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
            ),
            child: const Text('Confirm & Transfer'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    final reason = reasonController.text.trim();
    if (reason.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please provide a confiscation reason.')),
      );
      return;
    }

    setState(() => _confiscating = true);
    try {
      await api.confiscateTransactionDeposit(
        requestId: widget.requestId,
        reason: reason,
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Deposit has been confiscated and transferred.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to confiscate deposit: $e')),
      );
    } finally {
      if (mounted) setState(() => _confiscating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail ?? <String, dynamic>{};
    final handover =
        (detail['handover_evidence'] as List?) ?? const <dynamic>[];
    final returned = (detail['return_evidence'] as List?) ?? const <dynamic>[];

    final ownerId = _toInt(detail['owner_id']);
    final borrowerId = _toInt(detail['borrower_id']);
    Map<String, dynamic>? lenderEvidence;
    for (final e in handover) {
      if (e is Map<String, dynamic> && _toInt(e['uploaded_by']) == ownerId) {
        lenderEvidence = e;
      }
    }
    Map<String, dynamic>? renterEvidence;
    for (final e in returned) {
      if (e is Map<String, dynamic> && _toInt(e['uploaded_by']) == borrowerId) {
        renterEvidence = e;
      }
    }

    final depositConfiscated = _toInt(detail['deposit_confiscated']) == 1;
    final confiscationWindowClosed =
        _toInt(detail['confiscation_window_closed']) == 1;
    final cannotConfiscate = depositConfiscated || confiscationWindowClosed;
    final deadlineText = _formatDate(detail['confiscation_deadline']);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      appBar: AppBar(
        title: const Text('Transaction Details'),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text('Failed to load details: $_error'))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (detail['item_title'] ?? 'Item').toString(),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text('Order #${_toInt(detail['request_id'])}'),
                        const SizedBox(height: 4),
                        Text(
                          '${(detail['borrower_name'] ?? 'Borrower').toString()} <-> ${(detail['owner_name'] ?? 'Lender').toString()}',
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Total: RM${_toNum(detail['total_amount']).toStringAsFixed(2)} | Deposit: RM${_toNum(detail['deposit_amount']).toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        if (depositConfiscated) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFDECEC),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              'Deposit confiscated. Reason: ${(detail['confiscation_reason'] ?? '-').toString()}',
                              style: const TextStyle(
                                color: Color(0xFFB91C1C),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Transaction Photo Evidence',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1F2937),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _evidenceCard(
                              title: 'Check-out (Lender)',
                              subtitle: _formatDate(
                                lenderEvidence?['created_at'],
                              ),
                              imageUrl: _resolveUrl(lenderEvidence?['url']),
                            ),
                            const SizedBox(width: 10),
                            _evidenceCard(
                              title: 'Check-in (Renter)',
                              subtitle: _formatDate(
                                renterEvidence?['created_at'],
                              ),
                              imageUrl: _resolveUrl(renterEvidence?['url']),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Deposit Resolution',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: cannotConfiscate || _confiscating
                                ? null
                                : _confirmConfiscation,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFDC2626),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: _confiscating
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  )
                                : Text(
                                    depositConfiscated
                                        ? 'Deposit Already Confiscated'
                                        : (confiscationWindowClosed
                                              ? 'Confiscation Window Closed'
                                              : 'Confiscate Deposit (Damage)'),
                                  ),
                          ),
                        ),
                        if (confiscationWindowClosed &&
                            !depositConfiscated) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Confiscation is only allowed within 2 days after completion. Deadline: $deadlineText',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFFB91C1C),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _TransactionEvidencePreviewPage extends StatelessWidget {
  final String imageUrl;

  const _TransactionEvidencePreviewPage({required this.imageUrl});

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
