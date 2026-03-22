import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:firebase_auth/firebase_auth.dart' as fb_auth_lib;

import 'firebase_options.dart';

import 'pages/auth/login_screen.dart';
import 'pages/auth/signup_screen.dart';
import 'pages/auth/verify_otp_screen.dart';
import 'pages/auth/forgot_password_screen.dart';
import 'pages/auth/change_password_screen.dart';

import 'pages/profile_screen.dart';
import 'pages/edit_profile_screen.dart';
import 'pages/main_screen.dart';
import 'pages/admin_screen.dart';
import 'pages/report_found_screen.dart';
import 'pages/report_lost_screen.dart';
import 'pages/my_posts_screen.dart';
import 'pages/settings_screen.dart';

import 'services/api_service.dart';

import 'providers/auth_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(
    MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => AuthProvider())],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Django Firebase Auth',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        primaryColor: Colors.blueAccent,
        fontFamily: 'Inter',
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.blueAccent,
          foregroundColor: Colors.white,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 23,
            fontWeight: FontWeight.bold,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blueAccent,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(vertical: 16),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.blueAccent),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.blueAccent, width: 2),
          ),
          contentPadding: const EdgeInsets.all(16),
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: Colors.grey[800],
          contentTextStyle: const TextStyle(color: Colors.white),
        ),
      ),
      home: const AuthGate(),
      onGenerateRoute: (settings) {
        if (settings.name == '/verify-otp') {
          final args = settings.arguments as Map<String, dynamic>?;
          return MaterialPageRoute(
            builder:
                (context) => VerifyOTPScreen(
                  email: args?['email'] ?? '',
                  password: args?['password'],
                  username: args?['username'],
                  firebaseUid: args?['firebaseUid'] ?? '',
                  isEmailChange: args?['isEmailChange'] ?? false,
                  newEmail: args?['newEmail'],
                ),
          );
        }

        final routes = <String, WidgetBuilder>{
          '/login': (context) => const LoginScreen(),
          '/signup': (context) => const SignUpScreen(),
          '/forgot-password': (context) => const ForgotPasswordScreen(),
          '/change-password': (context) => const ChangePasswordScreen(),
          '/home': (context) => const MainScreen(),
          '/admin': (context) => const AdminScreen(),
          '/profile': (context) => const ProfileScreen(),
          '/edit-profile': (context) => const EditProfileScreen(),
          '/report-found': (context) => const ReportFoundScreen(),
          '/report-lost': (context) => const ReportLostScreen(),
          '/my-posts': (context) => const MyPostsScreen(),
          '/settings': (context) => const SettingsScreen(),
        };

        final builder = routes[settings.name];
        if (builder != null) {
          return MaterialPageRoute(builder: builder);
        }

        return null;
      },
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  Future<String>? _roleFuture;
  String? _lastUid;

  Future<String> _checkUserRole(String uid) async {
    await ApiService().fetchUserProfile();
    return await ApiService().getUserRole();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<fb_auth_lib.User?>(
      stream: fb_auth_lib.FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snapshot.data;
        if (user != null) {
          if (user.uid != _lastUid) {
            _lastUid = user.uid;
            _roleFuture = _checkUserRole(user.uid);
          }

          return FutureBuilder<String>(
            future: _roleFuture,
            builder: (context, roleSnapshot) {
              if (roleSnapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }

              final role = roleSnapshot.data ?? 'user';
              if (role == 'admin') {
                return const AdminScreen();
              } else {
                return MainScreen(key: MainScreen.navigatorKey);
              }
            },
          );
        } else {
          _lastUid = null;
          _roleFuture = null;
          return const LoginScreen();
        }
      },
    );
  }
}
