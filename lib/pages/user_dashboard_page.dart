import 'package:flutter/material.dart';
import 'main_navigation.dart';
import '../services/auth_service.dart';

/// User dashboard: main app with bottom nav. Profile can call AuthService.logout().
class UserDashboardPage extends StatelessWidget {
  const UserDashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const MainNavigation();
  }
}
