import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:offline_pdf_reader/main.dart' show OfflinePdfReaderApp;
import 'package:offline_pdf_reader/features/home/main_navigation_screen.dart';
import 'package:offline_pdf_reader/features/home/files_tab.dart';
import 'package:offline_pdf_reader/features/favorites/favorites_tab.dart';
import 'package:offline_pdf_reader/features/search/search_tab.dart';
import 'package:offline_pdf_reader/features/tools/tools_tab.dart';
import 'package:offline_pdf_reader/features/stats/stats_tab.dart';
import 'package:offline_pdf_reader/features/settings/settings_screen.dart';
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
        if (methodCall.method == 'getDatabasesPath') return '.';
        if (methodCall.method == 'openDatabase') return 1;
        if (methodCall.method == 'query') return <Map<String, dynamic>>[];
        if (methodCall.method == 'insert' ||
            methodCall.method == 'update' ||
            methodCall.method == 'delete') {
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

  group('Release Candidate Smoke Test Suite', () {
    testWidgets('1. FILES Tab loads and displays Quiet Editorial Header & Shell',
        (WidgetTester tester) async {
      await tester.pumpWidget(const ProviderScope(child: OfflinePdfReaderApp()));
      await tester.pumpAndSettle();

      expect(find.byType(MainNavigationScreen), findsOneWidget);
      expect(find.byType(FilesTab), findsOneWidget);
      expect(find.text('LOCAL STORAGE'), findsOneWidget);
      expect(find.text('Files'), findsWidgets);
      expect(find.text('All PDFs'), findsOneWidget);
      expect(find.text('Recent'), findsOneWidget);
      expect(find.text('Starred'), findsOneWidget);
    });

    testWidgets('2. Navigation to FAVORITES tab renders Editorial Curated Documents',
        (WidgetTester tester) async {
      await tester.pumpWidget(const ProviderScope(child: OfflinePdfReaderApp()));
      await tester.pumpAndSettle();

      // Tap on Favorites in navigation bar
      await tester.tap(find.text('Favorites'));
      await tester.pumpAndSettle();

      expect(find.byType(FavoritesTab), findsOneWidget);
      expect(find.textContaining('CURATED DOCUMENTS'), findsOneWidget);
      expect(find.text('Favorites'), findsWidgets);
    });

    testWidgets('3. Navigation to SEARCH tab renders Search and OCR controls',
        (WidgetTester tester) async {
      await tester.pumpWidget(const ProviderScope(child: OfflinePdfReaderApp()));
      await tester.pumpAndSettle();

      // Tap on Search in navigation bar
      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();

      expect(find.byType(SearchTab), findsOneWidget);
      expect(find.textContaining('DOCUMENT SEARCH'), findsOneWidget);
      expect(find.text('Search inside extracted OCR text'), findsOneWidget);
    });

    testWidgets('4. Navigation to TOOLS tab renders 3 Numbered Functional Suites',
        (WidgetTester tester) async {
      await tester.pumpWidget(const ProviderScope(child: OfflinePdfReaderApp()));
      await tester.pumpAndSettle();

      // Tap on Tools in navigation bar
      await tester.tap(find.text('Tools'));
      await tester.pumpAndSettle();

      expect(find.byType(ToolsTab), findsOneWidget);
      expect(find.text('Document Utilities'), findsOneWidget);
      expect(find.text('Document Transformation'), findsOneWidget);
      expect(find.text('Conversion & Capture'), findsOneWidget);
    });

    testWidgets('5. Navigation to STATS tab renders Telemetry and Breakdown',
        (WidgetTester tester) async {
      await tester.pumpWidget(const ProviderScope(child: OfflinePdfReaderApp()));
      await tester.pumpAndSettle();

      // Tap on Stats in navigation bar
      await tester.tap(find.text('Stats'));
      await tester.pumpAndSettle();

      expect(find.byType(StatsTab), findsOneWidget);
      expect(find.textContaining('READING ACTIVITY'), findsOneWidget);
      expect(find.text('Reading & Activity'), findsOneWidget);
      expect(find.text('Storage Distribution'), findsOneWidget);
      expect(find.text('Tool Operations'), findsOneWidget);
      expect(find.text('Frequent Documents'), findsOneWidget);
    });

    testWidgets('6. Settings Screen opens and displays Quiet Editorial Preferences',
        (WidgetTester tester) async {
      await tester.pumpWidget(const ProviderScope(child: OfflinePdfReaderApp()));
      await tester.pumpAndSettle();

      // Open settings via 'P' avatar on Library screen
      final settingsAvatar = find.text('P');
      expect(settingsAvatar, findsOneWidget);
      await tester.tap(settingsAvatar);
      await tester.pumpAndSettle();

      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.textContaining('STUDIO PREFERENCES'), findsOneWidget);
      expect(find.text('Settings & Storage'), findsOneWidget);
      expect(find.text('Appearance & Reading Bed'), findsOneWidget);
      expect(find.text('Application Theme'), findsOneWidget);
      expect(find.text('Persistence & Cache Control'), findsOneWidget);
    });

    testWidgets('7. Editorial Components Render Correctly', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                const EditorialSectionHeader(label: 'Test Section', trailing: 'Context'),
                EditorialFilterChip(
                  label: 'FILTER',
                  selected: true,
                  onTap: () {},
                ),
                const PhysicalPaperThumbnail(
                  pageNumber: 3,
                  totalPages: 10,
                  isCompleted: false,
                  progressPercent: 0.3,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Test Section'), findsOneWidget);
      expect(find.text('Context'), findsOneWidget);
      expect(find.text('FILTER'), findsOneWidget);
      expect(find.text('p.3'), findsOneWidget);
    });
  });
}
