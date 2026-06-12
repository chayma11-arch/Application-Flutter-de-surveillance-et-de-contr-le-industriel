import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;

  bool get isWeb => kIsWeb;
  bool get isMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // 🔥 LOGIN
  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final error = await AuthService.login(
      _emailController.text.trim(),
      _passwordController.text,
    );

    if (!mounted) return;

    setState(() => _isLoading = false);

    if (error == null) {
      Navigator.pushReplacementNamed(context, '/home');
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  // 🔥 GOOGLE SIGN IN
  Future<void> _googleSignIn() async {
    setState(() => _isLoading = true);

    final error = await AuthService.googleSignIn();

    if (!mounted) return;

    setState(() => _isLoading = false);

    if (error != null) {
      final message = error == 'cancelled' ? 'Google sign-in cancelled' : error;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      return;
    }

    Navigator.pushReplacementNamed(context, '/home');
  }

  @override
  Widget build(BuildContext context) {
    final isSmallScreen = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: isSmallScreen ? 24 : 48),
          child: Container(
            constraints: BoxConstraints(maxWidth: isWeb ? 450 : 400),
            child: Card(
              color: const Color(0xFFF5F9FF),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: EdgeInsets.all(isSmallScreen ? 24 : 32),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      const Text(
                        "Welcome Back",
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E88E5),
                        ),
                      ),

                      const SizedBox(height: 30),

                      // 📧 EMAIL
                      TextFormField(
                        controller: _emailController,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.email),
                        ),
                        validator: (value) => value == null || value.isEmpty
                            ? 'Enter email'
                            : null,
                      ),

                      const SizedBox(height: 15),

                      // 🔒 PASSWORD
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                          ),
                        ),
                        validator: (value) => value == null || value.length < 6
                            ? 'Min 6 chars'
                            : null,
                      ),

                      const SizedBox(height: 10),

                      // 🔥 FORGOT PASSWORD
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () {
                            Navigator.pushNamed(context, '/forgot');
                          },
                          child: const Text("Forgot password?"),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // 🔵 LOGIN BUTTON
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _login,
                          child: _isLoading
                              ? const CircularProgressIndicator(
                                  color: Colors.white,
                                )
                              : const Text("Sign in"),
                        ),
                      ),

                      const SizedBox(height: 15),

                      const Divider(),

                      const SizedBox(height: 15),

                      // 🔵 GOOGLE
                      OutlinedButton.icon(
                        onPressed: _googleSignIn,
                        icon: const Icon(Icons.g_mobiledata, color: Colors.red),
                        label: const Text("Continue with Google"),
                      ),

                      const SizedBox(height: 20),

                      // 🔵 SIGNUP
                      TextButton(
                        onPressed: () {
                          Navigator.pushNamed(context, '/signup');
                        },
                        child: const Text("Create account"),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
