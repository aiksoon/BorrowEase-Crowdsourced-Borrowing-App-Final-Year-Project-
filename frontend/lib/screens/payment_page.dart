import 'package:flutter/material.dart';

import '../services/api.dart';
import 'payment_receipt_page.dart';

// ==================== PAYMENT PAGE ====================
// Borrower pays for approved borrow request (simulated)
class PaymentPage extends StatefulWidget {
  final int requestId;
  final String itemName;
  final String? itemImageUrl;

  const PaymentPage({
    super.key,
    required this.requestId,
    required this.itemName,
    this.itemImageUrl,
  });

  @override
  State<PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends State<PaymentPage> {
  String selectedMethod = 'card';
  bool _loading = true;
  bool _processingPayment = false;
  num _rentalFee = 0;
  num _deposit = 0;

  @override
  void initState() {
    super.initState();
    _loadTransaction();
  }

  Future<void> _loadTransaction() async {
    try {
      final tx = await api.getTransaction(widget.requestId);
      if (!mounted) return;
      final totalAmount = (tx['total_amount'] as num?) ?? 0;
      final depositAmount = (tx['deposit_amount'] as num?) ?? 0;
      final rentalAmount =
          (tx['rental_amount'] as num?) ?? (totalAmount - depositAmount);
      setState(() {
        _rentalFee = rentalAmount < 0 ? 0 : rentalAmount;
        _deposit = depositAmount < 0 ? 0 : depositAmount;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load transaction: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final num total = _rentalFee + _deposit;

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
                    'Payment',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),

            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Order Summary
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.grey[50],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Order Summary',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    _buildItemImage(),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        widget.itemName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                const Divider(),
                                const SizedBox(height: 12),
                                _buildPriceRow(
                                  'Rental Fee',
                                  _formatCurrency(_rentalFee),
                                ),
                                const SizedBox(height: 8),
                                _buildPriceRow(
                                  'Security Deposit',
                                  _formatCurrency(_deposit),
                                ),
                                const SizedBox(height: 12),
                                const Divider(),
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'Total',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    Text(
                                      _formatCurrency(total),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 20,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 24),

                          // Payment Method
                          const Text(
                            'Payment Method',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 12),

                          _buildPaymentOption(
                            'card',
                            Icons.credit_card,
                            'Credit/Debit Card',
                            'Visa / Mastercard accepted',
                          ),
                          _buildPaymentOption(
                            'ewallet',
                            Icons.account_balance_wallet,
                            'E-Wallet',
                            'Touch \'n Go / GrabPay',
                          ),
                          _buildPaymentOption(
                            'banking',
                            Icons.account_balance,
                            'Online Banking',
                            'FPX',
                          ),
                          _buildPaymentOption(
                            'duitnow_qr',
                            Icons.qr_code_2,
                            'DuitNow QR',
                            'Scan to pay',
                          ),

                          const SizedBox(height: 24),

                          // Security Note
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.blue[50],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.security,
                                  size: 20,
                                  color: Colors.blue[700],
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Your deposit will be refunded after returning the item in good condition.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.blue[700],
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

            // Pay Button
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: (_loading || _processingPayment)
                          ? null
                          : () async {
                              try {
                                setState(() => _processingPayment = true);
                                await Future.wait([
                                  api.payTransaction(widget.requestId),
                                  Future.delayed(const Duration(seconds: 2)),
                                ]);
                                if (!mounted) return;
                                Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => PaymentReceiptPage(
                                      itemName: widget.itemName,
                                      totalText: _formatCurrency(total),
                                      depositText: _formatCurrency(_deposit),
                                      rentalText: _formatCurrency(_rentalFee),
                                      paymentMethod: _paymentMethodLabel,
                                    ),
                                  ),
                                );
                              } catch (e) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Payment failed: $e')),
                                );
                              } finally {
                                if (mounted) {
                                  setState(() => _processingPayment = false);
                                }
                              }
                            },
                      child: _processingPayment
                          ? const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                ),
                                SizedBox(width: 10),
                                Text(
                                  'Processing Payment...',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            )
                          : Text(
                              _loading
                                  ? 'Loading...'
                                  : 'Pay ${_formatCurrency(total)}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
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

  Widget _buildPriceRow(String label, String price) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: Colors.grey[600])),
        Text(price, style: const TextStyle(fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildPaymentOption(
    String value,
    IconData icon,
    String title,
    String? subtitle,
  ) {
    final isSelected = selectedMethod == value;
    return GestureDetector(
      onTap: () => setState(() => selectedMethod = value),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFE6F4F2) : Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFF0D9488) : Colors.grey[200]!,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected ? const Color(0xFF0D9488) : Colors.grey[600],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? const Color(0xFF0F766E)
                          : Colors.grey[800],
                    ),
                  ),
                  if (subtitle != null && subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle, color: Color(0xFF0D9488))
            else
              Icon(Icons.radio_button_unchecked, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  String get _paymentMethodLabel {
    switch (selectedMethod) {
      case 'card':
        return 'Credit/Debit Card';
      case 'ewallet':
        return 'E-Wallet';
      case 'banking':
        return 'Online Banking (FPX)';
      case 'duitnow_qr':
        return 'DuitNow QR';
      default:
        return 'Simulated';
    }
  }

  Widget _buildItemImage() {
    final url = widget.itemImageUrl;
    if (url == null || url.trim().isEmpty) {
      return Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(Icons.image, color: Colors.grey[400]),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        url,
        width: 60,
        height: 60,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: 60,
          height: 60,
          color: Colors.grey[200],
          child: Icon(Icons.broken_image, color: Colors.grey[400]),
        ),
      ),
    );
  }

  String _formatCurrency(num amount) => 'RM${amount.toStringAsFixed(2)}';
}




