import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api.dart';
import '../services/api_client.dart' show defaultBaseUrl;

class HandoverPage extends StatefulWidget {
  final String itemName;
  final String? itemImageUrl;
  final bool
  isPickup; // true = pickup confirmation, false = return confirmation
  final bool isLender; // true = lender view, false = borrower view
  final VoidCallback onConfirmed;
  final int requestId;

  const HandoverPage({
    super.key,
    required this.itemName,
    this.itemImageUrl,
    required this.isPickup,
    this.isLender = false,
    required this.onConfirmed,
    required this.requestId,
  });

  @override
  State<HandoverPage> createState() => _HandoverPageState();
}

class _HandoverPageState extends State<HandoverPage> {
  final ImagePicker _picker = ImagePicker();
  final List<XFile> _selectedFiles = [];
  bool _isUploading = false;
  bool _agreeToCondition = false;
  bool _submitting = false;

  String? _resolveMediaUrl(dynamic raw) {
    final value = (raw ?? '').toString().trim();
    if (value.isEmpty) return null;
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    if (value.startsWith('/')) return '$defaultBaseUrl$value';
    return '$defaultBaseUrl/$value';
  }

  String get _nextStatus {
    if (widget.isPickup) {
      return widget.isLender ? 'handover' : 'in_use';
    }
    return widget.isLender ? 'completed' : 'return_pending';
  }

  String get _evidenceType => widget.isPickup ? 'handover' : 'return';

  bool get _requiresEvidence {
    if (widget.isPickup) return widget.isLender;
    return !widget.isLender;
  }

  String get _confirmButtonText {
    if (widget.isPickup) {
      return widget.isLender
          ? 'Confirm Handover'
          : 'Yes, I received it in good condition';
    }
    return widget.isLender ? 'Confirm Received' : 'Submit Return';
  }

  @override
  Widget build(BuildContext context) {
    String title;
    String description;

    if (widget.isPickup && widget.isLender) {
      title = 'Confirm Handover';
      description =
          'Take at least one photo proving the item is in good condition before handover.';
    } else if (widget.isPickup && !widget.isLender) {
      title = 'Pickup Confirmation';
      description =
          'The lender has confirmed handover. Please verify carefully.';
    } else if (!widget.isPickup && !widget.isLender) {
      title = 'Submit Return';
      description =
          'Take at least one photo proving you returned the item in good condition.';
    } else {
      title = 'Confirm Received';
      description =
          'Inspect the returned item, then confirm received to complete settlement.';
    }

    final itemImageUrl = _resolveMediaUrl(widget.itemImageUrl);

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Info card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: Colors.blue[700]),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.isPickup
                              ? (widget.isLender
                                    ? 'Owner Handover'
                                    : 'Pickup Confirmation')
                              : (widget.isLender
                                    ? 'Owner Return Confirmation'
                                    : 'Borrower Return Submission'),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue[900],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          description,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.blue[800],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green[200]!),
              ),
              child: Text(
                _requiresEvidence
                    ? 'This step requires at least 1 photo as evidence.'
                    : (widget.isPickup
                          ? 'No photo required here. The lender already confirmed handover. Verify the item and confirm.'
                          : 'No photo required here. After inspection, tap Confirm Received.'),
                style: TextStyle(color: Colors.green[800], fontSize: 13),
              ),
            ),
            const SizedBox(height: 16),

            // Item info
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  _buildItemThumbnail(itemImageUrl),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.itemName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.isPickup
                              ? 'Ready for pickup'
                              : 'Ready to return',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            if (_requiresEvidence) ...[
              const Text(
                'Upload Photos',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                'Take clear photos showing the item condition (minimum 1 photo)',
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
              const SizedBox(height: 12),

              // Photo grid
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    if (_selectedFiles.isNotEmpty) ...[
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: _selectedFiles
                            .asMap()
                            .entries
                            .map((entry) => _buildPhotoCard(entry.key))
                            .toList(),
                      ),
                      const SizedBox(height: 16),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: _buildUploadButton(
                            icon: Icons.camera_alt,
                            label: 'Take Photo',
                            onTap: _pickFromCamera,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildUploadButton(
                            icon: Icons.photo_library,
                            label: 'Gallery',
                            onTap: _pickFromGallery,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Photo tips
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFE6F4F2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFBCE6E1)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.lightbulb_outline,
                          color: const Color(0xFF0F766E),
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Photo Tips',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF115E59),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildTipItem('Overall condition of the item'),
                    _buildTipItem('Any existing scratches or damage'),
                    _buildTipItem('All accessories and components'),
                    _buildTipItem('Item with both parties visible (optional)'),
                  ],
                ),
              ),

              const SizedBox(height: 24),
            ],

            // Agreement
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Checkbox(
                    value: _agreeToCondition,
                    onChanged: (value) {
                      setState(() => _agreeToCondition = value ?? false);
                    },
                    activeColor: const Color(0xFF0D9488),
                  ),
                  Expanded(
                    child: Text(
                      widget.isPickup
                          ? (widget.isLender
                                ? 'I confirm the handover photos accurately represent the item at pickup.'
                                : 'I confirm that I have received the item in good condition.')
                          : (widget.isLender
                                ? 'I confirm that I have received the returned item and verified its condition.'
                                : 'I confirm that I am returning the item in the same condition as received.'),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Confirm button
            ElevatedButton(
              onPressed: _canConfirm() ? _handleConfirm : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0D9488),
                disabledBackgroundColor: Colors.grey[400],
                minimumSize: const Size(double.infinity, 54),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: (_isUploading || _submitting)
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(
                      _confirmButtonText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),

            const SizedBox(height: 16),

            // Cancel button
            Center(
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Cancel',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ),
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoCard(int index) {
    final file = _selectedFiles[index];
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 80,
            height: 80,
            child: FutureBuilder<Uint8List>(
              future: file.readAsBytes(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Container(
                    color: Colors.grey[200],
                    child: const Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return Container(
                    color: Colors.grey[200],
                    child: Icon(Icons.image, color: Colors.grey[500]),
                  );
                }
                return Image.memory(snapshot.data!, fit: BoxFit.cover);
              },
            ),
          ),
        ),
        Positioned(
          right: -4,
          top: -4,
          child: GestureDetector(
            onTap: () {
              setState(() {
                _selectedFiles.removeAt(index);
              });
            },
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildItemThumbnail(String? imageUrl) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 60,
        height: 60,
        color: Colors.grey[200],
        child: imageUrl == null
            ? Icon(Icons.inventory_2_outlined, color: Colors.grey[400])
            : Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Icon(
                    Icons.inventory_2_outlined,
                    color: Colors.grey[400],
                  );
                },
              ),
      ),
    );
  }

  Widget _buildUploadButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          border: Border.all(
            color: Colors.grey[300]!,
            style: BorderStyle.solid,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, size: 32, color: Colors.grey[700]),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: Colors.grey[700],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTipItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle, size: 16, color: Color(0xFF0F766E)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13, color: Color(0xFF115E59)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickFromCamera() async {
    if (_selectedFiles.length >= 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Maximum 4 photos allowed'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    final file = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
    );
    if (file != null) {
      setState(() => _selectedFiles.add(file));
    }
  }

  Future<void> _pickFromGallery() async {
    if (_selectedFiles.length >= 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Maximum 4 photos allowed'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    final files = await _picker.pickMultiImage(imageQuality: 85);
    if (files.isNotEmpty) {
      final remaining = 4 - _selectedFiles.length;
      setState(() => _selectedFiles.addAll(files.take(remaining)));
    }
  }

  bool _canConfirm() {
    final hasRequiredEvidence = !_requiresEvidence || _selectedFiles.isNotEmpty;
    return hasRequiredEvidence &&
        _agreeToCondition &&
        !_isUploading &&
        !_submitting;
  }

  Future<void> _handleConfirm() async {
    setState(() => _submitting = true);

    try {
      if (_requiresEvidence && _selectedFiles.isEmpty) {
        throw Exception('Please upload at least one photo');
      }

      if (_requiresEvidence) {
        setState(() => _isUploading = true);
        final multipart = <MultipartFile>[];
        for (final file in _selectedFiles) {
          if (kIsWeb) {
            final bytes = await file.readAsBytes();
            multipart.add(MultipartFile.fromBytes(bytes, filename: file.name));
          } else {
            multipart.add(
              await MultipartFile.fromFile(file.path, filename: file.name),
            );
          }
        }
        final urls = await api.uploadFiles(multipart);
        if (urls.isEmpty) {
          throw Exception('Upload failed, no URLs returned');
        }

        await api.attachEvidence(
          requestId: widget.requestId,
          type: _evidenceType,
          urls: urls,
        );
      }

      await api.updateRequestStatus(
        requestId: widget.requestId,
        nextStatus: _nextStatus,
      );

      if (!mounted) return;

      widget.onConfirmed();
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _nextStatus == 'handover'
                ? 'Handover confirmed'
                : _nextStatus == 'in_use'
                ? 'Pickup confirmed'
                : _nextStatus == 'return_pending'
                ? 'Return submitted'
                : 'Return received and order completed',
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Update failed: $e'),
          duration: const Duration(seconds: 2),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
          _isUploading = false;
        });
      }
    }
  }
}


