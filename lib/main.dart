import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'services/firebase_service.dart';
import 'services/hive_service.dart';
import 'services/sync_service.dart';
import 'core/theme/app_theme.dart';
import 'core/constants/app_constants.dart';
import 'core/routing/app_router.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Initialize services
  await FirebaseService.initialize();
  await HiveService.initialize();
  await SyncService.instance.initialize();

  runApp(const ProviderScope(child: CeoConsApp()));
}

class CeoConsApp extends ConsumerWidget {
  const CeoConsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: AppConstants.appName,
      theme: AppTheme.lightTheme,
      routerConfig: ref.watch(goRouterProvider),
      debugShowCheckedModeBanner: false,
    );
  }
}

// Temporary placeholder screens
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.white,
      body: Center(
        child: Card(
          margin: const EdgeInsets.all(24),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.construction, size: 64, color: AppTheme.deepBlue),
                const SizedBox(height: 24),
                Text(
                  'CEO Construction Monitoring',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                const TextField(
                  decoration: InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email),
                  ),
                ),
                const SizedBox(height: 16),
                const TextField(
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: Icon(Icons.lock),
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {},
                    child: const Text('Sign In'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Placeholder home screens for each role
class SiteManagerHome extends StatelessWidget {
  const SiteManagerHome({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text(
          'Site Manager',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: const Center(child: Text('Site Manager Home')),
    );
  }
}

class AdminHome extends StatelessWidget {
  const AdminHome({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text(
          'Admin',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: const Center(child: Text('Admin Home')),
    );
  }
}

class CeoHome extends StatelessWidget {
  const CeoHome({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text(
          'CEO Head',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: const Center(child: Text('CEO Head Home')),
    );
  }
}

