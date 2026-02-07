import 'package:flutter/material.dart';
import 'pages/welcome_page.dart';
import 'package:firebase_core/firebase_core.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:async';

// #region agent log
void _debugLog(String location, String message, Map<String, dynamic> data, {String? hypothesisId}) {
  try {
    final logDir = Directory(r'c:\Users\Asus\smart_beauty\.cursor');
    if (!logDir.existsSync()) {
      logDir.createSync(recursive: true);
    }
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
    print('[LOG] Written to file: $message');
  } catch (e) {
    print('[LOG ERROR] Failed to write log: $e');
  }
}
// #endregion

void main() async {
  // #region agent log
  print('[DEBUG] main() entry');
  _debugLog('main.dart:27', 'main() entry', {}, hypothesisId: 'A');
  // #endregion
  
  try {
    // #region agent log
    print('[DEBUG] Calling WidgetsFlutterBinding.ensureInitialized()');
    _debugLog('main.dart:32', 'WidgetsFlutterBinding.ensureInitialized() called', {}, hypothesisId: 'A');
    // #endregion
    WidgetsFlutterBinding.ensureInitialized();
    
    // #region agent log
    print('[DEBUG] Attempting Firebase initialization with timeout...');
    _debugLog('main.dart:37', 'Firebase.initializeApp() called', {}, hypothesisId: 'A');
    // #endregion
    
    // Try Firebase initialization with timeout
    try {
      await Firebase.initializeApp().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          print('[DEBUG] Firebase initialization timed out after 5 seconds');
          throw TimeoutException('Firebase initialization timeout');
        },
      );
      // #region agent log
      print('[DEBUG] Firebase.initializeApp() completed successfully');
      _debugLog('main.dart:50', 'Firebase initialized successfully', {}, hypothesisId: 'A');
      // #endregion
    } catch (firebaseError) {
      // #region agent log
      print('[DEBUG] Firebase initialization failed or timed out: $firebaseError');
      _debugLog('main.dart:55', 'Firebase initialization error', {'error': firebaseError.toString()}, hypothesisId: 'A');
      // #endregion
      // Continue anyway - Firebase might not be critical for UI
      print('[DEBUG] Continuing without Firebase...');
    }
    
    // #region agent log
    print('[DEBUG] Calling runApp()');
    _debugLog('main.dart:62', 'runApp() called', {}, hypothesisId: 'A');
    // #endregion
    runApp(const SmartBeautyApp());
  } catch (e, stackTrace) {
    // #region agent log
    print('[DEBUG] ERROR in main(): $e');
    print('[DEBUG] StackTrace: $stackTrace');
    _debugLog('main.dart:49', 'Error in main()', {'error': e.toString(), 'stackTrace': stackTrace.toString()}, hypothesisId: 'A');
    // #endregion
    rethrow;
  }
}

class SmartBeautyApp extends StatelessWidget {
  const SmartBeautyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // #region agent log
    print('[DEBUG] SmartBeautyApp.build() called');
    _debugLog('main.dart:60', 'SmartBeautyApp.build() entry', {}, hypothesisId: 'B');
    // #endregion
    
    try {
      // #region agent log
      print('[DEBUG] Creating MaterialApp with WelcomePage');
      _debugLog('main.dart:65', 'Creating MaterialApp with WelcomePage', {}, hypothesisId: 'B');
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
        home: const WelcomePage(),
        debugShowCheckedModeBanner: false,
      );
    } catch (e, stackTrace) {
      // #region agent log
      _debugLog('main.dart:52', 'Error in SmartBeautyApp.build()', {'error': e.toString(), 'stackTrace': stackTrace.toString()}, hypothesisId: 'B');
      // #endregion
      rethrow;
    }
  }
}
