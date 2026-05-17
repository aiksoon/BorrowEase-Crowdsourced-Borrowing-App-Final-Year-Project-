import 'dart:async';

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api.dart';
import '../services/api_client.dart' show defaultBaseUrl;
import 'screens.dart';

// ==================== PROFILE PAGE ====================
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Map<String, dynamic>? _user;
  bool _loading = true;
  bool _isAdmin = false;
  double _rating = 5.0;
  int _itemsLent = 0;
  int _transactions = 0;
  int _borrowed = 0;
  bool _uploadingAvatar = false;
  final ImagePicker _picker = ImagePicker();
  Timer? _kycStatusPoller;

  @override
  void initState() {
    super.initState();
    _loadUser();
    _startKycStatusPolling();
  }

  @override
  void dispose() {
    _kycStatusPoller?.cancel();
    super.dispose();
  }

  void _startKycStatusPolling() {
    _kycStatusPoller?.cancel();
    _kycStatusPoller = Timer.periodic(const Duration(seconds: 8), (_) {
      _refreshKycStatusAjax(silent: true);
    });
  }

  Future<void> _refreshKycStatusAjax({bool silent = false}) async {
    try {
      final me = await api.getMe();
      final meUser = me['user'];
      if (meUser is! Map<String, dynamic>) return;

      final latest = Map<String, dynamic>.from(meUser);
      final current = _user ?? <String, dynamic>{};

      final currentStatus = (current['kyc_status'] ?? '')
          .toString()
          .toLowerCase();
      final latestStatus = (latest['kyc_status'] ?? '')
          .toString()
          .toLowerCase();
      final currentAvatar = (current['avatar_url'] ?? '').toString();
      final latestAvatar = (latest['avatar_url'] ?? '').toString();

      final changed =
          currentStatus != latestStatus || currentAvatar != latestAvatar;
      if (!mounted || !changed) return;

      setState(() {
        _user = <String, dynamic>{...current, ...latest};
      });
    } catch (_) {
      if (!silent) {
        // Keep profile usable when network is flaky.
      }
    }
  }

  Future<void> _loadUser() async {
    try {
      Map<String, dynamic>? data = await api.getStoredUser();
      final int? userId = _toInt(data?['id']);
      bool isAdmin = false;

      if (userId != null) {
        try {
          final me = await api.getMe();
          final meUser = me['user'];
          if (meUser is Map<String, dynamic>) {
            data = meUser;
          }
        } catch (_) {
          // Keep local user fallback.
        }

        try {
          final profile = await api.getUserProfile(userId);
          final stats = Map<String, dynamic>.from(
            (profile['stats'] as Map<String, dynamic>?) ??
                const <String, dynamic>{},
          );
          final mergedUser = <String, dynamic>{
            ...(data ?? <String, dynamic>{}),
            if (profile['name'] != null) 'name': profile['name'],
            if (profile['avatar_url'] != null)
              'avatar_url': profile['avatar_url'],
            if (profile['kyc_status'] != null)
              'kyc_status': profile['kyc_status'],
          };
          data = mergedUser;
          _rating = _toDouble(stats['rating'], 5.0);
          _itemsLent = _toInt(stats['itemsLent']) ?? 0;
          _transactions = _toInt(stats['transactions']) ?? 0;
          _borrowed =
              _toInt(stats['borrowed']) ?? _toInt(stats['itemsBorrowed']) ?? 0;
        } catch (_) {
          _rating = 5.0;
          _itemsLent = 0;
          _transactions = 0;
          _borrowed = 0;
        }

        if (_borrowed == 0) {
          try {
            final borrowRequests = await api.getRequests(role: 'borrower');
            final activeOrCompleted = borrowRequests.where((raw) {
              if (raw is! Map<String, dynamic>) return false;
              final status = (raw['status'] ?? '').toString();
              return status == 'accepted' ||
                  status == 'handover' ||
                  status == 'in_use' ||
                  status == 'return_pending' ||
                  status == 'completed';
            }).length;
            _borrowed = activeOrCompleted;
          } catch (_) {
            // Keep stats-based value when requests endpoint is unavailable.
          }
        }

        try {
          await api.getAdminDashboardStats();
          isAdmin = true;
        } catch (_) {
          isAdmin = false;
        }
      }

      if (!mounted) return;
      setState(() {
        _user = data;
        _isAdmin = isAdmin;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isAdmin = false;
        _loading = false;
      });
    }
  }

  int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  double _toDouble(dynamic value, double fallback) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? fallback;
    return fallback;
  }

  String? _resolveMediaUrl(dynamic raw) {
    final value = (raw ?? '').toString().trim();
    if (value.isEmpty) return null;
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    if (value.startsWith('/')) return '$defaultBaseUrl$value';
    return '$defaultBaseUrl/$value';
  }

  String _avatarInitial(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    final match = RegExp(r'[A-Za-z0-9]').firstMatch(trimmed);
    if (match != null) {
      return (match.group(0) ?? '?').toUpperCase();
    }
    return trimmed.characters.first.toUpperCase();
  }

  Future<void> _uploadAvatar() async {
    if (_uploadingAvatar) return;
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (!mounted || file == null) return;

      setState(() => _uploadingAvatar = true);
      final files = <MultipartFile>[
        MultipartFile.fromBytes(await file.readAsBytes(), filename: file.name),
      ];
      final uploadedUrls = await api.uploadFiles(files);
      if (uploadedUrls.isEmpty) {
        throw Exception('Upload returned no URL');
      }
      final updated = await api.updateMe(avatarUrl: uploadedUrls.first);
      final user = updated['user'] is Map<String, dynamic>
          ? updated['user'] as Map<String, dynamic>
          : _user;

      if (!mounted) return;
      setState(() {
        _user = user;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Avatar updated successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to upload avatar. Please try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _openSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit Profile'),
                onTap: () async {
                  Navigator.pop(context);
                  final changed = await Navigator.push<bool>(
                    this.context,
                    MaterialPageRoute(builder: (_) => const EditProfilePage()),
                  );
                  if (changed == true) {
                    await _loadUser();
                  }
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.account_balance_wallet_outlined,
                  color: Color(0xFF0D9488),
                ),
                title: const Text('Payout Account'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    this.context,
                    MaterialPageRoute(
                      builder: (_) => const PayoutSettingsPage(),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.lock_outline),
                title: const Text('Change Password'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    this.context,
                    MaterialPageRoute(
                      builder: (_) => const ChangePasswordPage(),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.help_outline),
                title: const Text('Help Center / FAQ'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    this.context,
                    MaterialPageRoute(builder: (_) => const HelpCenterPage()),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.privacy_tip_outlined),
                title: const Text('Privacy Policy & Terms of Service'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    this.context,
                    MaterialPageRoute(builder: (_) => const PrivacyTermsPage()),
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _logout() async {
    await api.signOut();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const WelcomePage()),
      (route) => false,
    );
  }

  Future<void> _openKycVerification() async {
    final status = (_user?['kyc_status'] ?? '').toString().toLowerCase().trim();
    if (status == 'pending') {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('KYC is under review. Please wait for admin approval.'),
        ),
      );
      return;
    }
    if (status == 'verified') {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You have already completed KYC verification.'),
        ),
      );
      return;
    }

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const KYCVerificationPage()),
    );
    await _refreshKycStatusAjax();
  }

  @override
  Widget build(BuildContext context) {
    final name = (_user?['name'] ?? 'Guest').toString();
    final email = (_user?['email'] ?? '').toString();
    final rawKycStatus = (_user?['kyc_status'] ?? '').toString();
    final avatarUrl = _resolveMediaUrl(_user?['avatar_url']);
    final normalizedKyc = rawKycStatus.toLowerCase().trim();
    final isVerified = normalizedKyc == 'verified';
    final isPending = normalizedKyc == 'pending';
    final badgeText = isVerified
        ? 'Verified'
        : isPending
        ? 'Pending Verification'
        : 'Not Verified';
    final badgeIcon = isVerified ? Icons.verified : Icons.gpp_maybe_rounded;
    final badgeBg = isVerified
        ? const Color(0xFFE8F8EE)
        : const Color(0xFFFFF6D8);
    final badgeFg = isVerified
        ? const Color(0xFF1A7F37)
        : const Color(0xFF8A5A00);

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                child: Column(
                  children: [
                    // Header with gradient background
                    SizedBox(
                      height: 170,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            height: 120,
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Color(0x330D9488), Color(0x000D9488)],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                            ),
                          ),
                          Positioned(
                            top: 16,
                            right: 16,
                            child: IconButton(
                              onPressed: _openSettings,
                              icon: Icon(
                                Icons.settings_outlined,
                                color: Colors.grey[700],
                              ),
                            ),
                          ),
                          Positioned(
                            top: 75,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: _uploadingAvatar ? null : _uploadAvatar,
                                child: Container(
                                  width: 90,
                                  height: 90,
                                  decoration: BoxDecoration(
                                    color: avatarUrl == null
                                        ? const Color(
                                            0xFF0D9488,
                                          ).withValues(alpha: 0.12)
                                        : Colors.grey[300],
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 4,
                                    ),
                                    image: avatarUrl != null
                                        ? DecorationImage(
                                            image: NetworkImage(avatarUrl),
                                            fit: BoxFit.cover,
                                          )
                                        : null,
                                  ),
                                  child: _uploadingAvatar
                                      ? const Center(
                                          child: SizedBox(
                                            width: 22,
                                            height: 22,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          ),
                                        )
                                      : Stack(
                                          children: [
                                            if (avatarUrl == null)
                                              Center(
                                                child: Text(
                                                  _avatarInitial(name),
                                                  style: const TextStyle(
                                                    fontSize: 42,
                                                    fontWeight: FontWeight.w700,
                                                    color: Color(0xFF0F766E),
                                                    height: 1,
                                                  ),
                                                ),
                                              ),
                                            Align(
                                              alignment: Alignment.bottomRight,
                                              child: Container(
                                                margin: const EdgeInsets.all(2),
                                                padding: const EdgeInsets.all(
                                                  4,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Colors.black
                                                      .withValues(alpha: 0.6),
                                                  shape: BoxShape.circle,
                                                ),
                                                child: const Icon(
                                                  Icons.camera_alt,
                                                  size: 14,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Name and Username
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      email.isNotEmpty ? email : 'Not signed in',
                      style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                    ),
                    const SizedBox(height: 12),

                    // Verified Badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: badgeBg,
                        border: Border.all(
                          color: badgeFg.withValues(alpha: 0.35),
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(badgeIcon, size: 16, color: badgeFg),
                          const SizedBox(width: 4),
                          Text(
                            badgeText,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: badgeFg,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Stats Row (same style as user profile, tappable)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: GestureDetector(
                        onTap: () {
                          final userId = _toInt(_user?['id']);
                          if (userId == null) return;
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => UserProfilePage(
                                userId: userId,
                                title: 'User Profile',
                                displayName: name,
                              ),
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey[200]!),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: _buildStat(
                                  _rating.toStringAsFixed(1),
                                  'Rating',
                                  showStar: true,
                                ),
                              ),
                              Container(
                                width: 1,
                                height: 36,
                                color: Colors.grey[200],
                              ),
                              Expanded(
                                child: _buildStat(
                                  _itemsLent.toString(),
                                  'Items Lent',
                                ),
                              ),
                              Container(
                                width: 1,
                                height: 36,
                                color: Colors.grey[200],
                              ),
                              Expanded(
                                child: _buildStat(
                                  _transactions.toString(),
                                  'Transactions',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Menu Items
                    _buildProfileMenuItem(
                      context,
                      Icons.inventory_2_outlined,
                      'My Listings',
                      subtitle: 'Manage your items and view requests',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const MyListingsPage(),
                          ),
                        );
                      },
                    ),
                    _buildProfileMenuItem(
                      context,
                      Icons.favorite_outline,
                      'My Favourites',
                      subtitle: 'Saved items',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const MyFavouritesPage(),
                          ),
                        );
                      },
                    ),
                    _buildProfileMenuItem(
                      context,
                      Icons.shopping_bag_outlined,
                      'Items I\'m Borrowing',
                      subtitle: 'Borrower: Items you\'re borrowing',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const MyBorrowingsPage(),
                          ),
                        );
                      },
                    ),
                    _buildProfileMenuItem(
                      context,
                      Icons.verified_user_outlined,
                      'KYC Verification',
                      subtitle: badgeText,
                      onTap: _openKycVerification,
                    ),
                    _buildProfileMenuItem(
                      context,
                      Icons.receipt_long_outlined,
                      'Transaction History',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                const TransactionHistoryPage(),
                          ),
                        );
                      },
                    ),
                    _buildProfileMenuItem(
                      context,
                      Icons.flag_outlined,
                      'Report an Issue',
                      subtitle: 'Submit a dispute with order evidence',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const SubmitReportPage(),
                          ),
                        );
                      },
                    ),
                    if (_isAdmin)
                      _buildProfileMenuItem(
                        context,
                        Icons.admin_panel_settings_outlined,
                        'Admin Dashboard',
                        subtitle: 'For administrators',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const AdminDashboardPage(),
                            ),
                          );
                        },
                      ),

                    const SizedBox(height: 12),
                    // Logout button
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _logout,
                          icon: const Icon(
                            Icons.logout,
                            size: 18,
                            color: Colors.black87,
                          ),
                          label: const Text(
                            'Logout',
                            style: TextStyle(color: Colors.black87),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: BorderSide(color: Colors.grey[300]!),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildStat(String value, String label, {bool showStar = false}) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showStar)
              const Icon(
                Icons.star_rounded,
                size: 18,
                color: Color(0xFFF4B400),
              ),
            if (showStar) const SizedBox(width: 3),
            Text(
              value,
              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }

  Widget _buildProfileMenuItem(
    BuildContext context,
    IconData icon,
    String title, {
    String? subtitle,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFE6F4F2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 20, color: const Color(0xFF0F766E)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}
