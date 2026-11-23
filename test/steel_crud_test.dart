import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';
import 'package:workout_app/models/fitness_schema.dart';
import 'package:workout_app/services/needle_workout_service.dart';
import 'package:workout_app/services/steel_chat_service.dart';
import 'package:workout_app/widgets/steel_chat_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final cli = Platform.environment['HYBRIDLOG_NEEDLE_QA'];
  late Directory scratch;
  late Isar db;
  var completions = 0;
  var lastModelOutput = '';
  var abstainOnHistory = false;
  final responses = {
    'create_folder': {'name': 'Push Day'},
    'rename_folder': {'target': 'Push Day', 'name': 'Monday Push'},
    'delete_folder': {'target': 'Monday Push'},
    'log_run': {'date': 'yesterday', 'miles': 3},
    'edit_run': {'target': 'yesterday', 'miles': 4},
    'delete_run': {'target': 'yesterday'},
    'add_exercise': {'name': 'Cable Fly', 'target_muscle': 'chest'},
    'rename_exercise': {'target': 'Cable Fly', 'name': 'Standing Cable Fly'},
    'delete_exercise': {'target': 'Standing Cable Fly'},
    'log_workout': {
      'date': 'yesterday',
      'name': 'Cable Fly',
      'weight': 25,
      'reps': [10, 8]
    },
    'edit_workout': {'target': 'yesterday', 'date': 'today'},
    'delete_workout': {'target': 'today'},
  };

  setUpAll(() async {
    scratch = await Directory.systemTemp.createTemp('steel_crud_');
    final config = File('.dart_tool/package_config.json').absolute;
    final packages = jsonDecode(config.readAsStringSync())['packages'] as List;
    final entry =
        packages.singleWhere((entry) => entry['name'] == 'isar_flutter_libs');
    final package = config.uri.resolve(entry['rootUri'] as String).toString();
    final root = Uri.parse(package.endsWith('/') ? package : '$package/');
    final library = Platform.isWindows
        ? 'windows/isar.dll'
        : Platform.isMacOS
            ? 'macos/Classes/libisar.dylib'
            : 'linux/libisar.so';
    await Isar.initializeIsarCore(
      libraries: {Abi.current(): root.resolve(library).toFilePath()},
    );
    db = await Isar.open(
      [
        ExerciseSchema,
        WorkoutFolderSchema,
        DailyWorkoutSchema,
        RunningLogSchema
      ],
      directory: scratch.path,
      inspector: false,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => scratch.path,
    );
    final bridge =
        File('android/app/src/main/cpp/needle_bridge.cpp').readAsStringSync();
    final system =
        RegExp(r'extractionSystem = "([^"]+)"').firstMatch(bridge)!.group(1)!;
    final promptFile = File('${scratch.path}/system.txt')
      ..writeAsStringSync(system);
    final toolsFile = File('${scratch.path}/tools.json');
    messenger.setMockMethodCallHandler(const MethodChannel('hybridlog/needle'),
        (call) async {
      switch (call.method) {
        case 'isSupported':
          return true;
        case 'initialize':
          return 'ok';
        case 'reset':
          return null;
        case 'complete':
          completions++;
          final schema = call.arguments['tools'] as String;
          final tool = (jsonDecode(schema) as List).single['function']['name'];
          if (tool == 'search_training_history' &&
              (abstainOnHistory || cli == null)) {
            return '{"success":true,"function_calls":[],"suppressed_calls":[]}';
          }
          if (cli != null) {
            await toolsFile.writeAsString(schema);
            final result = await Process.run(cli, [
              '--model',
              'assets/needle3.cact',
              '--tools',
              toolsFile.path,
              '--system',
              promptFile.path,
              '--max',
              '384',
              '--prompt',
              call.arguments['input'] as String,
            ], environment: {
              'DO_NOT_TRACK': '1',
              'NEEDLE_TELEMETRY': '0'
            });
            expect(result.exitCode, 0, reason: result.stderr.toString());
            return lastModelOutput = result.stdout.toString();
          }
          return jsonEncode({
            'function_calls': [
              {'name': tool, 'arguments': responses[tool]}
            ],
          });
        default:
          fail('Unexpected Needle method ${call.method}');
      }
    });
  });

  tearDownAll(() async {
    await db.close();
    await scratch.delete(recursive: true);
  });

  test('Steel chat creates, reads, edits and deletes dated logs and exercises',
      () async {
    Future<void> apply(String prompt, String operation) async {
      final reply =
          await SteelChatService.ask(prompt).catchError((Object error) {
        fail('$prompt: $error\n$lastModelOutput');
      });
      expect(reply.action?.operation, operation, reason: reply.text);
      await NeedleWorkoutService.applyApprovedDataAction(reply.action!);
    }

    await apply('Add Cable Fly to my exercise library for chest.', 'create');
    expect((await SteelChatService.ask('Show the Cable Fly exercise.')).text,
        'Cable Fly: chest');
    await apply('Log a 3 mile run yesterday.', 'create');
    expect((await SteelChatService.ask('How far did I run yesterday?')).text,
        contains('3 mi'));
    await apply('Change my run from yesterday to 4 miles.', 'update');
    expect((await db.runningLogs.where().findFirst())!.miles, 4);

    await apply('Log a workout yesterday: Cable Fly, 25 pounds, 10 and 8 reps.',
        'create');
    final run =
        await SteelChatService.ask('How many miles did I run yesterday?');
    expect(run.text, allOf(contains('4 mi'), isNot(contains('Cable Fly'))));
    final workout =
        await SteelChatService.ask('What was my workout yesterday?');
    expect(
        workout.text,
        allOf(contains('25 lbs x 10 reps, 25 lbs x 8 reps'),
            isNot(contains('4 mi'))));
    final strength =
        await SteelChatService.ask('Show yesterday’s weight training.');
    expect(strength.text, workout.text);
    await apply('Move my workout from yesterday to today.', 'update');
    expect((await SteelChatService.ask('Show today’s workout.')).text,
        contains('Cable Fly'));
    await apply('Delete my workout from today.', 'delete');
    expect(await db.dailyWorkouts.count(), 0);
    expect((await db.runningLogs.where().findFirst())!.miles, 4);
    await apply('Delete my run from yesterday.', 'delete');
    expect(await db.runningLogs.count(), 0);

    await apply(
        'Rename the Cable Fly exercise to Standing Cable Fly.', 'update');
    expect(
        (await db.exercises.where().findFirst())!.name, 'Standing Cable Fly');
    await apply('Delete the Standing Cable Fly exercise.', 'delete');
    expect(await db.exercises.count(), 0);

    final before = completions;
    await expectLater(
        SteelChatService.ask('Delete all folders.'), throwsFormatException);
    expect(completions, before);
  });

  test('chat answers with exact log data even when Needle abstains', () async {
    final today = DateTime.now();
    final recent = DateTime(today.year, today.month, today.day);
    final earlier = DateTime(today.year, today.month, today.day - 3);
    DailyWorkout bench(DateTime date, double weight) => DailyWorkout()
      ..date = date
      ..exercises = [
        LoggedExercise()
          ..exerciseName = 'Barbell Bench Press'
          ..sets = [
            SetLog()
              ..weight = weight
              ..reps = 8
          ],
        LoggedExercise()
          ..exerciseName = 'Cable Row'
          ..sets = [
            SetLog()
              ..weight = 60
              ..reps = 10
          ],
      ];
    await db.writeTxn(() async {
      await db.dailyWorkouts.putAll([bench(recent, 135), bench(earlier, 125)]);
    });
    const question = 'What did I bench last time?';
    final before = completions;
    final reply = await SteelChatService.ask(question);
    expect(completions, greaterThan(before),
        reason: 'The model path should run.');
    expect(
        reply.text,
        allOf(contains('Barbell Bench Press'), contains('135 lbs x 8 reps'),
            isNot(contains('Cable Row')), isNot(contains('125 lbs'))));
    expect(reply.sources, hasLength(1));
    expect(reply.action, isNull);

    abstainOnHistory = true;
    try {
      final followUp = await SteelChatService.ask(
        'What about the time before that?',
        sessionHistory: [
          {'role': 'user', 'content': question},
          {'role': 'assistant', 'content': reply.text},
        ],
      );
      expect(followUp.text,
          allOf(contains('125 lbs'), isNot(contains('135 lbs'))));
      final setCount = await SteelChatService.ask(
        'How many sets was that?',
        sessionHistory: [
          {'role': 'user', 'content': question},
          {'role': 'assistant', 'content': reply.text},
        ],
      );
      expect(setCount.text, contains('1 set and 8 reps'));
      final heaviest =
          await SteelChatService.ask('What’s my heaviest bench press?');
      expect(heaviest.text, contains('135 lbs x 8 reps'));
      final count = await SteelChatService.ask('How many workouts did I log?');
      expect(count.text, contains('2 workouts'));
      final noMatch =
          await SteelChatService.ask('What was my workout on 2000-01-01?');
      expect(
          noMatch.text, contains('don’t see a logged workout on 2000-01-01'));
      expect(noMatch.sources, isEmpty);
    } finally {
      abstainOnHistory = false;
      await db.writeTxn(() => db.dailyWorkouts.clear());
    }
  });

  testWidgets(
      'chat previews writes and deletion requires a second, checked approval',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SteelChatDialog(onDataChanged: () {})),
    ));

    Future<void> until(Finder finder) async {
      for (var i = 0; i < 150 && finder.evaluate().isEmpty; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(finder, findsOneWidget, reason: lastModelOutput);
      await tester.pumpAndSettle();
      await tester.ensureVisible(finder);
    }

    Future<void> send(String message, Finder reply) async {
      await tester.enterText(find.byType(TextField), message);
      await tester.pump();
      await tester.runAsync(() => tester.tap(find.byTooltip('Send')));
      await until(reply);
    }

    final approve = find.text('Approve change');
    await send('Please make a favorites folder called Push Day.', approve);
    expect(db.workoutFolders.countSync(), 0);
    await tester.runAsync(() => tester.tap(approve));
    await until(find.text('Done. I added it to your local app data.'));
    expect(db.workoutFolders.where().findFirstSync()!.name, 'Push Day');

    final beforeRead = completions;
    await send('Show my Push Day folder.', find.text('Push Day: empty'));
    expect(completions, beforeRead);
    await send('Rename my Push Day folder to Monday Push.', approve);
    expect(db.workoutFolders.where().findFirstSync()!.name, 'Push Day');
    await tester.runAsync(() => tester.tap(approve));
    await until(find.text('Done. I saved that change on this device.'));
    expect(db.workoutFolders.where().findFirstSync()!.name, 'Monday Push');

    final review = find.text('Review deletion');
    await send('Delete the Monday Push folder.', review);
    await tester.tap(review);
    await tester.pump(const Duration(milliseconds: 250));
    final delete = find.widgetWithText(FilledButton, 'Delete');
    expect(tester.widget<FilledButton>(delete).onPressed, isNull);
    final cancel = find.byTooltip('Cancel deletion');
    expect(
        tester
            .widget<Icon>(
                find.descendant(of: cancel, matching: find.byIcon(Icons.close)))
            .color,
        Colors.red);
    await tester.tap(cancel);
    await tester.pumpAndSettle();
    expect(db.workoutFolders.countSync(), 1);

    await tester.tap(review);
    await tester.pump(const Duration(milliseconds: 250));
    expect(tester.widget<FilledButton>(delete).onPressed, isNull);
    await tester.tap(find.text('I want to delete this item'));
    await tester.pump();
    expect(db.workoutFolders.countSync(), 1);
    await tester.runAsync(() => tester.tap(delete));
    await until(find.text('Done. I deleted the selected item.'));
    expect(db.workoutFolders.countSync(), 0);
  });
}
