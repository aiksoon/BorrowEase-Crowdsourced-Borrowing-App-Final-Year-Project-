import 'package:flutter/material.dart';

class PrivacyTermsPage extends StatelessWidget {
  const PrivacyTermsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('Privacy Policy & Terms'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section(
            title: 'Privacy Policy (PDPA-Oriented)',
            body:
                'BorrowEase collects account, transaction, and communication data to operate lending features. '
                'Data is processed with consent and for service delivery purposes in line with Malaysia PDPA principles. '
                'Users may request profile updates and can contact support for data correction requests.',
          ),
          _section(
            title: 'Data Usage',
            body:
                'We use your data for authentication, listings, borrowing workflows, messaging, and safety monitoring. '
                'Only relevant data is displayed to other users (for example, profile name and public listing details).',
          ),
          _section(
            title: 'Terms of Service',
            body:
                'Users must provide accurate information, respect lending agreements, and avoid prohibited behavior. '
                'BorrowEase may restrict accounts that violate platform safety, fraud, or abuse policies.',
          ),
          _section(
            title: 'Disclaimer',
            body:
                'This page is a project evaluation policy template for demonstration purposes and may be updated during production deployment.',
          ),
        ],
      ),
    );
  }

  Widget _section({required String title, required String body}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(body, style: TextStyle(color: Colors.grey[700], height: 1.4)),
        ],
      ),
    );
  }
}
