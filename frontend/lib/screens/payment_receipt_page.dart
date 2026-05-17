import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../utils/file_download.dart';

// ==================== PAYMENT RECEIPT PAGE ====================
class PaymentReceiptPage extends StatefulWidget {
  final String itemName;
  final String totalText;
  final String rentalText;
  final String depositText;
  final String paymentMethod;

  const PaymentReceiptPage({
    super.key,
    required this.itemName,
    required this.totalText,
    required this.rentalText,
    required this.depositText,
    this.paymentMethod = 'Simulated',
  });

  @override
  State<PaymentReceiptPage> createState() => _PaymentReceiptPageState();
}

class _PaymentReceiptPageState extends State<PaymentReceiptPage> {
  static const Color _brandTeal = Color(0xFF0D9488);
  final GlobalKey _receiptKey = GlobalKey();

  String _receiptFileName() {
    final now = DateTime.now();
    final stamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    return 'receipt_$stamp.png';
  }

  Future<void> _downloadReceipt(BuildContext context) async {
    try {
      await Future.delayed(const Duration(milliseconds: 16));
      final boundary =
          _receiptKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) {
        throw Exception('Receipt view is not ready');
      }
      final image = await boundary.toImage(pixelRatio: 3);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw Exception('Unable to encode receipt image');
      }
      final bytes = byteData.buffer.asUint8List();
      final ok = await downloadBytesFile(
        fileName: _receiptFileName(),
        bytes: bytes,
        mimeType: 'image/png',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'Receipt image downloaded successfully'
                : 'Download is not supported on this platform yet',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Download failed: $e')));
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
                  const Text(
                    'Payment Receipt',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),

            Expanded(
              child: RepaintBoundary(
                key: _receiptKey,
                child: Container(
                  color: Colors.white,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        // Success Icon
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: _brandTeal.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check,
                            size: 40,
                            color: _brandTeal,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Payment Successful',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Transaction completed',
                          style: TextStyle(
                            color: Colors.grey[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),

                        const SizedBox(height: 28),

                        // Receipt Card
                        _buildReceiptTicket(),

                        const SizedBox(height: 24),

                        // Info Box
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE6F4F2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.info_outline,
                                color: Color(0xFF0F766E),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Your deposit will be refunded after the item is returned in good condition.',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF115E59),
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
              ),
            ),

            // Bottom Buttons
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: () => _downloadReceipt(context),
                      icon: const Icon(Icons.download),
                      label: const Text('Download Receipt'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Back to Home'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReceiptRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: Color(0xFF111827),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReceiptTicket() {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            border: Border.all(color: Colors.grey[300]!),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            children: [
              Opacity(
                opacity: 0.28,
                child: Column(
                  children: [
                    const Icon(Icons.eco, size: 26, color: Color(0xFF64748B)),
                    const SizedBox(height: 2),
                    Text(
                      'BorrowEase',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _buildReceiptRow('Item', widget.itemName),
              const Divider(height: 24),
              _buildReceiptRow('Payment Method', widget.paymentMethod),
              const Divider(height: 24),
              _buildReceiptRow('Rental Fee', widget.rentalText),
              _buildReceiptRow('Security Deposit', widget.depositText),
              const SizedBox(height: 14),
              _buildDottedDivider(),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Total',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  Text(
                    widget.totalText,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 22,
                      color: _brandTeal,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        SizedBox(
          height: 16,
          child: CustomPaint(
            painter: _ZigZagEdgePainter(
              color: Colors.white,
              borderColor: Colors.grey[300]!,
            ),
            size: const Size(double.infinity, 16),
          ),
        ),
      ],
    );
  }

  Widget _buildDottedDivider() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = (constraints.maxWidth / 8).floor().clamp(12, 200);
        return Row(
          children: List.generate(
            count,
            (_) => Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                height: 1.6,
                color: Colors.grey[400],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ZigZagEdgePainter extends CustomPainter {
  final Color color;
  final Color borderColor;

  _ZigZagEdgePainter({required this.color, required this.borderColor});

  @override
  void paint(Canvas canvas, Size size) {
    final fillPaint = Paint()..color = color;
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final path = Path()..moveTo(0, 0);
    const toothWidth = 12.0;
    for (double x = 0; x < size.width; x += toothWidth) {
      final mid = x + (toothWidth / 2);
      final next = x + toothWidth;
      path.lineTo(mid, size.height);
      path.lineTo(next <= size.width ? next : size.width, 0);
    }
    path.lineTo(size.width, 0);
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();

    canvas.drawPath(path, fillPaint);
    canvas.drawLine(Offset(0, 0), Offset(size.width, 0), borderPaint);
  }

  @override
  bool shouldRepaint(covariant _ZigZagEdgePainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.borderColor != borderColor;
  }
}

