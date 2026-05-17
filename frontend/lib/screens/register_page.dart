import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import '../utils/navigator_key.dart';
import '../services/api.dart';
import 'screens.dart';

const Color _ecoTeal = Color(0xFF0D9488);

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final FocusNode _passwordFocusNode = FocusNode();

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
  String? _emailError;
  String? _usernameError;
  String? _passwordError;
  String? _phoneError;
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _passwordFocusNode.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  bool _isValidPassword(String value) {
    if (value.length < 8) return false;
    final hasUpper = RegExp(r'[A-Z]').hasMatch(value);
    final hasLower = RegExp(r'[a-z]').hasMatch(value);
    final hasDigit = RegExp(r'[0-9]').hasMatch(value);
    final hasSpecial = RegExp(r'[!@#\$%\^&*]').hasMatch(value);
    return hasUpper && hasLower && hasDigit && hasSpecial;
  }

  bool _isValidPhone(String value) {
    return RegExp(r'^[0-9]+$').hasMatch(value);
  }

  Future<void> _handleRegister() async {
    final name = _usernameController.text.trim();
    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text.trim();
    final phone = _phoneController.text.trim();

    if (name.isEmpty ||
        email.isEmpty ||
        password.isEmpty ||
        _selectedLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill username, email, password, and location'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    final validEmail = emailRegex.hasMatch(email);
    final validPassword = _isValidPassword(password);
    final validPhone = phone.isEmpty || _isValidPhone(phone);

    setState(() {
      _usernameError = null;
      _emailError = validEmail ? null : 'Please enter a valid address';
      _passwordError = validPassword
          ? null
          : 'At least 8 chars with A-Z, a-z, 0-9, and !@#%^&*';
      _phoneError = validPhone ? null : 'Phone must contain numbers only';
    });

    if (!validEmail || !validPassword || !validPhone) return;

    setState(() => _isLoading = true);
    try {
      await api.register(
        email: email,
        password: password,
        name: name,
        location: _selectedLocation,
        phone: phone.isEmpty ? null : phone,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Registration successful! Welcome, $name'),
            duration: const Duration(seconds: 2),
          ),
        );
        await Future.delayed(const Duration(milliseconds: 600));
        phoneNavigatorKey.currentState?.pushReplacement(
          MaterialPageRoute(builder: (context) => const MainNavigationPage()),
        );
      }
    } catch (e) {
      var message = 'Registration failed. Please try again.';
      if (e is DioException) {
        final status = e.response?.statusCode;
        final data = e.response?.data;
        final serverMessage = data is Map<String, dynamic>
            ? (data['message'] ?? '').toString()
            : '';
        final serverCode = data is Map<String, dynamic>
            ? (data['code'] ?? '').toString()
            : '';

        if (status == 409) {
          if (serverCode == 'EMAIL_EXISTS' ||
              serverMessage.toLowerCase().contains('email')) {
            if (mounted) {
              setState(() {
                _emailError = 'Email already registered';
              });
            }
            message =
                'Email already registered. Please use another email or login.';
          } else if (serverCode == 'USERNAME_EXISTS' ||
              serverMessage.toLowerCase().contains('username')) {
            if (mounted) {
              setState(() {
                _usernameError = 'Username already taken';
              });
            }
            message = 'Username already taken. Please choose another username.';
          } else {
            message = serverMessage.isNotEmpty
                ? serverMessage
                : 'Email or username already registered';
          }
        } else if (status == 400) {
          if (serverCode == 'PHONE_INVALID' ||
              serverMessage.toLowerCase().contains('phone')) {
            if (mounted) {
              setState(() {
                _phoneError = 'Phone must contain numbers only';
              });
            }
          }
          message = serverMessage.isNotEmpty
              ? serverMessage
              : 'Please check your input and try again.';
        } else if (serverMessage.isNotEmpty) {
          message = serverMessage;
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: SizedBox(
                  height: 56,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: GestureDetector(
                          onTap: () {
                            final nav = phoneNavigatorKey.currentState;
                            if (nav != null && nav.canPop()) {
                              nav.pop();
                            } else {
                              nav?.pushReplacement(
                                MaterialPageRoute(
                                  builder: (context) => const WelcomePage(),
                                ),
                              );
                            }
                          },
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.arrow_back,
                              size: 20,
                              color: Colors.grey[800],
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 56),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Create Account',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey[800],
                              ),
                            ),
                            Text(
                              'Join to lend and borrow',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTextField(
                      controller: _usernameController,
                      label: 'Username',
                      hintText: 'your username',
                      prefixIcon: Icons.person_outline,
                      errorText: _usernameError,
                      onChanged: (value) {
                        if (_usernameError != null && value.trim().isNotEmpty) {
                          setState(() => _usernameError = null);
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(
                      controller: _emailController,
                      label: 'Email',
                      hintText: 'you@example.com',
                      prefixIcon: Icons.mail_outline,
                      keyboardType: TextInputType.emailAddress,
                      errorText: _emailError,
                      onChanged: (value) {
                        final valid = RegExp(
                          r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                        ).hasMatch(value.trim());
                        if (valid != (_emailError == null)) {
                          setState(() {
                            _emailError = valid
                                ? null
                                : 'Please enter a valid address';
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Password',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[800],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: TextField(
                        controller: _passwordController,
                        focusNode: _passwordFocusNode,
                        obscureText: _obscurePassword,
                        onChanged: (value) {
                          final trimmed = value.trim();
                          setState(() {
                            _passwordError =
                                trimmed.isEmpty || _isValidPassword(trimmed)
                                ? null
                                : 'At least 8 chars with A-Z, a-z, 0-9, and !@#%^&*';
                          });
                        },
                        decoration: InputDecoration(
                          hintText: '********',
                          hintStyle: TextStyle(color: Colors.grey[400]),
                          prefixIcon: Icon(
                            Icons.lock_outline,
                            color: Colors.grey[500],
                            size: 20,
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color: Colors.grey[500],
                              size: 20,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: Colors.grey[200]!,
                              width: 1,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: _ecoTeal,
                              width: 1.5,
                            ),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: Colors.red[300]!,
                              width: 1,
                            ),
                          ),
                          focusedErrorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: Colors.red[400]!,
                              width: 1.5,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          errorText: _passwordError,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Use at least 8 characters with a mix of letters, numbers & symbols.',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    if (_passwordFocusNode.hasFocus ||
                        _passwordController.text.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _buildPasswordRule(
                        label: '8+ characters',
                        passed: _passwordController.text.trim().length >= 8,
                      ),
                      const SizedBox(height: 4),
                      _buildPasswordRule(
                        label: 'Uppercase and lowercase letters',
                        passed:
                            RegExp(r'[A-Z]').hasMatch(
                              _passwordController.text.trim(),
                            ) &&
                            RegExp(r'[a-z]').hasMatch(
                              _passwordController.text.trim(),
                            ),
                      ),
                      const SizedBox(height: 4),
                      _buildPasswordRule(
                        label: 'At least 1 number',
                        passed: RegExp(
                          r'[0-9]',
                        ).hasMatch(_passwordController.text.trim()),
                      ),
                      const SizedBox(height: 4),
                      _buildPasswordRule(
                        label: 'At least 1 symbol (!@#%^&*)',
                        passed: RegExp(
                          r'[!@#\$%\^&*]',
                        ).hasMatch(_passwordController.text.trim()),
                      ),
                    ],
                    const SizedBox(height: 16),
                    _buildTextField(
                      controller: _phoneController,
                      label: 'Phone',
                      hintText: '0123456789',
                      prefixIcon: Icons.phone_outlined,
                      keyboardType: TextInputType.phone,
                      errorText: _phoneError,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: (value) {
                        final valid =
                            value.trim().isEmpty || _isValidPhone(value.trim());
                        if (valid != (_phoneError == null)) {
                          setState(() {
                            _phoneError = valid
                                ? null
                                : 'Phone must contain numbers only';
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Location',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[800],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedLocation,
                          hint: Text(
                            'Select your location',
                            style: TextStyle(color: Colors.grey[500]),
                          ),
                          isExpanded: true,
                          icon: const Icon(Icons.keyboard_arrow_down_rounded),
                          onChanged: (value) =>
                              setState(() => _selectedLocation = value),
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
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _handleRegister,
                        child: Text(
                          _isLoading ? 'Creating...' : 'Create Account',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Already have an account? ',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            phoneNavigatorKey.currentState?.pushReplacement(
                              MaterialPageRoute(
                                builder: (context) => const LoginPage(),
                              ),
                            );
                          },
                          child: const Text(
                            'Login',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: _ecoTeal,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required String hintText,
    required IconData prefixIcon,
    TextEditingController? controller,
    TextInputType? keyboardType,
    String? errorText,
    ValueChanged<String>? onChanged,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[800],
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            inputFormatters: inputFormatters,
            onChanged: onChanged,
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: TextStyle(color: Colors.grey[400]),
              prefixIcon: Icon(prefixIcon, color: Colors.grey[500], size: 20),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey[200]!, width: 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _ecoTeal, width: 1.5),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.red[300]!, width: 1),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.red[400]!, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              errorText: errorText,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordRule({required String label, required bool passed}) {
    return Row(
      children: [
        Icon(
          passed ? Icons.check_circle : Icons.radio_button_unchecked,
          size: 14,
          color: passed ? _ecoTeal : Colors.grey[400],
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: passed ? Colors.grey[800] : Colors.grey[600],
            fontWeight: passed ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ],
    );
  }
}

