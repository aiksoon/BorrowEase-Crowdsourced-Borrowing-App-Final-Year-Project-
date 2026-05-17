import 'package:flutter/material.dart';
import 'package:dio/dio.dart';

import '../services/api.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

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

  String? _selectedLocation;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final me = await api.getMe();
      final user = me['user'] is Map<String, dynamic>
          ? me['user'] as Map<String, dynamic>
          : await api.getStoredUser() ?? <String, dynamic>{};
      if (!mounted) return;
      setState(() {
        _nameController.text = (user['name'] ?? '').toString();
        _emailController.text = (user['email'] ?? '').toString();
        _phoneController.text = (user['phone'] ?? '').toString();
        final rawLocation = (user['location'] ?? '').toString().trim();
        _selectedLocation = _locations.contains(rawLocation) ? rawLocation : null;
        _loading = false;
      });
    } catch (_) {
      final user = await api.getStoredUser() ?? <String, dynamic>{};
      if (!mounted) return;
      setState(() {
        _nameController.text = (user['name'] ?? '').toString();
        _emailController.text = (user['email'] ?? '').toString();
        _phoneController.text = (user['phone'] ?? '').toString();
        final rawLocation = (user['location'] ?? '').toString().trim();
        _selectedLocation = _locations.contains(rawLocation) ? rawLocation : null;
        _loading = false;
      });
    }
  }

  bool _isValidPhone(String value) {
    return RegExp(r'^[0-9]+$').hasMatch(value);
  }

  String _friendlyError(Object error, {required String fallback}) {
    if (error is DioException) {
      final data = error.response?.data;
      final status = error.response?.statusCode;
      final message = data is Map<String, dynamic>
          ? (data['message'] ?? '').toString()
          : '';

      if (status == 400 && message.toLowerCase().contains('phone')) {
        return 'Phone must contain numbers only';
      }
      if (message.isNotEmpty) {
        return message;
      }
    }
    return fallback;
  }

  Future<void> _save() async {
    if (_saving) return;

    final phone = _phoneController.text.trim();
    if (phone.isNotEmpty && !_isValidPhone(phone)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Phone must contain numbers only')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await api.updateMe(
        phone: phone,
        location: _selectedLocation,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _friendlyError(
              e,
              fallback: 'Unable to update profile. Please check your inputs and try again.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('Edit Profile'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: _nameController,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    helperText: 'Username is fixed and cannot be changed',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _emailController,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    helperText: 'Email is fixed and cannot be changed',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone Number',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _selectedLocation,
                  items: _locations
                      .map(
                        (loc) => DropdownMenuItem<String>(
                          value: loc,
                          child: Text(loc),
                        ),
                      )
                      .toList(),
                  onChanged: _saving
                      ? null
                      : (value) {
                          setState(() {
                            _selectedLocation = value;
                          });
                        },
                  decoration: const InputDecoration(
                    labelText: 'Default Location',
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 46,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save Changes'),
                  ),
                ),
              ],
            ),
    );
  }
}
