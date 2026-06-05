import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api.dart';

class SubmitReportPage extends StatefulWidget {
  const SubmitReportPage({super.key});

  @override
  State<SubmitReportPage> createState() => _SubmitReportPageState();
}

class _SubmitReportPageState extends State<SubmitReportPage> {
  static const Color _ecoTeal = Color(0xFF0D9488);
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  bool _loadingOrders = true;
  bool _submitting = false;
  int _allCompletedOrderCount = 0;
  List<Map<String, dynamic>> _completedOrders = <Map<String, dynamic>>[];
  int? _selectedRequestId;
  String? _selectedReason;
  final List<XFile> _selectedMedia = <XFile>[];

  final List<String> _reasons = const <String>[
    'Item Damaged',
    'Late Return',
    'Fake Item',
    'Missing Accessories',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _loadCompletedOrders();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  Future<void> _loadCompletedOrders() async {
    setState(() => _loadingOrders = true);
    try {
      final results = await Future.wait<dynamic>([
        api.getRequests(),
        api.getReports(),
      ]);

      final requests = results[0] as List<dynamic>;
      final reports = results[1] as List<dynamic>;

      final reportedRequestIds = reports
          .whereType<Map<String, dynamic>>()
          .map((r) => _toInt(r['request_id'] ?? r['target_id']))
          .whereType<int>()
          .toSet();

      final completed = requests
          .whereType<Map<String, dynamic>>()
          .where(
            (r) => (r['status'] ?? '').toString().toLowerCase() == 'completed',
          )
          .where((r) => !reportedRequestIds.contains(_toInt(r['id'])))
          .toList();
      final allCompletedCount = requests
          .whereType<Map<String, dynamic>>()
          .where(
            (r) => (r['status'] ?? '').toString().toLowerCase() == 'completed',
          )
          .length;

      if (!mounted) return;
      setState(() {
        _allCompletedOrderCount = allCompletedCount;
        _completedOrders = completed;
        _loadingOrders = false;
        if (completed.isNotEmpty) {
          _selectedRequestId = _toInt(completed.first['id']);
        } else {
          _selectedRequestId = null;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingOrders = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load completed orders: $e')),
      );
    }
  }

  String _orderLabel(Map<String, dynamic> order) {
    final id = _toInt(order['id']) ?? 0;
    final title = (order['item_title'] ?? 'Item').toString();
    return 'Order #$id - $title';
  }

  Future<void> _pickImages() async {
    try {
      final images = await _picker.pickMultiImage(imageQuality: 85);
      if (images.isEmpty) return;
      setState(() {
        _selectedMedia.addAll(images);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Image picker error: $e')));
    }
  }

  Future<void> _pickVideo() async {
    try {
      final video = await _picker.pickVideo(source: ImageSource.gallery);
      if (video == null) return;
      setState(() {
        _selectedMedia.add(video);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Video picker error: $e')));
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedRequestId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select an order.')));
      return;
    }

    setState(() => _submitting = true);
    try {
      List<String> mediaUrls = <String>[];
      if (_selectedMedia.isNotEmpty) {
        final files = <MultipartFile>[];
        for (final file in _selectedMedia) {
          files.add(
            MultipartFile.fromBytes(
              await file.readAsBytes(),
              filename: file.name,
            ),
          );
        }
        mediaUrls = await api.uploadFiles(files);
      }

      await api.createReport(
        requestId: _selectedRequestId,
        reasonCategory: _selectedReason,
        description: _descriptionController.text.trim(),
        mediaUrls: mediaUrls,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Report submitted successfully.')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to submit report: $e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _buildUploadBox() {
    return CustomPaint(
      painter: _DashedBorderPainter(
        color: _ecoTeal.withValues(alpha: 0.65),
        radius: 12,
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            const Icon(Icons.file_upload_outlined, color: _ecoTeal),
            const SizedBox(height: 8),
            const Text(
              'Upload Photos/Video',
              style: TextStyle(fontWeight: FontWeight.w600, color: _ecoTeal),
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _pickImages,
                  icon: const Icon(Icons.photo_library_outlined, size: 18),
                  label: const Text('Photos'),
                ),
                OutlinedButton.icon(
                  onPressed: _pickVideo,
                  icon: const Icon(Icons.videocam_outlined, size: 18),
                  label: const Text('Video'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbnails() {
    if (_selectedMedia.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: List.generate(
            4,
            (index) => Expanded(
              child: Container(
                margin: EdgeInsets.only(right: index == 3 ? 0 : 8),
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.image_outlined, color: Colors.grey[500]),
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 78,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _selectedMedia.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final file = _selectedMedia[index];
          final isVideo =
              file.name.toLowerCase().endsWith('.mp4') ||
              file.name.toLowerCase().endsWith('.mov') ||
              file.name.toLowerCase().endsWith('.webm');
          return Stack(
            children: [
              Container(
                width: 86,
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: isVideo
                    ? const Center(
                        child: Icon(Icons.play_circle_outline, size: 30),
                      )
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(
                          file.path,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              const Center(child: Icon(Icons.image_outlined)),
                        ),
                      ),
              ),
              Positioned(
                top: 2,
                right: 2,
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _selectedMedia.removeAt(index);
                    });
                  },
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(2),
                    child: const Icon(
                      Icons.close,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      appBar: AppBar(
        title: const Text('Submit Report'),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: _loadingOrders
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 12,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Order Selection',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 10),
                          DropdownButtonFormField<int>(
                            initialValue: _selectedRequestId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                            ),
                            items: _completedOrders
                                .map(
                                  (order) => DropdownMenuItem<int>(
                                    value: _toInt(order['id']),
                                    child: Text(
                                      _orderLabel(order),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            selectedItemBuilder: (context) {
                              return _completedOrders
                                  .map(
                                    (order) => Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        _orderLabel(order),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList();
                            },
                            onChanged: (value) {
                              setState(() => _selectedRequestId = value);
                            },
                            validator: (value) =>
                                value == null ? 'Please select an order' : null,
                          ),
                          if (_completedOrders.isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: Text(
                                _allCompletedOrderCount == 0
                                    ? 'No completed transactions found.'
                                    : 'All completed orders have already been reported.',
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                            ),
                          const SizedBox(height: 18),
                          const Text(
                            'Reason Category',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 10),
                          DropdownButtonFormField<String>(
                            initialValue: _selectedReason,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                            ),
                            items: _reasons
                                .map(
                                  (reason) => DropdownMenuItem<String>(
                                    value: reason,
                                    child: Text(reason),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              setState(() => _selectedReason = value);
                            },
                            validator: (value) => value == null || value.isEmpty
                                ? 'Please choose a reason'
                                : null,
                          ),
                          const SizedBox(height: 18),
                          const Text(
                            'Description',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: _descriptionController,
                            maxLines: 4,
                            decoration: const InputDecoration(
                              hintText: 'Please describe the issue in detail',
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) {
                              final text = (value ?? '').trim();
                              if (text.isEmpty) {
                                return 'Please enter a description';
                              }
                              if (text.length < 10) {
                                return 'Description should be at least 10 characters';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 18),
                          const Text(
                            'Media Upload',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 10),
                          _buildUploadBox(),
                          const SizedBox(height: 10),
                          _buildThumbnails(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: (_submitting || _completedOrders.isEmpty)
                ? null
                : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: _ecoTeal,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text(
                    'Submit Report',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;

  _DashedBorderPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );

    const dashWidth = 6.0;
    const dashSpace = 4.0;
    final path = Path()..addRRect(rect);
    final metrics = path.computeMetrics();
    for (final metric in metrics) {
      double distance = 0;
      while (distance < metric.length) {
        final next = distance + dashWidth;
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.radius != radius;
  }
}
