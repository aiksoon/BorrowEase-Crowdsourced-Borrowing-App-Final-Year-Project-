import 'package:flutter/material.dart';

import '../services/api.dart';

class PayoutSettingsPage extends StatefulWidget {
  const PayoutSettingsPage({super.key});

  @override
  State<PayoutSettingsPage> createState() => _PayoutSettingsPageState();
}

class _PayoutSettingsPageState extends State<PayoutSettingsPage> {
  static const Color _ecoTeal = Color(0xFF0D9488);

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _holderController = TextEditingController();
  final TextEditingController _accountController = TextEditingController();

  final List<String> _banks = const <String>[
    'Maybank',
    'CIMB Bank',
    'Public Bank',
    'RHB Bank',
    'Hong Leong Bank',
    'AmBank',
    'Bank Islam',
    'BSN',
    'UOB Malaysia',
    'OCBC Bank',
    "Touch 'n Go eWallet",
  ];

  bool _loading = true;
  bool _saving = false;
  bool _editing = false;
  String? _selectedBank;

  String? _linkedBank;
  String? _linkedHolder;
  String? _linkedAccount;

  @override
  void initState() {
    super.initState();
    _loadPayoutAccount();
  }

  @override
  void dispose() {
    _holderController.dispose();
    _accountController.dispose();
    super.dispose();
  }

  String _maskAccountNumber(String? value) {
    final raw = (value ?? '').trim();
    if (raw.length <= 4) return raw;
    return '**** ${raw.substring(raw.length - 4)}';
  }

  Future<void> _loadPayoutAccount() async {
    setState(() => _loading = true);
    try {
      final me = await api.getMe();
      final user = me['user'] as Map<String, dynamic>?;
      final bank = (user?['payout_bank_name'] ?? '').toString().trim();
      final holder = (user?['payout_account_holder'] ?? '').toString().trim();
      final account = (user?['payout_account_number'] ?? '').toString().trim();

      if (!mounted) return;
      setState(() {
        _linkedBank = bank.isEmpty ? null : bank;
        _linkedHolder = holder.isEmpty ? null : holder;
        _linkedAccount = account.isEmpty ? null : account;
        _selectedBank = _linkedBank;
        _holderController.text = _linkedHolder ?? '';
        _accountController.text = _linkedAccount ?? '';
        _editing = _linkedBank == null || _linkedHolder == null || _linkedAccount == null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load payout settings: $e')),
      );
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      await api.updateMe(
        payoutBankName: _selectedBank,
        payoutAccountHolder: _holderController.text.trim(),
        payoutAccountNumber: _accountController.text.trim(),
      );

      if (!mounted) return;
      setState(() {
        _linkedBank = _selectedBank?.trim();
        _linkedHolder = _holderController.text.trim();
        _linkedAccount = _accountController.text.trim();
        _editing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payout account saved successfully.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save payout account: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _removeLinkedAccount() async {
    setState(() => _saving = true);
    try {
      await api.updateMe(
        payoutBankName: '',
        payoutAccountHolder: '',
        payoutAccountNumber: '',
      );

      if (!mounted) return;
      setState(() {
        _linkedBank = null;
        _linkedHolder = null;
        _linkedAccount = null;
        _selectedBank = null;
        _holderController.clear();
        _accountController.clear();
        _editing = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payout account removed.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to remove payout account: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  bool get _hasLinkedAccount {
    return (_linkedBank ?? '').isNotEmpty &&
        (_linkedHolder ?? '').isNotEmpty &&
        (_linkedAccount ?? '').isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      appBar: AppBar(
        title: const Text('Payout Account'),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 110),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Add your bank details to receive rental earnings and compensations securely.',
                    style: TextStyle(color: Colors.grey[700], height: 1.4),
                  ),
                  const SizedBox(height: 14),
                  if (_hasLinkedAccount) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 12,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Current Linked Account',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 12),
                          _buildRow('Bank Name', _linkedBank ?? '-'),
                          _buildRow('Account Holder Name', _linkedHolder ?? '-'),
                          _buildRow('Account Number', _maskAccountNumber(_linkedAccount)),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              OutlinedButton(
                                onPressed: _saving
                                    ? null
                                    : () {
                                        setState(() {
                                          _editing = true;
                                          _selectedBank = _linkedBank;
                                          _holderController.text = _linkedHolder ?? '';
                                          _accountController.text = _linkedAccount ?? '';
                                        });
                                      },
                                child: const Text('Edit'),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton(
                                onPressed: _saving ? null : _removeLinkedAccount,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red[700],
                                ),
                                child: const Text('Remove'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  if (_editing || !_hasLinkedAccount)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 12,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Bank Account Details',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              initialValue: _selectedBank,
                              decoration: const InputDecoration(
                                labelText: 'Bank Name',
                                border: OutlineInputBorder(),
                              ),
                              items: _banks
                                  .map(
                                    (bank) => DropdownMenuItem<String>(
                                      value: bank,
                                      child: Text(bank),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                setState(() => _selectedBank = value);
                              },
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please choose a bank';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _holderController,
                              decoration: const InputDecoration(
                                labelText: 'Account Holder Name',
                                hintText: 'Must match your IC/Verification',
                                border: OutlineInputBorder(),
                              ),
                              validator: (value) {
                                final text = (value ?? '').trim();
                                if (text.isEmpty) {
                                  return 'Please enter account holder name';
                                }
                                if (text.length < 3) {
                                  return 'Name is too short';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _accountController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Account Number',
                                border: OutlineInputBorder(),
                              ),
                              validator: (value) {
                                final text = (value ?? '').trim();
                                if (text.isEmpty) {
                                  return 'Please enter account number';
                                }
                                if (!RegExp(r'^[0-9]{6,25}$').hasMatch(text)) {
                                  return 'Enter a valid account number';
                                }
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                    child: Row(
                      children: [
                        Icon(Icons.lock_outline, size: 16, color: Colors.grey[600]),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Your financial information is encrypted and securely stored.',
                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: (_saving || (!_editing && _hasLinkedAccount)) ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: _ecoTeal,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text(
                    'Save Account Details',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600])),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
