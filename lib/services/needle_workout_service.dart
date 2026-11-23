import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:isar/isar.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../models/fitness_schema.dart';
import '../utils/weight_reps_format.dart';
import 'database_service.dart';
import 'equipment_profile_service.dart';
import 'steel_guardrails.dart';
import 'widget_service.dart';

class NeedleDataAction {
  final String operation;
  final String recordType;
  final int? recordId;
  final Map<String, dynamic> record;
  final String summary;

  const NeedleDataAction({
    required this.operation,
    required this.recordType,
    required this.recordId,
    required this.record,
    required this.summary,
  });
}

class WorkoutLogDraft {
  final Exercise exercise;
  final List<SetLog> sets;

  const WorkoutLogDraft({required this.exercise, required this.sets});
}

class NeedleWorkoutService {
  static const _channel = MethodChannel('hybridlog/needle');
  static const _modelName = 'needle3.cact';
  static bool _initialized = false;

  static const splitMuscles = <String, List<String>>{
    'Push': ['chest', 'front_deltoids', 'side_deltoids', 'triceps'],
    'Pull': [
      'lats',
      'upper_back',
      'traps',
      'back_deltoids',
      'biceps',
      'lower_back',
      'forearm'
    ],
    'Legs': ['quads', 'hamstrings', 'glutes', 'calves', 'adductors'],
    'Upper': [
      'chest',
      'front_deltoids',
      'side_deltoids',
      'triceps',
      'lats',
      'upper_back',
      'traps',
      'back_deltoids',
      'biceps',
      'lower_back'
    ],
    'Lower': ['quads', 'hamstrings', 'glutes', 'calves', 'adductors'],
    'Fullbody': [],
    'Shoulders': ['front_deltoids', 'side_deltoids', 'back_deltoids'],
    'Arms': ['biceps', 'triceps', 'forearm'],
    'Shoulders and Arms': [
      'front_deltoids',
      'side_deltoids',
      'back_deltoids',
      'biceps',
      'triceps',
      'forearm'
    ],
    'Back': ['lats', 'upper_back', 'traps', 'back_deltoids', 'lower_back'],
    'Chest': ['chest'],
    'Chest and Back': [
      'chest',
      'lats',
      'upper_back',
      'traps',
      'back_deltoids',
      'lower_back'
    ],
    'Posterior': [
      'lats',
      'upper_back',
      'traps',
      'back_deltoids',
      'lower_back',
      'glutes',
      'hamstrings',
      'calves'
    ],
    'Anterior': [
      'chest',
      'abs',
      'obliques',
      'front_deltoids',
      'side_deltoids',
      'biceps',
      'quads'
    ],
  };

  static Future<bool> get isSupported async {
    try {
      return await _channel.invokeMethod<bool>('isSupported') == true;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<void> ensureReady(
      {required void Function(int received, int total) onProgress}) async {
    if (_initialized) return;
    if (!await isSupported) {
      throw UnsupportedError(
          'On-device Needle3 currently requires an ARM Android phone or tablet.');
    }

    final directory = await getApplicationSupportDirectory();
    final model = File('${directory.path}/$_modelName');
    final bundledModel = await rootBundle.load('assets/needle3.cact');
    final modelBytes = bundledModel.buffer.asUint8List(
      bundledModel.offsetInBytes,
      bundledModel.lengthInBytes,
    );
    if (modelBytes.length < 30 * 1024 * 1024) {
      throw const FormatException('The bundled Needle3 model is incomplete.');
    }
    if (!await model.exists() || await model.length() != modelBytes.length) {
      final temporary = File('${model.path}.tmp');
      await temporary.writeAsBytes(modelBytes, flush: true);
      if (await model.exists()) await model.delete();
      await temporary.rename(model.path);
    }
    onProgress(modelBytes.length, modelBytes.length);

    final result = await _channel
        .invokeMethod<String>('initialize', {'modelPath': model.path});
    if (result != 'ok')
      throw StateError(result ?? 'Could not initialize Needle3.');
    _initialized = true;
  }

  static Future<void> resetConversation() =>
      _channel.invokeMethod<void>('reset');

  static Future<String> completeLocally(String input, {String? tools}) async =>
      await _channel.invokeMethod<String>('complete', {
        'input': input,
        if (tools != null) 'tools': tools,
      }) ??
      '';

  static Future<WorkoutLogDraft> parseWorkoutLog(
    String userText,
    List<Exercise> exerciseLibrary,
  ) async {
    if (userText.trim().length > 500) {
      throw const FormatException(
          'Keep the workout description under 500 characters.');
    }
    final request = jsonEncode({
      'task':
          'Prepare a draft only; never save it. If the user gave one exercise and all its set weights and reps, call draft_workout_log with one exact exercise_library name, weight in pounds, and integer reps. Use weight 0 only for clearly stated bodyweight. If an exercise or a value is missing or unclear, call answer_user and ask one brief clarification. Do not call manage_data for a log draft.',
      'user_text': userText,
      'exercise_library':
          exerciseLibrary.map((exercise) => exercise.name).toList(),
      'output_shape': {
        'exercise_name': 'one exact name from exercise_library',
        'sets': [
          {'weight': 'number in pounds', 'reps': 'integer'}
        ],
      },
    });
    final raw = await completeLocally(request);
    final decoded = jsonDecode(raw);
    if (decoded is Map && decoded['function_calls'] is List) {
      final calls = decoded['function_calls'] as List;
      final answer = calls
          .whereType<Map>()
          .where((call) => call['name'] == 'answer_user')
          .firstOrNull;
      if (answer != null) {
        final arguments = answer['arguments'];
        final parsed = arguments is String ? jsonDecode(arguments) : arguments;
        final response = parsed is Map ? parsed['response'] : null;
        if (response is String && response.trim().isNotEmpty) {
          throw FormatException(response.trim());
        }
      }
    }
    return parseWorkoutLogResponse(raw, exerciseLibrary);
  }

  static WorkoutLogDraft parseWorkoutLogResponse(
    String raw,
    List<Exercise> exerciseLibrary,
  ) {
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start < 0 || end < start) {
      throw const FormatException('Steel could not read the workout details.');
    }
    final decoded = jsonDecode(raw.substring(start, end + 1));
    final data = decoded is Map ? _workoutLogData(decoded) : null;
    if (data == null ||
        data['exercise_name'] is! String ||
        data['sets'] is! List) {
      throw const FormatException(
          'Steel couldn’t prepare a draft. Tell it one exercise and the weight and reps for each set.');
    }
    final name = (data['exercise_name'] as String).trim();
    Exercise? exercise;
    for (final candidate in exerciseLibrary) {
      if (candidate.name.toLowerCase() == name.toLowerCase()) {
        exercise = candidate;
        break;
      }
    }
    if (exercise == null) {
      throw const FormatException(
          'That exercise is not in your exercise library yet.');
    }
    final rawSets = data['sets'] as List;
    if (rawSets.isEmpty || rawSets.length > 20) {
      throw const FormatException('A workout draft must contain 1 to 20 sets.');
    }
    final sets = <SetLog>[];
    for (final value in rawSets) {
      if (value is! Map) {
        throw const FormatException('Steel returned an invalid set.');
      }
      final weight = value['weight'];
      final reps = value['reps'];
      if (weight is! num ||
          !weight.isFinite ||
          weight < 0 ||
          weight > 2000 ||
          reps is! num ||
          reps != reps.roundToDouble() ||
          reps < 1 ||
          reps > 100) {
        throw const FormatException(
            'Check the weight and rep count in your request.');
      }
      sets.add(SetLog()
        ..weight = weight.toDouble()
        ..reps = reps.toInt());
    }
    return WorkoutLogDraft(exercise: exercise, sets: List.unmodifiable(sets));
  }

  static Map<String, dynamic>? _workoutLogData(Map decoded) {
    if (decoded['exercise_name'] is String && decoded['sets'] is List) {
      return Map<String, dynamic>.from(decoded);
    }
    final calls = decoded['function_calls'];
    if (calls is! List) return null;
    for (final call in calls) {
      if (call is Map && call['name'] == 'draft_workout_log') {
        final arguments = call['arguments'];
        final draft = arguments is String ? jsonDecode(arguments) : arguments;
        if (draft is Map &&
            draft['exercise_name'] is String &&
            draft['sets'] is List) {
          return Map<String, dynamic>.from(draft);
        }
      }
      if (call is! Map || call['name'] != 'manage_data') continue;
      final arguments = call['arguments'];
      final action = arguments is String ? jsonDecode(arguments) : arguments;
      if (action is! Map ||
          action['operation'] != 'create' ||
          action['record_type'] != 'workout' ||
          action['record'] is! Map) continue;
      final exercises = action['record']['exercises'];
      if (exercises is! List ||
          exercises.length != 1 ||
          exercises.single is! Map) {
        continue;
      }
      final exercise = exercises.single as Map;
      final sets = exercise['sets'];
      final name = exercise['name'] ??
          exercise['exercise_name'] ??
          exercise['exerciseName'];
      if (name is String && sets is List) {
        return {'exercise_name': name, 'sets': sets};
      }
    }
    return null;
  }

  static final _recordTerms = RegExp(
    r'\b(folders?|exercises?|work[ -]?outs?|runs?|ran|running|strength training|weight ?lifting|weight training|weights|lifting|muscle[ -]building)\b',
    caseSensitive: false,
  );

  static Iterable<String> dataRecordTypes(String request) =>
      _recordTerms.allMatches(request).map((match) {
        final term = match.group(0)!.toLowerCase();
        if (term.startsWith('folder')) return 'folder';
        if (term.startsWith('exercise')) return 'exercise';
        if (term.startsWith('run') || term == 'ran') return 'run';
        return 'workout';
      });

  static String? dataRecordType(String request) =>
      dataRecordTypes(request).firstOrNull;

  static bool isDataRead(String request) => RegExp(
        r"^(?:(?:please|can you|could you|would you)\s+)*(show|find|list|read|look up|pull up|what is in|what['’]s in|what (?:was|were) my|how (?:far|many miles) did i run)\b",
        caseSensitive: false,
      ).hasMatch(request);

  static Future<NeedleDataAction> proposeDataAction(
    String request, {
    void Function(int, int)? onProgress,
  }) async {
    final type = dataRecordType(request);
    if (type == null) {
      throw const FormatException(
          'Name the exercise, folder, workout, or run you want me to look at.');
    }
    final operation = SteelGuardrails.requestedMutation(request);
    final db = await DatabaseService().database;
    if (operation == null) {
      if (!isDataRead(request)) {
        throw const FormatException(
            'Ask me to show a record or describe one change you want to make.');
      }
      final rows = await _dataTargets(db, type);
      final datePhrase = RegExp(
        r'\b(today|yesterday|\d{4}-\d{2}-\d{2}|(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:tember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?) \d{1,2}(?:,? \d{4})?)\b',
        caseSensitive: false,
      ).firstMatch(request)?.group(0);
      final date = datePhrase == null ? null : _requestedDate(datePhrase);
      final named = rows
          .where((row) => row.name.isNotEmpty && _phraseIn(request, row.name));
      final latest =
          RegExp(r'\b(last|latest|most recent)\b', caseSensitive: false)
              .hasMatch(request);
      final listing = RegExp(
        r"\b(folders|exercises|work[ -]?outs|runs|library|running log|run log|workout log|strength training|weight ?lifting|weight training)\s*[?.!]*$",
        caseSensitive: false,
      ).hasMatch(request);
      var matches = named;
      if (type == 'run' || type == 'workout') {
        final exerciseNames = type == 'workout'
            ? (await db.exercises.where().findAll())
                .map((exercise) => exercise.name)
                .where((name) => _phraseIn(request, name))
                .toList()
            : <String>[];
        if (date != null || latest || listing || exerciseNames.isNotEmpty) {
          matches = rows.where((row) =>
              (date == null || _dateLabel(row.date!) == _dateLabel(date)) &&
              (exerciseNames.isEmpty ||
                  exerciseNames.any((name) => _phraseIn(row.label, name))));
          if (latest) matches = matches.take(1);
        }
      } else if (named.isEmpty && listing) {
        matches = rows;
      }
      final labels = matches.map((row) => row.label).take(8).join('\n');
      return NeedleDataAction(
        operation: 'read',
        recordType: type,
        recordId: null,
        record: const {},
        summary: labels.isEmpty
            ? 'I found no matching ${type}s in your logs or library.'
            : labels,
      );
    }
    if (!SteelGuardrails.allowsOperation(request, operation)) {
      throw const FormatException(
          'I can delete one item at a time. Please name one record.');
    }

    final renaming = operation == 'update' &&
        (type == 'folder' ||
            type == 'exercise' &&
                RegExp(r'\brename\b', caseSensitive: false).hasMatch(request));
    final (tool, schema) = _dataTool(operation, type, renaming: renaming);
    await ensureReady(onProgress: onProgress ?? (_, __) {});
    final raw = await completeLocally(request, tools: schema);
    final fields = _readDataFields(raw, tool, schema);
    if (fields == null) {
      throw FormatException(switch ((operation, type)) {
        ('create', 'exercise') =>
          'What is the new exercise name and its main muscle?',
        ('create', 'workout') =>
          'Give me an exercise name, the weight in pounds and reps per set, and the workout date.',
        ('create', 'run') => 'What date and how many whole miles should I log?',
        ('create', _) => 'What should I name the new folder?',
        ('update', 'folder') =>
          'Give me the current folder name and its new name.',
        _ =>
          'Which $type should I $operation? Give its exact name or date and any new values.',
      });
    }

    var target = fields.remove('target');
    final separator = RegExp(r'\s+to\s+', caseSensitive: false)
        .allMatches(request)
        .lastOrNull;
    if (renaming &&
        separator != null &&
        target is String &&
        fields['name'] is String) {
      final before = request.substring(0, separator.start);
      final after = request.substring(separator.end);
      final name = fields['name'] as String;
      if (!_phraseIn(before, target) || !_phraseIn(after, name)) {
        if (_phraseIn(before, name) && _phraseIn(after, target)) {
          fields['name'] = target;
          target = name;
        } else {
          throw const FormatException(
              'Give me the current name followed by the new name.');
        }
      }
    }
    int? id;
    if (operation != 'create') {
      final targets = await _dataTargets(db, type);
      final selector = target is String ? target.trim() : '';
      if (selector.isEmpty || !_phraseIn(request, selector)) {
        throw FormatException(
            'Which $type do you mean? Give its exact name or date.');
      }
      var matching = targets.where((row) {
        if (row.date == null)
          return row.name.toLowerCase() == selector.toLowerCase();
        final date = _requestedDate(selector.replaceFirst(
            RegExp(r'^(from|on|for)\s+', caseSensitive: false), ''));
        return date != null && _dateLabel(row.date!) == _dateLabel(date);
      }).toList();
      if (matching.isEmpty && (type == 'exercise' || type == 'folder')) {
        final name = selector
            .replaceFirst(RegExp(r'^(the|my)\s+', caseSensitive: false), '')
            .replaceFirst(RegExp('\\s+$type\$', caseSensitive: false), '');
        matching = targets
            .where((row) => row.name.toLowerCase() == name.toLowerCase())
            .toList();
      }
      if (matching.length != 1) {
        throw FormatException(
            'I need one matching $type. Check its exact name or date.');
      }
      id = matching.single.id;
    }
    if (fields['name'] case final String name when !_phraseIn(request, name)) {
      throw const FormatException('Please give the exact name to use.');
    }
    if (fields['date'] case final String phrase) {
      final date = _requestedDate(phrase);
      if (date == null || !_phraseIn(request, phrase)) {
        throw const FormatException(
            'Please give a date, such as yesterday or 2026-11-18.');
      }
      fields['date'] = _dateLabel(date);
    }
    if (fields['target_muscle'] case final String muscle) {
      if (!_phraseIn(request, muscle)) {
        throw const FormatException('Please name the primary muscle.');
      }
      fields['target_muscle'] = muscle.toLowerCase().replaceAll(' ', '_');
    }
    if (type == 'workout' && fields.containsKey('name')) {
      final name = _recordString(fields, 'name');
      final exercise = await db.exercises
          .filter()
          .nameEqualTo(name, caseSensitive: false)
          .findFirst();
      if (exercise == null) {
        throw const FormatException('Choose an exercise from your library.');
      }
      final weight = fields.remove('weight');
      final reps = fields.remove('reps');
      final draft = parseWorkoutLogResponse(
          jsonEncode({
            'exercise_name': exercise.name,
            'sets': [
              if (reps is List)
                for (final count in reps) {'weight': weight, 'reps': count},
            ],
          }),
          [exercise]);
      fields.remove('name');
      fields['exercises'] = [
        {
          'name': exercise.name,
          'target_muscle': exercise.targetMuscle,
          'target_muscles': exercise.targetMuscles,
          'secondary_muscles': exercise.secondaryMuscles,
          'sets': [
            for (final set in draft.sets)
              {'weight': set.weight, 'reps': set.reps},
          ],
        }
      ];
    }
    if (operation != 'delete' && fields.isEmpty) {
      throw const FormatException('Tell me what value you want to change.');
    }
    return _verifyDataAction(
        db,
        NeedleDataAction(
          operation: operation,
          recordType: type,
          recordId: id,
          record: Map.unmodifiable(fields),
          summary: '',
        ));
  }

  static (String, String) _dataTool(String operation, String type,
      {required bool renaming}) {
    final verb = switch ((operation, type)) {
      ('create', 'exercise') => 'add',
      ('create', 'run' || 'workout') => 'log',
      ('update', _) when renaming => 'rename',
      ('update', _) => 'edit',
      _ => operation,
    };
    final tool = '${verb}_$type';
    final dated = type == 'workout' || type == 'run';
    final props = <String, Map<String, Object>>{};
    final required = <String>[];
    void field(String key, String description,
        {String kind = 'string', bool needed = true}) {
      props[key] = {
        'type': kind,
        'description': description,
        if (kind == 'array') 'items': {'type': 'integer'},
      };
      if (needed) required.add(key);
    }

    if (operation != 'create') {
      field(
          'target',
          dated
              ? 'Copy the original date phrase verbatim'
              : 'Exact name of the existing $type');
    }
    if (operation != 'delete') {
      if (dated) {
        field('date',
            'Copy the ${operation == 'update' ? 'new ' : ''}date phrase verbatim',
            needed: operation == 'create');
      }
      if (!dated || type == 'workout' && operation == 'create') {
        field(
            'name',
            type == 'workout'
                ? 'Exercise name from the user'
                : 'Exact ${operation == 'update' ? 'new ' : ''}$type name',
            needed: renaming || operation == 'create');
      }
      if (type == 'exercise' && !renaming) {
        field('target_muscle', 'Primary muscle explicitly named by the user',
            needed: operation == 'create');
      }
      if (type == 'run') {
        field('miles', 'Logged mileage in whole miles',
            kind: 'integer', needed: operation == 'create');
      }
      if (type == 'workout' && operation == 'create') {
        field('weight',
            'Weight per set in pounds. Zero only for explicit bodyweight.',
            kind: 'number');
        field('reps', 'Reps for each set, repeating the count once per set',
            kind: 'array');
      }
    }
    final description = switch (tool) {
      'rename_folder' => 'Rename an existing favorites folder to a new name.',
      'create_folder' => 'Create or make a favorites folder with a name.',
      'add_exercise' => 'Create or add an exercise to the exercise library.',
      'rename_exercise' => 'Rename an existing exercise to a new name.',
      'edit_exercise' =>
        'Update or rename an exercise or change its primary muscle.',
      'log_run' => 'Record or add a run with its date and mileage.',
      'edit_run' =>
        'Update, correct or change the mileage or date of an existing run.',
      'log_workout' =>
        'Log one exercise performed at one weight, with the reps for each set.',
      'edit_workout' => 'Move an existing logged workout to a new date.',
      _ => 'Delete or remove one existing $type.',
    };
    return (
      tool,
      jsonEncode([
        {
          'type': 'function',
          'function': {
            'name': tool,
            'description': description,
            'parameters': {
              'type': 'object',
              'properties': props,
              'required': required
            },
          },
        }
      ])
    );
  }

  static Map<String, dynamic>? _readDataFields(
      String raw, String tool, String schema) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['success'] == false) return null;
      var calls = decoded['function_calls'];
      final validation = decoded['validation'];
      // A fully grounded low-confidence extraction may be reviewed. Neither
      // suppressed nor accepted calls can write anything on their own.
      if (calls is List &&
          calls.isEmpty &&
          validation is Map &&
          validation['negation'] == false &&
          validation['ungrounded'] is List &&
          (validation['ungrounded'] as List).isEmpty) {
        calls = decoded['suppressed_calls'];
      }
      if (calls is! List || calls.length != 1) return null;
      final call = calls.single;
      if (call is! Map || call['name'] != tool) return null;
      final args = call['arguments'];
      final fields = args is String ? jsonDecode(args) : args;
      final parameters = jsonDecode(schema)[0]['function']['parameters'] as Map;
      final properties = parameters['properties'] as Map;
      if (fields is! Map<String, dynamic> ||
          !fields.keys.every(properties.containsKey) ||
          !(parameters['required'] as List).every(fields.containsKey))
        return null;
      for (final entry in fields.entries) {
        final value = entry.value;
        final valid = switch (properties[entry.key]['type']) {
          'string' =>
            value is String && value.trim().isNotEmpty && value.length <= 300,
          'integer' => value is int,
          'number' => value is num && value.isFinite,
          'array' =>
            value is List && value.length <= 20 && value.every((v) => v is int),
          _ => false,
        };
        if (!valid) return null;
      }
      return Map.of(fields);
    } on FormatException {
      return null;
    }
  }

  static Future<List<({int id, String name, DateTime? date, String label})>>
      _dataTargets(
    Isar db,
    String type,
  ) async {
    switch (type) {
      case 'folder':
        final folders = await db.workoutFolders.where().sortByName().findAll();
        final exercises = await db.exercises.where().sortByName().findAll();
        return folders.map((folder) {
          final names = exercises
              .where((e) =>
                  e.folderNames.contains(folder.name) ||
                  e.folderName == folder.name)
              .map((e) => e.name)
              .join(', ');
          return (
            id: folder.id,
            name: folder.name,
            date: null,
            label: '${folder.name}: ${names.isEmpty ? 'empty' : names}'
          );
        }).toList();
      case 'exercise':
        return [
          for (final item in await db.exercises.where().sortByName().findAll())
            (
              id: item.id,
              name: item.name,
              date: null,
              label: '${item.name}: ${item.targetMuscle.replaceAll('_', ' ')}'
            ),
        ];
      case 'run':
        return [
          for (final item
              in await db.runningLogs.where().sortByDateDesc().findAll())
            (
              id: item.id,
              name: '',
              date: item.date,
              label: '${_dateLabel(item.date)}: ${item.miles} mi'
            ),
        ];
      default:
        return [
          for (final item
              in await db.dailyWorkouts.where().sortByDateDesc().findAll())
            (
              id: item.id,
              name: '',
              date: item.date,
              label: '${_dateLabel(item.date)}: ${_workoutDetails(item)}'
            ),
        ];
    }
  }

  static String _workoutDetails(DailyWorkout item) => item.exercises
      .map((ex) =>
          '${ex.exerciseName}: ${ex.sets.map((s) => formatWeightReps(s.weight, s.reps)).join(', ')}')
      .join(' | ');

  static bool _phraseIn(String text, String phrase) => RegExp(
        r'(?<![\p{L}\p{N}])' +
            RegExp.escape(phrase.trim()) +
            r'(?![\p{L}\p{N}])',
        caseSensitive: false,
        unicode: true,
      ).hasMatch(text);

  static DateTime? _requestedDate(String phrase) {
    final now = DateTime.now();
    final value = phrase.trim().toLowerCase().replaceAll(',', '');
    if (value == 'today' || value == 'yesterday') {
      return DateTime(
          now.year, now.month, now.day - (value == 'yesterday' ? 1 : 0));
    }
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      final parsed = DateTime.tryParse(value);
      return parsed != null && _dateLabel(parsed) == value ? parsed : null;
    }
    final capitalized =
        value.isEmpty ? '' : value[0].toUpperCase() + value.substring(1);
    final withYear = RegExp(r'\d{4}$').hasMatch(value)
        ? capitalized
        : '$capitalized ${now.year}';
    for (final format in ['MMMM d yyyy', 'MMM d yyyy']) {
      final date = DateFormat(format, 'en_US').tryParseStrict(withYear);
      if (date != null) return date;
    }
    return null;
  }

  static Future<void> applyApprovedDataAction(NeedleDataAction action) async {
    if (action.operation == 'read') {
      throw StateError('Read operations do not change stored data.');
    }
    final db = await DatabaseService().database;
    await db.writeTxn(() async {
      final current = await _verifyDataAction(db, action);
      if (current.summary != action.summary) {
        throw const FormatException(
            'That record changed. Ask Steel for a new preview.');
      }
      switch (action.recordType) {
        case 'exercise':
          if (action.operation == 'create') {
            final exercise = _exerciseFrom(action.record);
            if (await db.exercises
                    .filter()
                    .nameEqualTo(exercise.name, caseSensitive: false)
                    .findFirst() !=
                null) {
              throw StateError(
                  'An exercise named "${exercise.name}" already exists.');
            }
            await db.exercises.put(exercise);
            return;
          }
          final existing = await db.exercises.get(_requiredId(action));
          if (existing == null)
            throw StateError('The selected exercise no longer exists.');
          if (action.operation == 'delete') {
            await db.exercises.delete(existing.id);
          } else {
            final updated = _exerciseFrom(action.record, existing: existing);
            final duplicate = await db.exercises
                .filter()
                .nameEqualTo(updated.name, caseSensitive: false)
                .findFirst();
            if (duplicate != null && duplicate.id != existing.id) {
              throw StateError(
                  'An exercise named "${updated.name}" already exists.');
            }
            await db.exercises.put(updated);
          }
        case 'folder':
          if (action.operation == 'create') {
            final name = _recordString(action.record, 'name');
            if (await db.workoutFolders
                    .filter()
                    .nameEqualTo(name, caseSensitive: false)
                    .findFirst() !=
                null) {
              throw StateError('A folder named "$name" already exists.');
            }
            await db.workoutFolders.put(WorkoutFolder()..name = name);
            return;
          }
          final folder = await db.workoutFolders.get(_requiredId(action));
          if (folder == null)
            throw StateError('The selected folder no longer exists.');
          if (action.operation == 'delete') {
            await db.workoutFolders.delete(folder.id);
            final exercises = await db.exercises.where().findAll();
            for (final exercise in exercises) {
              if (!exercise.folderNames.contains(folder.name) &&
                  exercise.folderName != folder.name) continue;
              exercise.folderNames = List.of(exercise.folderNames)
                ..remove(folder.name);
              exercise.folderName = exercise.folderNames.firstOrNull;
              exercise.isFavorite = exercise.folderNames.isNotEmpty;
              await db.exercises.put(exercise);
            }
          } else {
            final name = _recordString(action.record, 'name');
            final duplicate = await db.workoutFolders
                .filter()
                .nameEqualTo(name, caseSensitive: false)
                .findFirst();
            if (duplicate != null && duplicate.id != folder.id) {
              throw StateError('A folder named "$name" already exists.');
            }
            final oldName = folder.name;
            folder.name = name;
            await db.workoutFolders.put(folder);
            if (oldName != name) {
              final exercises = await db.exercises.where().findAll();
              for (final exercise in exercises) {
                if (!exercise.folderNames.contains(oldName) &&
                    exercise.folderName != oldName) continue;
                final names = exercise.folderNames.isEmpty
                    ? [oldName]
                    : exercise.folderNames;
                exercise.folderNames =
                    names.map((item) => item == oldName ? name : item).toList();
                exercise.folderName = exercise.folderNames.firstOrNull;
                await db.exercises.put(exercise);
              }
            }
          }
        case 'workout':
          if (action.operation == 'create') {
            final draft = _workoutFrom(action.record);
            final days = await db.dailyWorkouts
                .filter()
                .dateBetween(
                  draft.date,
                  _nextDay(draft.date),
                  includeUpper: false,
                )
                .findAll();
            if (days.length > 1)
              throw const FormatException(
                  'This date has more than one workout. Choose one in workout history.');
            final existing = days.firstOrNull;
            if (existing != null) {
              existing.exercises = [...existing.exercises, ...draft.exercises];
            }
            await db.dailyWorkouts.put(existing ?? draft);
            return;
          }
          final workout = await db.dailyWorkouts.get(_requiredId(action));
          if (workout == null)
            throw StateError('The selected workout no longer exists.');
          if (action.operation == 'delete') {
            await db.dailyWorkouts.delete(workout.id);
          } else {
            final updated = _workoutFrom(action.record, existing: workout);
            if (updated.date != workout.date &&
                await db.dailyWorkouts
                    .filter()
                    .dateBetween(updated.date, _nextDay(updated.date),
                        includeUpper: false)
                    .isNotEmpty()) {
              throw const FormatException(
                  'There is already a workout on the new date.');
            }
            await db.dailyWorkouts.put(updated);
          }
        case 'run':
          if (action.operation == 'create') {
            final draft = _runFrom(action.record);
            if (await db.runningLogs
                .filter()
                .dateBetween(draft.date, _nextDay(draft.date),
                    includeUpper: false)
                .isNotEmpty()) {
              throw const FormatException(
                  'You already have a run on that date. Ask Steel to edit its mileage.');
            }
            await db.runningLogs.put(draft);
            return;
          }
          final run = await db.runningLogs.get(_requiredId(action));
          if (run == null)
            throw StateError('The selected run no longer exists.');
          if (action.operation == 'delete') {
            await db.runningLogs.delete(run.id);
          } else {
            final updated = _runFrom(action.record, existing: run);
            if (updated.date != run.date &&
                await db.runningLogs
                    .filter()
                    .dateBetween(updated.date, _nextDay(updated.date),
                        includeUpper: false)
                    .isNotEmpty()) {
              throw const FormatException(
                  'There is already a run on the new date.');
            }
            await db.runningLogs.put(updated);
          }
        default:
          throw StateError('Unsupported data type.');
      }
    });
    if (action.recordType == 'run') await WidgetService.updateRunningWidget();
  }

  static Future<NeedleDataAction> _verifyDataAction(
      Isar db, NeedleDataAction action) async {
    if (action.operation == 'read') return action;
    final id = action.recordId;
    final record = action.record;
    String summary;
    switch (action.recordType) {
      case 'exercise':
        final existing = id == null ? null : await db.exercises.get(id);
        if (action.operation != 'create' && existing == null) {
          throw const FormatException(
              'Needle selected an exercise that no longer exists.');
        }
        final proposed = action.operation == 'delete'
            ? existing!
            : _exerciseFrom(record, existing: existing);
        summary = switch (action.operation) {
          'create' =>
            'Create exercise "${proposed.name}" (${proposed.targetMuscle}).',
          'update' =>
            'Update exercise "${existing!.name}" to "${proposed.name}" (${proposed.targetMuscle}).',
          _ =>
            'Delete exercise "${existing!.name}" from the library. Workout history will remain.',
        };
      case 'folder':
        final existing = id == null ? null : await db.workoutFolders.get(id);
        if (action.operation != 'create' && existing == null) {
          throw const FormatException(
              'Needle selected a folder that no longer exists.');
        }
        final name = action.operation == 'delete'
            ? existing!.name
            : _recordString(record, 'name', fallback: existing?.name);
        summary = switch (action.operation) {
          'create' => 'Create favorites folder "$name".',
          'update' => 'Rename folder "${existing!.name}" to "$name".',
          _ =>
            'Delete folder "$name". Its exercises stay in the library; exercises with no other favorite folder will be unfavorited.',
        };
      case 'workout':
        final existing = id == null ? null : await db.dailyWorkouts.get(id);
        if (action.operation != 'create' && existing == null) {
          throw const FormatException(
              'Needle selected a workout that no longer exists.');
        }
        final proposed = action.operation == 'delete'
            ? existing!
            : _workoutFrom(record, existing: existing);
        final details = _workoutDetails(proposed);
        summary = switch (action.operation) {
          'create' => 'Log ${_dateLabel(proposed.date)}: $details.',
          'update' =>
            'Update workout from ${_dateLabel(existing!.date)} to ${_dateLabel(proposed.date)}: $details.',
          _ => 'Delete workout from ${_dateLabel(existing!.date)}: $details.',
        };
      case 'run':
        final existing = id == null ? null : await db.runningLogs.get(id);
        if (action.operation != 'create' && existing == null) {
          throw const FormatException(
              'Needle selected a run that no longer exists.');
        }
        final proposed = action.operation == 'delete'
            ? existing!
            : _runFrom(record, existing: existing);
        summary = switch (action.operation) {
          'create' =>
            'Create ${proposed.miles}-mile run for ${_dateLabel(proposed.date)}.',
          'update' =>
            'Update run from ${existing!.miles} to ${proposed.miles} miles on ${_dateLabel(proposed.date)}.',
          _ =>
            'Delete ${existing!.miles}-mile run from ${_dateLabel(existing.date)}.',
        };
      default:
        throw const FormatException(
            'Needle proposed an unsupported data type.');
    }
    return NeedleDataAction(
      operation: action.operation,
      recordType: action.recordType,
      recordId: action.recordId,
      record: action.record,
      summary: summary,
    );
  }

  static String _dateLabel(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  static DateTime _nextDay(DateTime date) =>
      DateTime(date.year, date.month, date.day + 1);

  static int _requiredId(NeedleDataAction action) =>
      action.recordId ?? (throw const FormatException('Missing record ID.'));

  static Exercise _exerciseFrom(Map<String, dynamic> record,
      {Exercise? existing}) {
    final exercise = Exercise()..id = existing?.id ?? Isar.autoIncrement;
    exercise.name = _recordString(record, 'name', fallback: existing?.name);
    exercise.targetMuscle = _recordString(record, 'target_muscle',
        fallback: existing?.targetMuscle);
    exercise.targetMuscles = _stringList(
        record['target_muscles'],
        record.containsKey('target_muscle')
            ? [exercise.targetMuscle]
            : existing?.targetMuscles ?? [exercise.targetMuscle]);
    exercise.secondaryMuscles = _stringList(
        record['secondary_muscles'], existing?.secondaryMuscles ?? const []);
    exercise.isFavorite = record['is_favorite'] is bool
        ? record['is_favorite'] as bool
        : existing?.isFavorite ?? false;
    exercise.folderNames =
        _stringList(record['folder_names'], existing?.folderNames ?? const []);
    exercise.folderName = exercise.folderNames.firstOrNull;
    return exercise;
  }

  static DailyWorkout _workoutFrom(Map<String, dynamic> record,
      {DailyWorkout? existing}) {
    final date = record['date'] == null && existing != null
        ? existing.date
        : _recordDate(record, 'date');
    final exercises = record['exercises'] == null && existing != null
        ? existing.exercises
        : _loggedExercises(record['exercises']);
    return (DailyWorkout()..id = existing?.id ?? Isar.autoIncrement)
      ..date = date
      ..exercises = exercises;
  }

  static RunningLog _runFrom(Map<String, dynamic> record,
          {RunningLog? existing}) =>
      (RunningLog()..id = existing?.id ?? Isar.autoIncrement)
        ..date = record['date'] == null && existing != null
            ? existing.date
            : _recordDate(record, 'date')
        ..miles = record['miles'] == null && existing != null
            ? existing.miles
            : _boundedInt(record['miles'], 'miles', 0, 1000000);

  static List<LoggedExercise> _loggedExercises(Object? value) {
    if (value is! List || value.length > 100)
      throw const FormatException('Workout exercises must be a list.');
    return value.map((item) {
      final data = _recordMap(item, 'workout exercise');
      final logged = LoggedExercise()
        ..exerciseName = _recordString(data, 'name')
        ..targetMuscle = data['target_muscle'] is String
            ? data['target_muscle'] as String
            : null
        ..targetMuscles = _stringList(data['target_muscles'], const [])
        ..secondaryMuscles = _stringList(data['secondary_muscles'], const []);
      final sets = data['sets'] ?? const [];
      if (sets is! List || sets.length > 100)
        throw const FormatException('Workout sets must be a list.');
      logged.sets = sets.map((item) {
        final set = _recordMap(item, 'set');
        final subsets = set['sub_sets'] ?? const [];
        if (subsets is! List || subsets.length > 100)
          throw const FormatException('Dropsets must be a list.');
        final rest = set['rest_pause_seconds'];
        if (rest != null &&
            _boundedInt(rest, 'rest_pause_seconds', 0, 60) != rest) {
          throw const FormatException('Invalid rest pause.');
        }
        return SetLog()
          ..reps = _boundedInt(set['reps'], 'reps', 0, 10000)
          ..weight = _boundedDouble(set['weight'], 'weight', 1000000)
          ..restPauseSeconds = rest == null
              ? null
              : _boundedInt(rest, 'rest_pause_seconds', 0, 60)
          ..subSets = subsets.map((subsetValue) {
            final subset = _recordMap(subsetValue, 'dropset');
            return SubSetLog()
              ..reps = _boundedInt(subset['reps'], 'reps', 0, 10000)
              ..weight = _boundedDouble(subset['weight'], 'weight', 1000000);
          }).toList();
      }).toList();
      return logged;
    }).toList();
  }

  static DateTime _recordDate(Map<String, dynamic> record, String key) {
    final value = record[key];
    if (value is String) {
      final date = DateTime.tryParse(value);
      if (date != null) return date;
    }
    throw FormatException('A valid $key is required.');
  }

  static String _recordString(Map<String, dynamic> record, String key,
      {String? fallback}) {
    final value = record[key] ?? fallback;
    if (value is String && value.trim().isNotEmpty && value.length <= 300)
      return value.trim();
    throw FormatException('A valid $key is required.');
  }

  static Map<String, dynamic> _recordMap(Object? value, String field) {
    if (value is Map && value.keys.every((key) => key is String))
      return Map<String, dynamic>.from(value);
    throw FormatException('$field must be an object.');
  }

  static List<String> _stringList(Object? value, List<String> fallback) {
    if (value == null) return List.of(fallback);
    if (value is! List ||
        value.length > 100 ||
        value.any((item) => item is! String || item.length > 100)) {
      throw const FormatException('Expected a list of short text values.');
    }
    return value.cast<String>();
  }

  static int _boundedInt(
      Object? value, String field, int minimum, int maximum) {
    if (value is num &&
        value.isFinite &&
        value == value.roundToDouble() &&
        value >= minimum &&
        value <= maximum) return value.toInt();
    throw FormatException('$field is outside the supported range.');
  }

  static double _boundedDouble(Object? value, String field, double maximum) {
    if (value is num && value.isFinite && value >= 0 && value <= maximum)
      return value.toDouble();
    throw FormatException('$field is outside the supported range.');
  }

  static Future<List<Exercise>> generate({
    required List<Exercise> exercises,
    required List<DailyWorkout> history,
    required List<String> splits,
    required bool includeNewExercises,
    required Map<String, double> fatigue,
    required Set<String> unavailable,
    Set<String> unavailableEquipment = const {},
    List<Exercise> currentPlan = const [],
  }) async {
    final used = <String, int>{};
    final recent = history.toList()..sort((a, b) => b.date.compareTo(a.date));
    for (final workout in recent.take(20)) {
      for (final logged in workout.exercises) {
        final name = logged.exerciseName;
        if (name != null) used[name] = (used[name] ?? 0) + 1;
      }
    }

    final eligible = exercises.where((exercise) {
      final familiar = exercise.isFavorite ||
          exercise.folderNames.isNotEmpty ||
          (used[exercise.name] ?? 0) > 0;
      if (!includeNewExercises && !familiar) return false;
      if (unavailable.contains(exercise.name)) return false;
      final equipment =
          EquipmentProfileService.categoriesForExercise(exercise.name);
      if (equipment.any(unavailableEquipment.contains)) return false;
      return _matchesSplit(exercise, splits);
    }).toList();
    if (eligible.isEmpty) return const [];

    eligible.sort(
        (a, b) => _rank(b, used, fatigue).compareTo(_rank(a, used, fatigue)));
    final candidates = eligible.take(50).toList();
    final historySummary = recent
        .take(8)
        .map((workout) => {
              'date':
                  '${workout.date.year}-${workout.date.month.toString().padLeft(2, '0')}-${workout.date.day.toString().padLeft(2, '0')}',
              'exercises': workout.exercises
                  .map((e) => e.exerciseName)
                  .whereType<String>()
                  .take(12)
                  .toList(),
            })
        .toList();
    final candidateSummary = candidates
        .map((e) => {
              'name': e.name,
              'muscles':
                  (e.targetMuscles.isEmpty ? [e.targetMuscle] : e.targetMuscles)
                      .take(3)
                      .toList(),
              'used_before': (used[e.name] ?? 0) > 0,
            })
        .toList();
    final request = jsonEncode({
      'previous_plan': currentPlan.map((exercise) => exercise.name).toList(),
      'request':
          'Plan a ${splits.join(' and ')} workout with 4 to 8 distinct exercises. Use recent history to avoid repeating too much and avoid heavily fatigued muscles when practical. ${includeNewExercises ? 'Include up to two suitable exercises marked used_before=false.' : 'Use only exercises marked used_before=true.'} ${unavailable.isEmpty ? '' : 'The user says they cannot use this equipment/exercise: ${unavailable.join(', ')}. Replace those with suitable alternatives.'} Return 6 exercises when possible.',
      'recent_workouts': historySummary,
      'muscle_fatigue': fatigue.entries
          .where((entry) => entry.value >= 0.2)
          .map((entry) => {'muscle': entry.key, 'level': entry.value})
          .toList(),
      'unavailable': [
        ...unavailable.toList(),
        ...unavailableEquipment.toList()
      ],
      'candidates': candidateSummary,
    });
    final raw =
        await _channel.invokeMethod<String>('complete', {'input': request});
    final chosenNames = _parseNames(raw ?? '');
    final byName = {
      for (final candidate in candidates) candidate.name: candidate
    };
    final selected = <Exercise>[];
    for (final name in chosenNames) {
      final exercise = byName[name];
      if (exercise != null &&
          !unavailable.contains(name) &&
          !selected.any((e) => e.name == name)) {
        selected.add(exercise);
      }
    }

    // The model can abstain when its small tool-calling model is uncertain.
    // Ponytail ceiling: ranked heuristics serve only as a local completion fallback; finer personalization can replace them later.
    if (selected.length < 4) {
      for (final exercise in candidates) {
        if (selected.length == 8) break;
        if (!unavailable.contains(exercise.name) &&
            !selected.any((e) => e.name == exercise.name))
          selected.add(exercise);
      }
    }
    return selected;
  }

  static bool _matchesSplit(Exercise exercise, List<String> splits) {
    if (splits.isEmpty || splits.contains('Fullbody')) return true;
    final muscles = splits
        .expand((split) => splitMuscles[split] ?? const <String>[])
        .toSet();
    final target = [
      ...exercise.targetMuscles,
      ...exercise.secondaryMuscles,
      exercise.targetMuscle
    ];
    return target.any((muscle) {
      final normalized = muscle.toLowerCase().replaceAll(' ', '_');
      return muscles.contains(normalized) ||
          muscles.contains(normalized.endsWith('s')
              ? normalized.substring(0, normalized.length - 1)
              : '${normalized}s');
    });
  }

  static double _rank(
      Exercise exercise, Map<String, int> used, Map<String, double> fatigue) {
    final targets = exercise.targetMuscles.isEmpty
        ? [exercise.targetMuscle]
        : exercise.targetMuscles;
    final strain = targets
        .map((muscle) => fatigue[muscle] ?? 0)
        .fold<double>(0, (a, b) => a > b ? a : b);
    final familiarity = (used[exercise.name] ?? 0) > 0
        ? 2.0
        : (exercise.isFavorite || exercise.folderNames.isNotEmpty ? 1.0 : 0.0);
    return familiarity - strain;
  }

  static List<String> _parseNames(String raw) {
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final calls = decoded['function_calls'] as List<dynamic>? ?? const [];
      for (final call in calls) {
        if (call is! Map || call['name'] != 'select_exercises') continue;
        final arguments = call['arguments'];
        final parsed = arguments is String ? jsonDecode(arguments) : arguments;
        if (parsed is Map && parsed['exercise_names'] is List) {
          return (parsed['exercise_names'] as List)
              .whereType<String>()
              .toList();
        }
      }
    } catch (_) {
      return const [];
    }
    return const [];
  }
}
