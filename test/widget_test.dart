import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:offline_pdf_reader/main.dart' show OfflinePdfReaderApp;
import 'package:offline_pdf_reader/features/home/main_navigation_screen.dart';
import 'package:offline_pdf_reader/widgets/editorial_components.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    databaseFactory = databaseFactorySqflitePlugin;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.tekartik.sqflite'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'getDatabasesPath') {
          return '.';
        }
        if (methodCall.method == 'openDatabase') {
          return 1;
        }
        if (methodCall.method == 'query') {
          return <Map<String, dynamic>>[];
        }
        if (methodCall.method == 'insert' || methodCall.method == 'update' || methodCall.method == 'delete') {
          return 1;
        }
        return null;
      },
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => '.',
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.offlinepdf.app/intent'),
      (MethodCall methodCall) async => null,
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/permissions/methods'),
      (MethodCall methodCall) async => 1,
    );
  });

  testWidgets('App smoke test - Renders MainNavigationScreen', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const ProviderScope(child: OfflinePdfReaderApp()));

    // Verify that the MainNavigationScreen is rendered
    expect(find.byType(MainNavigationScreen), findsOneWidget);

    // Verify bottom navigation bar exists with at least one item
    expect(find.byType(EditorialBottomBar), findsOneWidget);
    
    // Verify that the 'Files' tab exists
    expect(find.text('Files'), findsWidgets);
  });
}
