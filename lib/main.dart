import 'package:flutter/material.dart';
import 'pages/main_navigation.dart';

void main() {
  runApp(const SmartBeautyApp());
}

class SmartBeautyApp extends StatelessWidget {
  const SmartBeautyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SmartBeauty AI',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.pink,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const MainNavigation(),
      debugShowCheckedModeBanner: false,
    );
  }
}
