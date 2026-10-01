import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:offline_pdf_reader/core/ai/ai_model_manager.dart';
import 'package:offline_pdf_reader/core/ai/local_model_downloader.dart';
import 'package:offline_pdf_reader/core/pet/dragon_pet_controller.dart';
import 'package:offline_pdf_reader/widgets/dragon_pet_widget.dart';
import 'package:offline_pdf_reader/widgets/dragon_pet_menu.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('DragonPetController Tests', () {
    test('initializes in idle state and transitions states', () {
      final controller = DragonPetController();
      expect(controller.state, DragonPetState.idle);

      controller.setState(DragonPetState.reading);
      expect(controller.state, DragonPetState.reading);

      controller.setState(DragonPetState.thinking);
      expect(controller.state, DragonPetState.thinking);

      controller.dispose();
    });

    test('pause and resume manages state correctly', () {
      final controller = DragonPetController();
      controller.setState(DragonPetState.sleeping);
      expect(controller.state, DragonPetState.sleeping);

      controller.pause();
      controller.setState(DragonPetState.excited);
      // Ignored because controller is paused
      expect(controller.state, DragonPetState.sleeping);

      controller.resume();
      // Resume resets sleeping or tired to idle
      expect(controller.state, DragonPetState.idle);

      controller.dispose();
    });

    test('returnToPreviousAfter restores previous state after timer', () async {
      final controller = DragonPetController();
      controller.setContextState(DragonPetState.reading);
      expect(controller.state, DragonPetState.reading);

      controller.setState(DragonPetState.curious, returnToPreviousAfter: const Duration(milliseconds: 50));
      expect(controller.state, DragonPetState.curious);

      await Future.delayed(const Duration(milliseconds: 70));
      expect(controller.state, DragonPetState.reading);

      controller.dispose();
    });

    test('markInteraction wakes dragon from tired/sleeping', () {
      final controller = DragonPetController();
      controller.setState(DragonPetState.tired);
      expect(controller.state, DragonPetState.tired);

      controller.markInteraction();
      expect(controller.state, DragonPetState.idle);

      controller.setState(DragonPetState.sleeping);
      expect(controller.state, DragonPetState.sleeping);

      controller.markInteraction();
      expect(controller.state, DragonPetState.idle);

      controller.dispose();
    });
  });

  group('DragonPetWidget Tests', () {
    testWidgets('renders companion and triggers onTap callback', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DragonPetWidget(
              size: 56,
              state: DragonPetState.idle,
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      // Verify Semantics
      expect(find.bySemanticsLabel('Study companion'), findsOneWidget);

      // Tap widget
      await tester.tap(find.byType(DragonPetWidget));
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets('respects enabled=false', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DragonPetWidget(
              size: 56,
              enabled: false,
            ),
          ),
        ),
      );

      expect(find.bySemanticsLabel('Study companion'), findsNothing);
    });
  });

  group('DragonPetMenu Tests', () {
    testWidgets('renders all 5 companion actions and triggers callbacks', (tester) async {
      bool askedDoc = false;
      bool explained = false;
      bool studied = false;
      bool summarized = false;
      bool aiModels = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DragonPetMenu(
              hasSelection: true,
              onAskDocument: () => askedDoc = true,
              onExplainSelection: () => explained = true,
              onStudyMode: () => studied = true,
              onSummarizePage: () => summarized = true,
              onAiModels: () => aiModels = true,
            ),
          ),
        ),
      );

      expect(find.text('Study Companion'), findsOneWidget);
      expect(find.text('Ask Document'), findsOneWidget);
      expect(find.text('Explain Selection'), findsOneWidget);
      expect(find.text('Study Mode'), findsOneWidget);
      expect(find.text('Summarize Page'), findsOneWidget);
      expect(find.text('Local AI Models'), findsOneWidget);

      await tester.tap(find.text('Ask Document'));
      expect(askedDoc, isTrue);

      await tester.tap(find.text('Explain Selection'));
      expect(explained, isTrue);

      await tester.tap(find.text('Study Mode'));
      expect(studied, isTrue);

      await tester.tap(find.text('Summarize Page'));
      expect(summarized, isTrue);

      await tester.tap(find.text('Local AI Models'));
      expect(aiModels, isTrue);
    });
  });

  group('Local AI Models & Manager Tests', () {
    test('LocalModelDownloader models registry contains expected GGUFs', () {
      expect(LocalModelDownloader.models.length, greaterThanOrEqualTo(2));
      final qwen4 = LocalModelDownloader.models.firstWhere((m) => m.id == 'qwen3-4b-q4km');
      expect(qwen4.fileName, 'Qwen3-4B-Q4_K_M.gguf');
      expect(qwen4.expectedSizeBytes, 2497280640);
      expect(qwen4.displaySize, '~2.50 GB');
      expect(qwen4.sha256, 'ab27b9bfa375a178d6cba48f3ad892b94b7739659dcc7aae8058ce0ffed6b328');

      final qwen0_6 = LocalModelDownloader.models.firstWhere((m) => m.id == 'qwen3-0.6b-q40');
      expect(qwen0_6.fileName, 'Qwen3-0.6B-Q4_0.gguf');
      expect(qwen0_6.displaySize, '~429 MB');
      expect(qwen0_6.sha256, 'da2572f16c06133561ce56accaa822216f2391ef4d37fba427801cd6736417d4');
    });

    test('AiModelManager updates settings and toggles enabled', () async {
      final manager = AiModelManager.instance;
      await manager.initialize();
      expect(manager.initialized, isTrue);

      expect(manager.config.maxContextLength, 2048);
      await manager.updateSettings(maxContext: 1024);
      expect(manager.config.maxContextLength, 1024);

      await manager.toggleEnabled(false);
      expect(manager.config.isEnabled, isFalse);
      await manager.toggleEnabled(true);
      expect(manager.config.isEnabled, isTrue);
    });
  });
}
