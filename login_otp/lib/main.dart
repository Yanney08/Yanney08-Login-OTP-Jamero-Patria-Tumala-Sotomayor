import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Login OTP',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const LoginOtpScreen(),
    );
  }
}

class LoginOtpScreen extends StatefulWidget {
  const LoginOtpScreen({super.key});

  @override
  State<LoginOtpScreen> createState() => _LoginOtpScreenState();
}

class _LoginOtpScreenState extends State<LoginOtpScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _otpController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isLoading = false;
  bool _otpStage = false;
  String _statusMessage = '';

  static String get _baseUrl {
    if (kIsWeb) {
      return 'http://localhost:8000';
    }
    return 'http://192.168.1.7:8000';
  }

  Future<void> _sendOtp() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = '';
    });

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    try {
      debugPrint('Flutter web/mobile calling: $_baseUrl/request-otp');
      setState(() => _statusMessage = 'Requesting OTP from $_baseUrl/request-otp');

      final response = await http
          .post(
            Uri.parse('$_baseUrl/request-otp'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email, 'password': password}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        setState(() {
          _otpStage = true;
          _statusMessage = 'OTP sent to $email';
        });
      } else {
        final body = jsonDecode(response.body);
        setState(() {
          _statusMessage = 'Error: ${body['detail'] ?? response.body}';
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Network error: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _verifyOtp() async {
    if (_otpController.text.trim().isEmpty) {
      setState(() {
        _statusMessage = 'Please enter the OTP';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = '';
    });

    final email = _emailController.text.trim();
    final otp = _otpController.text.trim();

    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/verify-otp'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email, 'otp_code': otp}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        setState(() {
          _statusMessage = 'Login successful!';
        });
      } else {
        final body = jsonDecode(response.body);
        setState(() {
          _statusMessage = 'Error: ${body['detail'] ?? response.body}';
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Network error: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login with OTP')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Enter your email and password. OTP will be sent to your email.',
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.email),
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Please enter email';
                    if (!value.contains('@') || !value.contains('.')) return 'Enter valid email';
                    return null;
                  }
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.lock),
                    labelText: 'Password',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Please enter password';
                    if (value.length < 4) return 'Password must be at least 4 characters';
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                if (!_otpStage) ...[
                  ElevatedButton(
                    onPressed: _isLoading ? null : _sendOtp,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('Send OTP to my email', style: TextStyle(fontSize: 16)),
                  ),
                ],
                if (_otpStage) ...[
                  TextFormField(
                    controller: _otpController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.lock_outline),
                      labelText: 'OTP Code',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _verifyOtp,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('Verify OTP', style: TextStyle(fontSize: 16)),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _otpStage = false;
                        _otpController.clear();
                        _statusMessage = '';
                      });
                    },
                    child: const Text('Resend OTP / Back'),
                  ),
                ],
                const SizedBox(height: 20),
                if (_statusMessage.isNotEmpty)
                  Text(
                    _statusMessage,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _otpController.dispose();
    super.dispose();
  }
}
