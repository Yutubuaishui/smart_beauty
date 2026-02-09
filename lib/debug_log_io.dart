import 'dart:io';
import 'dart:convert';

/// Append one NDJSON line to the session log file.
void debugLog(String location, String message, Map<String, dynamic> data, {String? hypothesisId}) {
  // #region agent log
  try {
    const logPath = r'c:\Users\Asus\smart_beauty\.cursor\debug.log';
    final logFile = File(logPath);
    logFile.parent.createSync(recursive: true);
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
  } catch (_) {}
  // #endregion
}
