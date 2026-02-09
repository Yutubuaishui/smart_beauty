import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auth_service.dart';
import '../services/role_service.dart';
import '../debug_log.dart';
import 'welcome_page.dart';
import 'admin_dashboard_page.dart';
import 'user_dashboard_page.dart';

/// Decides which screen to show: Welcome, AdminDashboard, or UserDashboard.
/// After login, uses RoleService.getUserRole(uid) to navigate.
/// Uses a short timeout so we never stay on an invisible loading state.
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  static const _initialTimeout = Duration(seconds: 3);

  User? _user;
  bool _authResolved = false;
  StreamSubscription<User?>? _authSub;

  @override
  void initState() {
    super.initState();
    // #region agent log
    print('[RBAC] AuthWrapper initState');
    debugLog('auth_wrapper.dart', 'initState subscribe authStateChanges', {}, hypothesisId: 'H2');
    // #endregion
    // Defer ALL Firebase access to after first frame so we never throw [core/no-app] during build.
    WidgetsBinding.instance.addPostFrameCallback((_) => _initAuth());
  }

  void _initAuth() {
    if (!mounted) return;
    if (Firebase.apps.isEmpty) {
      // #region agent log
      print('[RBAC] Firebase.apps.isEmpty, showing welcome');
      debugLog('auth_wrapper.dart', 'Firebase.apps.isEmpty', {}, hypothesisId: 'H2');
      // #endregion
      setState(() => _authResolved = true);
      Firebase.initializeApp().catchError((_) {}).whenComplete(() {
        if (!mounted) return;
        if (Firebase.apps.isEmpty) return;
        try {
          final authService = AuthService();
          _authSub = authService.authStateChanges.listen((user) {
            if (mounted) setState(() {
              _user = user;
              _authResolved = true;
            });
          });
        } catch (_) {
          if (mounted) setState(() => _authResolved = true);
        }
      });
      return;
    }
    try {
      final authService = AuthService();
      _authSub = authService.authStateChanges.listen((user) {
        // #region agent log
        print('[RBAC] authStateChanges event uid=${user?.uid}');
        debugLog('auth_wrapper.dart', 'authStateChanges event', {'uid': user?.uid}, hypothesisId: 'H2');
        // #endregion
        if (mounted) {
          setState(() {
            _user = user;
            _authResolved = true;
          });
        }
      });
    } on FirebaseException catch (e) {
      if (e.code == 'no-app' && mounted) setState(() => _authResolved = true);
    } catch (_) {
      if (mounted) setState(() => _authResolved = true);
    }
    Future.delayed(_initialTimeout, () {
      if (!mounted) return;
      if (!_authResolved) {
        // #region agent log
        print('[RBAC] auth timeout, showing welcome');
        debugLog('auth_wrapper.dart', 'auth timeout, showing welcome', {}, hypothesisId: 'H2');
        // #endregion
        setState(() => _authResolved = true);
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // #region agent log
    print('[RBAC] AuthWrapper.build authResolved=$_authResolved uid=${_user?.uid}');
    debugLog('auth_wrapper.dart', 'AuthWrapper.build', {'authResolved': _authResolved, 'uid': _user?.uid}, hypothesisId: 'H2');
    // #endregion
    if (!_authResolved) {
      // Visible loading: colored background + text so something always shows.
      return const Scaffold(
        backgroundColor: Color(0xFFF0FFDF),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading...', style: TextStyle(fontSize: 16)),
            ],
          ),
        ),
      );
    }
    if (_user == null) {
      // #region agent log
      print('[RBAC] showing WelcomePage');
      debugLog('auth_wrapper.dart', 'return WelcomePage', {}, hypothesisId: 'H2');
      // #endregion
      return const WelcomePage();
    }
    // Do not build RoleService (Firestore) until default app exists (avoids [core/no-app] during build).
    if (Firebase.apps.isEmpty) {
      return const WelcomePage();
    }
    return FutureBuilder<String>(
      future: RoleService().getUserRole(_user!.uid),
      builder: (context, roleSnapshot) {
        if (roleSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFFF0FFDF),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading...', style: TextStyle(fontSize: 16)),
                ],
              ),
            ),
          );
        }
        final role = roleSnapshot.data ?? 'user';
        if (role == 'admin') {
          return const AdminDashboardPage();
        }
        return const UserDashboardPage();
      },
    );
  }
}
