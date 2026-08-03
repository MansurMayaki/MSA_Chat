import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'login_screen.dart';
import 'group_screen.dart';
import 'presence.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await ThemeController.instance.load();
  runApp(const MyApp());
}

/// Holds the app's light/dark preference and keeps it in sync with
/// SharedPreferences so it's remembered between app opens. [isDark] is a
/// ValueNotifier so widgets (the AppBar toggle, MaterialApp itself) can
/// listen and rebuild the moment it changes, without needing a full
/// state-management package for just this one setting.
class ThemeController {
  ThemeController._();
  static final ThemeController instance = ThemeController._();

  static const _prefsKey = 'dark_mode_enabled';

  final ValueNotifier<bool> isDark = ValueNotifier<bool>(false);

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      isDark.value = prefs.getBool(_prefsKey) ?? false;
    } catch (_) {
      // If prefs aren't available yet, just start in light mode.
    }
  }

  Future<void> toggle() async {
    isDark.value = !isDark.value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey, isDark.value);
    } catch (_) {
      // Not saving the preference isn't critical — worst case it resets
      // to light mode next launch.
    }
  }
}

// Shared theme colors used across the whole app, matched to the
// MUHAB SKILLS ACADEMY logo (teal-blue + lime green). These are getters
// rather than plain constants so every screen automatically follows
// whichever mode ThemeController.instance.isDark is currently set to —
// no need to thread a "isDark" flag through every widget.
class AppColors {
  static bool get _dark => ThemeController.instance.isDark.value;

  // Brand teal — kept the same in both modes so the app bar / buttons
  // still read as "MSA_Chat" regardless of theme.
  static Color get primary => const Color(0xFF2E6B7A);

  // Used everywhere as the main text/title color. On light backgrounds
  // that's a near-black navy; on dark backgrounds it needs to flip to a
  // light, high-contrast color instead.
  static Color get primaryDark =>
      _dark ? const Color(0xFFE9F2F2) : const Color(0xFF1F4B56);

  static Color get accent => const Color(0xFF8DC63F); // lime green from the logo

  static Color get background =>
      _dark ? const Color(0xFF121B1C) : const Color(0xFFF7FAFA);

  static Color get fieldFill =>
      _dark ? const Color(0xFF1D2A2B) : const Color(0xFFFFFFFF);

  static Color get fieldBorder =>
      _dark ? const Color(0xFF32403F) : const Color(0xFFD8E2E2);
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ThemeController.instance.isDark,
      builder: (context, isDark, _) {
        return MaterialApp(
          title: 'MSA_Chat',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            scaffoldBackgroundColor: AppColors.background,
            colorScheme: ColorScheme.fromSeed(
              seedColor: AppColors.primary,
              brightness: isDark ? Brightness.dark : Brightness.light,
            ),
            // Uses a font already installed on the device/browser instead of
            // Flutter's default "Roboto", which tries to download itself from
            // fonts.gstatic.com on web — and fails on restricted networks.
            fontFamily: 'Arial',
            useMaterial3: true,
          ),
          home: PresenceObserver(child: SplashScreen()),
        );
      },
    );
  }
}

/// Watches app lifecycle (foreground/background) and keeps the logged-in
/// user's online status in Firestore in sync with it, app-wide.
class PresenceObserver extends StatefulWidget {
  final Widget child;

  const PresenceObserver({super.key, required this.child});

  @override
  State<PresenceObserver> createState() => _PresenceObserverState();
}

class _PresenceObserverState extends State<PresenceObserver>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) setUserOnline(uid);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    if (state == AppLifecycleState.resumed) {
      setUserOnline(uid);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.inactive) {
      setUserOffline(uid);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fadeAnimation = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _controller.forward();
    _goToNextScreen();
  }

  Future<void> _goToNextScreen() async {
    await Future.delayed(const Duration(seconds: 3));
    if (!mounted) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
      return;
    }

    // Already logged in — go straight to their group
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const GroupRouter()),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset('assets/images/logo.png', width: 260),
              SizedBox(height: 16),
              Text(
                'MSA_Chat',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primaryDark,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
