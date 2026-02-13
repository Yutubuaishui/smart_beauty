import 'package:flutter/material.dart';
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

class LogoWidget extends StatelessWidget {
  final String assetPath;
  final double? height;
  final double? width;

  const LogoWidget({
    super.key,
    required this.assetPath,
    this.height,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    // #region agent log
    _debugLog('logo_widget.dart:37', 'LogoWidget.build() entry', {'assetPath': assetPath}, hypothesisId: 'D');
    // #endregion
    
    // #region agent log
    _debugLog('logo_widget.dart:41', 'Loading asset', {'assetPath': assetPath}, hypothesisId: 'D');
    // #endregion
    
    return Image.asset(
      assetPath,
      height: height ?? 120,
      width: width,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) {
        // #region agent log
        _debugLog('logo_widget.dart:48', 'Asset loading error', {'assetPath': assetPath, 'error': error.toString()}, hypothesisId: 'D');
        // #endregion
        return Icon(
          Icons.image_not_supported,
          size: height ?? 120,
          color: Colors.grey,
        );
      },
    );
  }
}
