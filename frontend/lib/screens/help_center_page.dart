import 'package:flutter/material.dart';

class HelpCenterPage extends StatelessWidget {
  const HelpCenterPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('Help Center / FAQ'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          _FaqTile(
            question: 'How do I contact a lender?',
            answer:
                'Open the item details and tap the chat icon next to Request to Borrow, or go to the Chat tab and open the related conversation.',
          ),
          _FaqTile(
            question: 'How can I submit KYC?',
            answer:
                'Go to Profile -> KYC Verification and submit your details. Your status will be updated to pending, verified, or rejected after review.',
          ),
          _FaqTile(
            question: 'Where can I check request and handover progress?',
            answer:
                'Use Alerts for reminders and status updates. For full details, open Profile -> Items I\'m Borrowing (borrower) or Profile -> My Listings (lender), then open the related order.',
          ),
          _FaqTile(
            question: 'What if pickup/return confirmation fails?',
            answer:
                'Open the related order and continue the handover flow (Confirm Handover, Confirm Received, or Submit Return). Make sure required evidence photos/checklist are completed, then retry. If it still fails, use Chat with the counterparty and check Alerts for the next reminder.',
          ),
          _FaqTile(
            question: 'How do I report a user or listing?',
            answer:
                'Go to Profile -> Report an Issue, select the completed order from dropdown, choose a reason category, add details, and upload photo/video evidence before submitting.',
          ),
        ],
      ),
    );
  }
}

class _FaqTile extends StatelessWidget {
  const _FaqTile({required this.question, required this.answer});

  final String question;
  final String answer;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: ExpansionTile(
        title: Text(
          question,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Text(answer, style: TextStyle(color: Colors.grey[700], height: 1.4)),
        ],
      ),
    );
  }
}
