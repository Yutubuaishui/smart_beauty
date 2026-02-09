import 'package:flutter/material.dart';
import '../widgets/logo_widget.dart';
import '../widgets/custom_button.dart';
import '../debug_log.dart';
import 'login_page.dart';
import 'signup_page.dart';

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    // #region agent log
    print('[RBAC] WelcomePage.build');
    debugLog('welcome_page.dart', 'WelcomePage.build', {}, hypothesisId: 'H3');
    // #endregion
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF0FFDF), // Pale Green
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 60),
              const LogoWidget(
                assetPath: 'assets/frontlogo_green.png',
                height: 150,
              ),
              const SizedBox(height: 40),
              Text(
                'Welcome to SmartBeauty',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Your AI-powered beauty companion',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const Spacer(),
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
    );
  }
}
