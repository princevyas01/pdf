import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:syncfusion_flutter_core/core.dart';
import 'core/config/app_config.dart';
import 'core/services/external_pdf_intent_service.dart';
import 'core/theme/app_theme.dart';
import 'features/home/main_navigation_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Register Syncfusion License Key
  // ignore: deprecated_member_use
  SyncfusionLicense.registerLicense(AppConfig.syncfusionLicenseKey);

  runApp(
    const ProviderScope(
      child: OfflinePdfReaderApp(),
    ),
  );
}

class OfflinePdfReaderApp extends ConsumerStatefulWidget {
  const OfflinePdfReaderApp({super.key});

  @override
  ConsumerState<OfflinePdfReaderApp> createState() =>
      _OfflinePdfReaderAppState();
}

class _OfflinePdfReaderAppState extends ConsumerState<OfflinePdfReaderApp> {
  @override
  void initState() {
    super.initState();
    // Initialize external PDF intent listener once on app start
    ExternalPdfIntentService.initialize(ref);
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: AppConfig.appName,
      navigatorKey: appNavigatorKey,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      home: const MainNavigationScreen(),
    );
  }
}
