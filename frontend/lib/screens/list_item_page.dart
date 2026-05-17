import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api.dart';

class ListItemPage extends StatefulWidget {
  const ListItemPage({super.key});

  @override
  State<ListItemPage> createState() => _ListItemPageState();
}

class _ListItemPageState extends State<ListItemPage> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _depositController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  final List<String> _categories = [
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
  bool _isSubmitting = false;
  XFile? _pictureFile;
  XFile? _videoFile;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _depositController.dispose();
    super.dispose();
  }

  Future<void> _submitItem() async {
    final title = _titleController.text.trim();
    final priceText = _priceController.text.trim();
    final depositText = _depositController.text.trim();
    final description = _descriptionController.text.trim();
    final locationText = _selectedLocation;

    if (title.isEmpty || priceText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Title and price are required'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final price = double.tryParse(priceText);
    if (price == null || price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a valid rental fee per day'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final deposit = depositText.isEmpty ? 0.0 : double.tryParse(depositText);
    if (deposit == null || deposit < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a valid security deposit (0 or above)'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    if (_pictureFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Picture is required'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final uploadFiles = <MultipartFile>[
        MultipartFile.fromBytes(
          await _pictureFile!.readAsBytes(),
          filename: _pictureFile!.name,
        ),
      ];
      if (_videoFile != null) {
        uploadFiles.add(
          MultipartFile.fromBytes(
            await _videoFile!.readAsBytes(),
            filename: _videoFile!.name,
          ),
        );
      }
      final uploadedUrls = await api.uploadFiles(uploadFiles);
      if (uploadedUrls.isEmpty) {
        throw Exception('File upload failed');
      }

      await api.createItem(
        title: title,
        pricePerDay: price,
        depositAmount: deposit,
        imageUrl: uploadedUrls.first,
        videoUrl: uploadedUrls.length > 1 ? uploadedUrls[1] : null,
        category: _selectedCategory,
        description: description.isEmpty ? null : description,
        locationText: locationText,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Item listed'),
          duration: Duration(seconds: 2),
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Submit failed: $e'),
          duration: const Duration(seconds: 2),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
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
        const SnackBar(
          content: Text(
            'Please upload MP4 or WEBM video for better playback compatibility.',
          ),
          duration: Duration(seconds: 2),
        ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        title: const Text('List an Item'),
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
              buttonText: _pictureFile == null
                  ? 'Upload Picture'
                  : 'Change Picture',
              fileName: _pictureFile?.name,
              icon: Icons.image_outlined,
              onTap: _isSubmitting ? null : _pickPicture,
              onClear: _pictureFile == null || _isSubmitting
                  ? null
                  : () => setState(() => _pictureFile = null),
            ),
            const SizedBox(height: 12),
            _buildUploadRow(
              label: 'Video (optional)',
              buttonText: _videoFile == null ? 'Upload Video' : 'Change Video',
              fileName: _videoFile?.name,
              icon: Icons.videocam_outlined,
              onTap: _isSubmitting ? null : _pickVideo,
              onClear: _videoFile == null || _isSubmitting
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
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _showCategoryPicker,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _selectedCategory ?? 'Select a category',
                      style: TextStyle(color: Colors.grey[700]),
                    ),
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
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
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
                  hint: Text(
                    'Select a location',
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                  isExpanded: true,
                  icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  onChanged: _isSubmitting
                      ? null
                      : (value) => setState(() => _selectedLocation = value),
                  items: _locations
                      .map(
                        (loc) => DropdownMenuItem<String>(
                          value: loc,
                          child: Row(
                            children: [
                              Icon(
                                Icons.location_on_outlined,
                                color: Colors.grey[500],
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(loc),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitItem,
                child: Text(
                  _isSubmitting ? 'Submitting...' : 'List Item',
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
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
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
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
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
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onTap,
                icon: Icon(icon, size: 18),
                label: Text(buttonText),
              ),
            ),
            if (fileName != null) ...[
              const SizedBox(width: 8),
              IconButton(
                onPressed: onClear,
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'Remove file',
              ),
            ],
          ],
        ),
        if (fileName != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              fileName,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }
}


