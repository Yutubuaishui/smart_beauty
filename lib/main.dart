import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'pages/auth_wrapper.dart';
import 'debug_log.dart';
import 'firebase_options.dart';

/// Initialize Firebase first (with timeout so we don't hang), then runApp so no widget sees [core/no-app].
void main() async {
  // #region agent log
  debugLog('main.dart', 'main entry', {}, hypothesisId: 'H1');
  // #endregion
  WidgetsFlutterBinding.ensureInitialized();
  try {
    // #region agent log
    debugLog('main.dart', 'before Firebase.initializeApp', {}, hypothesisId: 'H1');
    // #endregion
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform, // <--- Add this!
    ).timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw TimeoutException('Firebase init timeout'),
    );
    // #region agent log
    debugLog('main.dart', 'after Firebase.initializeApp', {}, hypothesisId: 'H1');
    // #endregion
  } catch (e, st) {
    // #region agent log
    debugLog('main.dart', 'Firebase.initializeApp error', {'error': e.toString(), 'stack': st.toString()}, hypothesisId: 'H1');
    // #endregion
    // Continue so UI still shows; AuthWrapper will see Firebase.apps.isEmpty and show welcome
  }
  // #region agent log
  debugLog('main.dart', 'calling runApp', {}, hypothesisId: 'H1');
  // #endregion
  runApp(const SmartBeautyApp());
}

/// Minimal first screen: no Firebase, no auth. If this paints, the issue is in AuthWrapper.
class _BootScreen extends StatefulWidget {
  const _BootScreen();

  @override
  State<_BootScreen> createState() => _BootScreenState();
}

class _BootScreenState extends State<_BootScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const AuthWrapper()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0FFDF),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'SmartBeauty',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20)),
            ),
            const SizedBox(height: 16),
            const CircularProgressIndicator(color: Color(0xFF1B5E20)),
            const SizedBox(height: 8),
            const Text('Loading...', style: TextStyle(fontSize: 16, color: Color(0xFF1B5E20))),
          ],
        ),
      ),
    );
  }
}

class SmartBeautyApp extends StatelessWidget {
  const SmartBeautyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // #region agent log
    debugLog('main.dart', 'SmartBeautyApp.build', {}, hypothesisId: 'H4');
    // #endregion
    return MaterialApp(
      title: 'SmartBeauty AI',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.pink,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const _BootScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
