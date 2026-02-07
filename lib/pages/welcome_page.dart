import 'package:flutter/material.dart';
import '../widgets/logo_widget.dart';
import '../widgets/custom_button.dart';
import 'login_page.dart';
import 'signup_page.dart';
import 'dart:io';
import 'dart:convert';

// #region agent log
void _debugLog(String location, String message, Map<String, dynamic> data, {String? hypothesisId}) {
  try {
    final logFile = File(r'c:\Users\Asus\smart_beauty\.cursor\debug.log');
    final logEntry = <String, dynamic>{
      'id': 'log_${DateTime.now().millisecondsSinceEpoch}',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'location': location,
      'message': message,
      'data': data,
      if (hypothesisId != null) 'hypothesisId': hypothesisId,
      'runId': 'run1',
    };
    logFile.writeAsStringSync('${jsonEncode(logEntry)}\n', mode: FileMode.append);
  } catch (e) {
    // Silently fail if logging fails
  }
}
// #endregion

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    // #region agent log
    print('[DEBUG] WelcomePage.build() called');
    _debugLog('welcome_page.dart:32', 'WelcomePage.build() entry', {}, hypothesisId: 'C');
    // #endregion
    
    try {
      final theme = Theme.of(context);
      
      // #region agent log
      print('[DEBUG] Theme obtained, building Scaffold');
      _debugLog('welcome_page.dart:38', 'Theme obtained, building Scaffold', {}, hypothesisId: 'C');
      // #endregion

    // #region agent log
    print('[DEBUG] Building Scaffold with green background');
    // #endregion
    
    return Scaffold(
      backgroundColor: const Color(0xFFF0FFDF), // Pale Green
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // #region agent log
            print('[DEBUG] LayoutBuilder constraints: ${constraints.maxWidth}x${constraints.maxHeight}');
            // #endregion
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight,
                ),
                child: IntrinsicHeight(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 60),
                        // Logo
                        // #region agent log
                        Builder(
                          builder: (context) {
                            print('[DEBUG] Building LogoWidget');
                            return const LogoWidget(
                              assetPath: 'assets/frontlogo_green.png',
                              height: 150,
                            );
                          },
                        ),
                        // #endregion
                        const SizedBox(height: 40),
                        // Header
                        Text(
                          'Welcome to SmartBeauty',
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurface,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        // Sub-headline
                        Text(
                          'Your AI-powered beauty companion',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const Spacer(),
                        // Split buttons
                        Row(
                          children: [
                            Expanded(
                              child: CustomButton(
                                text: 'Login',
                                backgroundColor: const Color(0xFF1A237E), // Dark Navy
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => const LoginPage(),
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: CustomButton(
                                text: 'SignUp',
                                backgroundColor: const Color(0xFFC8E6C9), // Light Green
                                textColor: const Color(0xFF1B5E20), // Dark Green Text
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => const SignUpPage(),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    } catch (e, stackTrace) {
      // #region agent log
      _debugLog('welcome_page.dart:88', 'Error in WelcomePage.build()', {'error': e.toString(), 'stackTrace': stackTrace.toString()}, hypothesisId: 'C');
      // #endregion
      return Scaffold(
        body: Center(
          child: Text('Error: $e'),
        ),
      );
    }
  }
}
