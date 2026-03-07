import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'providers/p2p_provider.dart';
import 'providers/profile_provider.dart';
import 'providers/sharing_provider.dart';
import 'screens/home_screen.dart';
import 'screens/dashboard_screen.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  // Load profile before running the app so it's available immediately
  final profileProvider = ProfileProvider();
  await profileProvider.loadProfile();

  runApp(P2PClassroomApp(profileProvider: profileProvider));
}

class P2PClassroomApp extends StatelessWidget {
  final ProfileProvider profileProvider;

  const P2PClassroomApp({super.key, required this.profileProvider});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: profileProvider),
        ChangeNotifierProvider(create: (_) => P2PProvider()),
        ChangeNotifierProvider(create: (_) => SharingProvider()),
      ],
      child: MaterialApp(
        title: 'TuroLink',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        locale: const Locale('en', 'US'),
        supportedLocales: const [
          Locale('en', 'US'),
        ],
        // If profile exists, go straight to Dashboard; otherwise HomeScreen
        home: profileProvider.hasProfile
            ? const DashboardScreen()
            : const HomeScreen(),
      ),
    );
  }
}
