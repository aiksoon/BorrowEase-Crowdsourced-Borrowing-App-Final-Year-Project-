import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api.dart';

class EditListingPage extends StatefulWidget {
  final Map<String, dynamic> item;

  const EditListingPage({super.key, required this.item});

  @override
  State<EditListingPage> createState() => _EditListingPageState();
}

class _EditListingPageState extends State<EditListingPage> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _depositController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  final List<String> _categories = const [
    'Tools',
    'Electronics',
    'Books',
    'Furniture',
    'Sports',
    'Automotive',
    'Fashion',
    'Music',
  ];

  final List<String> _locations = const [
    'Johor',
    'Kedah',
    'Kelantan',
    'Melaka',
    'Negeri Sembilan',
    'Pahang',
    'Penang',
    'Perak',
    'Perlis',
    'Sabah',
    'Sarawak',
    'Selangor',
    'Terengganu',
    'Kuala Lumpur',
    'Putrajaya',
    'Labuan',
  ];

  String? _selectedCategory;
  String? _selectedLocation;
  bool _submitting = false;
  XFile? _pictureFile;
  XFile? _videoFile;
  String? _existingImageUrl;
  String? _existingVideoUrl;

  String? _normalizeCategory(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return null;
    if (_categories.contains(value)) return value;
    return null;
  }

  String? _normalizeLocation(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return null;
    if (_locations.contains(value)) return value;

    const alias = <String, String>{
      'JB': 'Johor',
      'KL': 'Kuala Lumpur',
      'PG': 'Penang',
      'NS': 'Negeri Sembilan',
      'MLK': 'Melaka',
      'SBH': 'Sabah',
      'SRWK': 'Sarawak',
    };
    final upper = value.toUpperCase();
    final mapped = alias[upper];
    if (mapped != null && _locations.contains(mapped)) {
      return mapped;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _titleController.text = (widget.item['title'] ?? '').toString();
    _descriptionController.text = (widget.item['description'] ?? '').toString();
    _priceController.text = (widget.item['price_per_day'] ?? '').toString();
    _depositController.text = (widget.item['deposit_amount'] ?? '').toString();
    _selectedCategory = _normalizeCategory(widget.item['category']?.toString());
    _selectedLocation = _normalizeLocation(widget.item['location_text']?.toString());
    _existingImageUrl = (widget.item['image_url'] ?? '').toString().trim();
    _existingVideoUrl = (widget.item['video_url'] ?? '').toString().trim();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _depositController.dispose();
    super.dispose();
  }

  Future<void> _pickPicture() async {
    final file = await _picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;
    setState(() => _pictureFile = file);
  }

  Future<void> _pickVideo() async {
    final file = await _picker.pickVideo(source: ImageSource.gallery);
    if (file == null) return;
    final lowerName = file.name.toLowerCase();
    final supported = lowerName.endsWith('.mp4') || lowerName.endsWith('.webm');
    if (!supported) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please upload MP4 or WEBM video.')),
      );
      return;
    }
    setState(() => _videoFile = file);
  }

  void _showCategoryPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final maxHeight = MediaQuery.of(context).size.height * 0.7;
        return SafeArea(
          child: SizedBox(
            height: maxHeight,
            child: Column(
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    itemCount: _categories.length,
                    itemBuilder: (context, index) {
                      final category = _categories[index];
                      final selected = _selectedCategory == category;
                      return ListTile(
                        title: Text(category),
                        trailing: selected
                            ? Icon(Icons.check, color: const Color(0xFF0F766E))
                            : null,
                        onTap: () {
                          setState(() => _selectedCategory = category);
                          Navigator.pop(context);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final id = (widget.item['id'] as num?)?.toInt();
    if (id == null) return;

    final title = _titleController.text.trim();
    final description = _descriptionController.text.trim();
    final price = double.tryParse(_priceController.text.trim());
    final depositText = _depositController.text.trim();
    final deposit = depositText.isEmpty ? 0.0 : double.tryParse(depositText);

    if (title.isEmpty || price == null || price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please provide valid title and rental fee.')),
      );
      return;
    }
    if (deposit == null || deposit < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please provide a valid security deposit (0 or above).')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      String? finalImage = _existingImageUrl;
      String? finalVideo = _existingVideoUrl;

      if (_pictureFile != null || _videoFile != null) {
        final files = <MultipartFile>[];
        if (_pictureFile != null) {
          files.add(
            MultipartFile.fromBytes(
              await _pictureFile!.readAsBytes(),
              filename: _pictureFile!.name,
            ),
          );
        }
        if (_videoFile != null) {
          files.add(
            MultipartFile.fromBytes(
              await _videoFile!.readAsBytes(),
              filename: _videoFile!.name,
            ),
          );
        }

        final uploaded = await api.uploadFiles(files);
        var idx = 0;
        if (_pictureFile != null && uploaded.length > idx) {
          finalImage = uploaded[idx++];
        }
        if (_videoFile != null && uploaded.length > idx) {
          finalVideo = uploaded[idx];
        }
      }

      if ((finalImage ?? '').trim().isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Picture is required.')),
        );
        return;
      }

      await api.updateItem(
        id: id,
        title: title,
        description: description.isEmpty ? null : description,
        category: _selectedCategory,
        pricePerDay: price,
        depositAmount: deposit,
        locationText: _selectedLocation,
        imageUrl: finalImage,
        videoUrl: (finalVideo ?? '').trim().isEmpty ? '' : finalVideo,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Listing updated')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Update failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        title: const Text('Edit Listing'),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildUploadRow(
              label: 'Picture *',
              buttonText: _pictureFile == null ? 'Change Picture' : 'Replace Picture',
              fileName: _pictureFile?.name,
              icon: Icons.image_outlined,
              onTap: _submitting ? null : _pickPicture,
              onClear: _pictureFile == null || _submitting
                  ? null
                  : () => setState(() => _pictureFile = null),
            ),
            const SizedBox(height: 12),
            _buildUploadRow(
              label: 'Video (optional)',
              buttonText: _videoFile == null ? 'Change Video' : 'Replace Video',
              fileName: _videoFile?.name,
              icon: Icons.videocam_outlined,
              onTap: _submitting ? null : _pickVideo,
              onClear: _videoFile == null || _submitting
                  ? null
                  : () => setState(() => _videoFile = null),
            ),
            const SizedBox(height: 16),
            _buildTextField(
              label: 'Title *',
              hint: 'e.g., Professional Power Drill',
              controller: _titleController,
            ),
            const SizedBox(height: 16),
            _buildTextField(
              label: 'Description',
              hint: 'Describe condition, accessories, pickup notes...',
              controller: _descriptionController,
              maxLines: 4,
            ),
            const SizedBox(height: 16),
            const Text(
              'Category',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.black87),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _showCategoryPicker,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_selectedCategory ?? 'Select a category', style: TextStyle(color: Colors.grey[700])),
                    Icon(Icons.keyboard_arrow_down, color: Colors.grey[500]),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildTextField(
                    label: 'Rental fee per day (RM) *',
                    hint: 'e.g., 15',
                    controller: _priceController,
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildTextField(
                    label: 'Security deposit (RM)',
                    hint: 'e.g., 80',
                    controller: _depositController,
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Location',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.black87),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedLocation,
                  hint: Text('Select a location', style: TextStyle(color: Colors.grey[500])),
                  isExpanded: true,
                  icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  onChanged: _submitting ? null : (value) => setState(() => _selectedLocation = value),
                  items: _locations
                      .map((loc) => DropdownMenuItem<String>(
                            value: loc,
                            child: Row(
                              children: [
                                Icon(Icons.location_on_outlined, color: Colors.grey[500], size: 18),
                                const SizedBox(width: 8),
                                Text(loc),
                              ],
                            ),
                          ))
                      .toList(),
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                child: Text(
                  _submitting ? 'Submitting...' : 'Update Item',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required String hint,
    TextEditingController? controller,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.black87),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(12),
          ),
          child: TextField(
            controller: controller,
            maxLines: maxLines,
            keyboardType: keyboardType,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUploadRow({
    required String label,
    required String buttonText,
    required IconData icon,
    required VoidCallback? onTap,
    required VoidCallback? onClear,
    String? fileName,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onTap,
                icon: Icon(icon, size: 18),
                label: Text(buttonText),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.black87,
                  side: BorderSide(color: Colors.grey[300]!),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            if (onClear != null) ...[
              const SizedBox(width: 8),
              IconButton(onPressed: onClear, icon: const Icon(Icons.close)),
            ],
          ],
        ),
        if (fileName != null && fileName.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              fileName,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              overflow: TextOverflow.ellipsis,
            ),
          )
        else if ((label.contains('Picture') && (_existingImageUrl ?? '').isNotEmpty) ||
            (label.contains('Video') && (_existingVideoUrl ?? '').isNotEmpty))
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Existing file will be kept if not replaced',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ),
      ],
    );
  }
}


