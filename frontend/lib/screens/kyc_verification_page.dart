import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api.dart';
import '../services/api_client.dart' show defaultBaseUrl;

// ==================== KYC VERIFICATION PAGE ====================
class KYCVerificationPage extends StatefulWidget {
  const KYCVerificationPage({super.key});

  @override
  State<KYCVerificationPage> createState() => _KYCVerificationPageState();
}

class _KYCVerificationPageState extends State<KYCVerificationPage> {
  int currentStep = 0;
  bool _submitting = false;
  bool _loading = true;

  String _kycStatus = 'unverified';
  String? _docType;

  Uint8List? _idImageBytes;
  String? _idImageName;
  String? _idImageUrl;

  Uint8List? _selfieImageBytes;
  String? _selfieImageName;
  String? _selfieImageUrl;

  final ImagePicker _picker = ImagePicker();

  bool get _hasIdImage => _idImageBytes != null || (_idImageUrl ?? '').isNotEmpty;
  bool get _hasSelfieImage => _selfieImageBytes != null || (_selfieImageUrl ?? '').isNotEmpty;
  bool get _isLocked => _kycStatus == 'verified';

  @override
  void initState() {
    super.initState();
    _loadKyc();
  }

  Future<void> _loadKyc() async {
    try {
      final data = await api.getKyc();
      if (!mounted) return;
      setState(() {
        _kycStatus = (data['kyc_status'] ?? 'unverified').toString();
        _docType = (data['kyc_doc_type'] ?? '').toString().trim().isEmpty
            ? null
            : data['kyc_doc_type'].toString();
        _idImageUrl = (data['kyc_id_image_url'] ?? '').toString().trim().isEmpty
            ? null
            : data['kyc_id_image_url'].toString();
        _selfieImageUrl = (data['kyc_selfie_image_url'] ?? '').toString().trim().isEmpty
            ? null
            : data['kyc_selfie_image_url'].toString();

        if (_hasIdImage && _hasSelfieImage) {
          currentStep = 2;
        }
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  String? _resolveMediaUrl(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return null;
    if (value.startsWith('http://') || value.startsWith('https://')) return value;
    if (value.startsWith('/')) return '$defaultBaseUrl$value';
    return '$defaultBaseUrl/$value';
  }

  void _showLockedMessage() {
    _toast('Your KYC is already verified. Document upload is locked.');
  }

  Future<void> _pickIdImage() async {
    if (_isLocked) {
      _showLockedMessage();
      return;
    }
    final file = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() {
      _idImageBytes = bytes;
      _idImageName = file.name;
    });
  }

  Future<void> _pickSelfieImage() async {
    if (_isLocked) {
      _showLockedMessage();
      return;
    }

    // Camera picker is unreliable on Flutter web in some browsers.
    // Use gallery as a web-safe fallback for selfie upload.
    final source = kIsWeb ? ImageSource.gallery : ImageSource.camera;
    final file = await _picker.pickImage(source: source, imageQuality: 85);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() {
      _selfieImageBytes = bytes;
      _selfieImageName = file.name;
    });
  }

  Future<void> _nextStepOrSubmit() async {
    if (_submitting || _loading) return;
    if (_isLocked) {
      _showLockedMessage();
      return;
    }

    if (currentStep == 0) {
      if (_docType == null) {
        _toast('Please select your document type');
        return;
      }
      if (!_hasIdImage) {
        _toast('Please upload your ID document image');
        return;
      }
      setState(() => currentStep = 1);
      return;
    }

    if (currentStep == 1) {
      if (!_hasSelfieImage) {
        _toast('Please upload your selfie with ID');
        return;
      }
      setState(() => currentStep = 2);
      return;
    }

    await _submit();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<String> _uploadOne(Uint8List bytes, String fileName) async {
    final urls = await api.uploadFiles([
      MultipartFile.fromBytes(bytes, filename: fileName),
    ]);
    if (urls.isEmpty) {
      throw Exception('Upload returned no URL');
    }
    return urls.first;
  }

  Future<void> _submit() async {
    if (_docType == null || !_hasIdImage || !_hasSelfieImage) {
      _toast('Please complete all required uploads before submit');
      return;
    }

    setState(() => _submitting = true);
    try {
      String idUrl = _idImageUrl ?? '';
      String selfieUrl = _selfieImageUrl ?? '';

      if (_idImageBytes != null) {
        idUrl = await _uploadOne(_idImageBytes!, _idImageName ?? 'kyc-id.jpg');
      }
      if (_selfieImageBytes != null) {
        selfieUrl = await _uploadOne(_selfieImageBytes!, _selfieImageName ?? 'kyc-selfie.jpg');
      }

      final result = await api.submitKyc(
        docType: _docType!,
        idImageUrl: idUrl,
        selfieImageUrl: selfieUrl,
      );

      if (!mounted) return;
      setState(() {
        _kycStatus = (result['kyc_status'] ?? 'pending').toString();
        _idImageUrl = (result['kyc_id_image_url'] ?? idUrl).toString();
        _selfieImageUrl = (result['kyc_selfie_image_url'] ?? selfieUrl).toString();
        _idImageBytes = null;
        _selfieImageBytes = null;
      });

      _toast('KYC submitted successfully. Status is now pending review.');
      Navigator.pop(context, true);
    } catch (e) {
      _toast('Submit failed: $e');
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
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
                          'KYC Verification',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        _buildStatusChip(_kycStatus),
                      ],
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      children: [
                        _buildStepIndicator(0, 'ID Upload'),
                        Expanded(
                          child: Container(
                            height: 2,
                            color: currentStep >= 1
                                ? const Color(0xFF0D9488)
                                : Colors.grey[300],
                          ),
                        ),
                        _buildStepIndicator(1, 'Selfie'),
                        Expanded(
                          child: Container(
                            height: 2,
                            color: currentStep >= 2
                                ? const Color(0xFF0D9488)
                                : Colors.grey[300],
                          ),
                        ),
                        _buildStepIndicator(2, 'Review'),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: currentStep == 0
                          ? _buildIdUploadStep()
                          : currentStep == 1
                              ? _buildSelfieStep()
                              : _buildReviewStep(),
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: (_submitting || _isLocked) ? null : _nextStepOrSubmit,
                        child: Text(_buttonText()),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  String _buttonText() {
    if (_submitting) return 'Submitting...';
    if (_kycStatus == 'verified') return 'Verified';
    if (currentStep == 2) {
      return _kycStatus == 'pending' ? 'Resubmit for Review' : 'Submit for Review';
    }
    return 'Continue';
  }

  Widget _buildStatusChip(String status) {
    final normalized = status.toLowerCase();
    Color color;
    if (normalized == 'verified') {
      color = Colors.green;
    } else if (normalized == 'pending') {
      color = const Color(0xFF0D9488);
    } else {
      color = Colors.grey[700]!;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        normalized,
        style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12),
      ),
    );
  }

  Widget _buildStepIndicator(int step, String label) {
    final isActive = currentStep >= step;
    return Column(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFF0D9488) : Colors.grey[200],
            shape: BoxShape.circle,
          ),
          child: Center(
            child: isActive && currentStep > step
                ? const Icon(Icons.check, color: Colors.white, size: 18)
                : Text(
                    '${step + 1}',
                    style: TextStyle(
                      color: isActive ? Colors.white : Colors.grey[500],
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[600])),
      ],
    );
  }

  Widget _buildIdUploadStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Upload ID Document', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(
          'Please upload a clear photo of your IC, Passport, or Driving License.',
          style: TextStyle(color: Colors.grey[600]),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildDocTypeChip('IC/MyKad'),
            _buildDocTypeChip('Passport'),
            _buildDocTypeChip('Driving License'),
          ],
        ),
        const SizedBox(height: 16),
        _buildUploadCard(
          title: 'ID Document',
          emptyIcon: Icons.cloud_upload_outlined,
          emptyText: 'Tap to upload from gallery',
          bytes: _idImageBytes,
          networkUrl: _idImageUrl,
          onTap: _pickIdImage,
        ),
      ],
    );
  }

  Widget _buildDocTypeChip(String label) {
    final selected = _docType == label;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: const Color(0xFFCFEDEA),
      backgroundColor: const Color(0xFFE6F4F2),
      labelStyle: TextStyle(
        color: selected ? const Color(0xFF134E4A) : const Color(0xFF115E59),
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
      side: BorderSide(color: const Color(0xFFBCE6E1)),
      onSelected: (_) {
        if (_isLocked) {
          _showLockedMessage();
          return;
        }
        setState(() {
          _docType = label;
        });
      },
    );
  }

  Widget _buildSelfieStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Take a Selfie', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('Hold your ID beside your face and take a clear photo.', style: TextStyle(color: Colors.grey[600])),
        const SizedBox(height: 18),
        _buildUploadCard(
          title: 'Selfie with ID',
          emptyIcon: Icons.camera_alt_outlined,
          emptyText: kIsWeb ? 'Tap to upload selfie' : 'Tap to take photo',
          bytes: _selfieImageBytes,
          networkUrl: _selfieImageUrl,
          onTap: _pickSelfieImage,
          height: 240,
        ),
      ],
    );
  }

  Widget _buildUploadCard({
    required String title,
    required IconData emptyIcon,
    required String emptyText,
    required VoidCallback onTap,
    Uint8List? bytes,
    String? networkUrl,
    double height = 180,
  }) {
    final resolvedUrl = _resolveMediaUrl(networkUrl);
    final hasMedia = bytes != null || resolvedUrl != null;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: height,
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: hasMedia
            ? ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (bytes != null)
                      Image.memory(bytes, fit: BoxFit.cover)
                    else
                      Image.network(
                        resolvedUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image, size: 40)),
                      ),
                    Positioned(
                      left: 10,
                      bottom: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          title,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(emptyIcon, size: 46, color: Colors.grey[400]),
                  const SizedBox(height: 10),
                  Text(emptyText, style: TextStyle(color: Colors.grey[600])),
                ],
              ),
      ),
    );
  }

  Widget _buildReviewStep() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Review & Submit', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Please review your uploaded ID and selfie before submitting.', style: TextStyle(color: Colors.grey[600])),
          const SizedBox(height: 16),
          if (_docType != null)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFE6F4F2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.badge_outlined, color: const Color(0xFF115E59)),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Document type: $_docType')),
                ],
              ),
            ),
          _buildUploadCard(
            title: 'ID Document',
            emptyIcon: Icons.credit_card,
            emptyText: 'No ID uploaded',
            bytes: _idImageBytes,
            networkUrl: _idImageUrl,
            onTap: _pickIdImage,
          ),
          const SizedBox(height: 12),
          _buildUploadCard(
            title: 'Selfie with ID',
            emptyIcon: Icons.person,
            emptyText: 'No selfie uploaded',
            bytes: _selfieImageBytes,
            networkUrl: _selfieImageUrl,
            onTap: _pickSelfieImage,
            height: 220,
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFE6F4F2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: const Color(0xFF0F766E)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _kycStatus == 'pending'
                        ? 'Your KYC is pending admin review.'
                        : _kycStatus == 'verified'
                            ? 'Your account is already verified.'
                            : 'Verification usually takes 1-2 business days after submit.',
                    style: TextStyle(color: const Color(0xFF115E59), fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}




