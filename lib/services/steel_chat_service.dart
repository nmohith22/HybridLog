import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:isar/isar.dart';

import '../models/fitness_schema.dart';
import '../utils/weight_reps_format.dart';
import 'database_service.dart';
import 'equipment_profile_service.dart';
import 'needle_workout_service.dart';
import 'progression_service.dart';
import 'steel_guardrails.dart';

class SteelLocalDocument {
  final String kind;
  final String label;
  final String searchableText;
  final DateTime? date;
  final Map<String, dynamic> evidence;

  const SteelLocalDocument({
    required this.kind,
    required this.label,
    required this.searchableText,
    required this.evidence,
    this.date,
  });
}

class SteelChatReply {
  final String text;
  final List<String> sources;
  final WorkoutLogDraft? draft;
  final NeedleDataAction? action;
  final List<Exercise> selectedExercises;

  const SteelChatReply({
    required this.text,
    this.sources = const [],
    this.draft,
    this.action,
    this.selectedExercises = const [],
  });
}

class SteelChatService {
  static const _historyTool = 'search_training_history';
  static const _historyTools = '''
[
  {"type":"function","function":{
    "name":"search_training_history",
    "description":"Look up or compare old workout sessions, exercises, logged sets and weights, or running mileage from personal training history.",
    "parameters":{"type":"object","properties":{
      "view":{"type":"string","enum":["latest","heaviest","count","list","compare","weekly"],
              "description":"Return the latest session, heaviest weight, count sessions, list dates and sets, compare two sessions, or give a weekly recap."}
    },"required":["view"]}
  }}
]
''';

  static const _stopWords = {
    'a',
    'about',
    'and',
    'are',
    'did',
    'do',
    'for',
    'from',
    'have',
    'how',
    'i',
    'in',
    'is',
    'it',
    'last',
    'me',
    'my',
    'of',
    'on',
    'please',
    'the',
    'this',
    'to',
    'what',
    'when',
    'where',
    'which',
    'with',
  };

  static const _recentWords = {
    'latest',
    'last',
    'previous',
    'recent',
    'week',
    'weekly',
    'history',
    'training',
    'progress',
  };

  static List<SteelLocalDocument> rankDocuments(
    String question,
    List<SteelLocalDocument> documents, {
    int limit = 8,
  }) {
    final terms = _terms(question);
    final query = _normalize(question);
    final activities = NeedleWorkoutService.dataRecordTypes(question)
        .where((type) => type == 'run' || type == 'workout')
        .toSet();
    final wantsRecent = _words(question).any(_recentWords.contains);
    final thisWeek =
        RegExp(r'\b(this week|current week)\b', caseSensitive: false)
            .hasMatch(question);
    final today = DateTime.now();
    final weekStart = DateTime(today.year, today.month, today.day)
        .subtract(Duration(days: today.weekday - DateTime.monday));
    final ranked = <({SteelLocalDocument document, double score})>[];

    for (final document in documents) {
      final isActivity = document.kind == 'workout' || document.kind == 'run';
      if (isActivity &&
          activities.isNotEmpty &&
          !activities.contains(document.kind)) {
        continue;
      }
      if (thisWeek &&
          isActivity &&
          (document.date == null || document.date!.isBefore(weekStart))) {
        continue;
      }
      final searchable = _normalize(document.searchableText);
      final documentTerms = _terms(document.searchableText);
      var score = 0.0;
      for (final term in terms) {
        if (documentTerms.contains(term)) score += 1;
      }
      if (query.length >= 4 && searchable.contains(query)) score += 3;
      if (isActivity && (wantsRecent || activities.contains(document.kind))) {
        score += 0.5;
      }
      if (score > 0) ranked.add((document: document, score: score));
    }

    ranked.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return (b.document.date ?? DateTime(0))
          .compareTo(a.document.date ?? DateTime(0));
    });
    return ranked.take(limit).map((entry) => entry.document).toList();
  }

  static Future<SteelChatReply> ask(
    String question, {
    List<Map<String, String>> sessionHistory = const [],
    void Function(int, int)? onProgress,
  }) async {
    final request = question.trim();
    if (request.isEmpty) {
      throw const FormatException('Type a message for Steel first.');
    }
    if (request.length > 1200) {
      throw const FormatException('Keep each message under 1,200 characters.');
    }

    final type = NeedleWorkoutService.dataRecordType(request);
    if (type != null &&
        (SteelGuardrails.requestedMutation(request) != null ||
            (type == 'folder' || type == 'exercise') &&
                NeedleWorkoutService.isDataRead(request))) {
      final action = await NeedleWorkoutService.proposeDataAction(
        request,
        onProgress: onProgress,
      );
      return action.operation == 'read'
          ? SteelChatReply(text: action.summary)
          : SteelChatReply(
              text: 'Review this change before applying it.',
              action: action,
            );
    }

    final words = _normalize(request);
    final askingForDraftOrPlan = RegExp(
          r'^(?:please |(?:can|could|would) you |(?:help me|i want to|id like to) )*(?:plan|build|make|suggest|recommend|log|record|draft)\b',
        ).hasMatch(words) ||
        words == 'help me turn a workout into a draft';
    if (!askingForDraftOrPlan) {
      return _answerHistory(request, sessionHistory, onProgress);
    }

    await NeedleWorkoutService.ensureReady(
        onProgress: onProgress ?? (_, __) {});
    final db = await DatabaseService().database;
    final exercises = await db.exercises.where().sortByName().findAll();
    final documents = await _loadDocuments(db, exercises);
    final sources = rankDocuments(request, documents);
    final unavailable = await EquipmentProfileService.loadUnavailable();
    final exerciseCandidates = rankDocuments(
      request,
      documents.where((document) => document.kind == 'exercise').toList(),
      limit: 20,
    ).map((document) => document.evidence['name']).whereType<String>().toList();
    final retrieved = sources.take(8).toList();

    final input = jsonEncode({
      'user_message': request,
      'recent_conversation': sessionHistory,
      'retrieved_local_records':
          retrieved.map((source) => source.evidence).toList(),
      'record_sources': retrieved.map((source) => source.label).toList(),
      'exercise_candidates': exerciseCandidates,
      'saved_unavailable_equipment': unavailable.toList(),
      'today': _date(DateTime.now()),
    });
    await NeedleWorkoutService.resetConversation();
    final raw = await NeedleWorkoutService.completeLocally(input);
    final decoded = _decode(raw);
    final calls = decoded['function_calls'];
    if (calls is! List || calls.isEmpty) {
      return SteelChatReply(
        text: words.contains('draft') || words.startsWith('log')
            ? 'Tell me the exercise and the weight and reps for each set. For example, bench press at 135 lbs for 8 and 6 reps.'
            : 'Choose Build a workout to plan a session around your equipment and the muscles you want to train.',
      );
    }

    final call = calls.first;
    if (call is! Map || call['name'] is! String) {
      throw const FormatException('Steel returned an invalid response.');
    }
    final arguments = _arguments(call['arguments']);
    switch (call['name']) {
      case 'answer_user':
        final answer = arguments['response'] ?? arguments['answer'];
        if (answer is! String ||
            answer.trim().isEmpty ||
            answer.length > 1200) {
          throw const FormatException('Steel returned an empty reply.');
        }
        return SteelChatReply(
          text: answer.trim(),
          sources: retrieved.map((source) => source.label).toList(),
        );
      case 'draft_workout_log':
        final draft = NeedleWorkoutService.parseWorkoutLogResponse(
          jsonEncode(arguments),
          exercises,
        );
        return SteelChatReply(
          text:
              'I’ve prepared a draft for you to review. Nothing has been saved.',
          sources: retrieved.map((source) => source.label).toList(),
          draft: draft,
        );
      case 'select_exercises':
        final names = arguments['exercise_names'];
        if (names is! List) {
          throw const FormatException('Steel could not form an exercise list.');
        }
        final byName = {
          for (final exercise in exercises)
            exercise.name.toLowerCase(): exercise
        };
        final selected = <Exercise>[];
        for (final name in names.whereType<String>()) {
          final exercise = byName[name.toLowerCase()];
          if (exercise != null &&
              !selected.any((item) => item.id == exercise.id)) {
            selected.add(exercise);
          }
          if (selected.length == 8) break;
        }
        if (selected.isEmpty) {
          throw const FormatException(
              'I couldn’t match the suggested exercises to your library.');
        }
        return SteelChatReply(
          text:
              'Here are exercises from your library that fit your request. This is a suggestion; I haven’t saved anything.',
          sources: retrieved.map((source) => source.label).toList(),
          selectedExercises: List.unmodifiable(selected),
        );
      default:
        throw const FormatException('Steel selected an unsupported tool.');
    }
  }

  static Future<SteelChatReply> _answerHistory(
    String question,
    List<Map<String, String>> sessionHistory,
    void Function(int, int)? onProgress,
  ) async {
    final words = _normalize(question);
    if (RegExp(r'^(hi|hey|hello)( steel)?$').hasMatch(words)) {
      return const SteelChatReply(
        text:
            'Hey! I can look up your past sets, compare workouts, or recap your running. What do you want to check?',
      );
    }
    if (RegExp(r'^(thanks|thank you)( steel)?$').hasMatch(words)) {
      return const SteelChatReply(text: 'You’re welcome!');
    }
    if (RegExp(r'\b(what is|what are|what do|difference between)\b')
            .hasMatch(words) &&
        RegExp(r'\b(sets?|reps?)\b').hasMatch(words) &&
        !RegExp(r'\b(my|did|log|mean for)\b').hasMatch(words)) {
      return const SteelChatReply(
        text:
            'A rep is one repetition of an exercise. A set is a group of reps done together before you rest. If you do 8 bench presses, rest, then do 6 more, that’s two sets.',
      );
    }

    final db = await DatabaseService().database;
    final workouts = await db.dailyWorkouts.where().sortByDateDesc().findAll();
    final runs = await db.runningLogs.where().sortByDateDesc().findAll();
    final names = workouts
        .expand((w) => w.trainingExercises)
        .map((ex) => ex.exerciseName)
        .whereType<String>()
        .toSet();
    final matched = _matchedExercises(question, names);
    final explicitTypes =
        NeedleWorkoutService.dataRecordTypes(question).toSet();
    final date = NeedleWorkoutService.requestedDateIn(question);
    final followUp = matched.isEmpty &&
        explicitTypes.isEmpty &&
        RegExp(r'\b(that|those|it|time before|previous one|how about|what about)\b')
            .hasMatch(words);
    final prior = followUp
        ? sessionHistory.reversed
            .where((turn) => turn['role'] == 'user')
            .map((turn) => turn['content'] ?? '')
            .firstWhere(
                (text) =>
                    _matchedExercises(text, names).isNotEmpty ||
                    NeedleWorkoutService.dataRecordTypes(text)
                        .any((type) => type == 'run' || type == 'workout') ||
                    RegExp(r'\b(last time|my training)\b')
                        .hasMatch(_normalize(text)),
                orElse: () => '')
        : '';
    final selectedNames =
        matched.isNotEmpty ? matched : _matchedExercises(prior, names);
    final types = explicitTypes.isNotEmpty
        ? explicitTypes
        : NeedleWorkoutService.dataRecordTypes(prior).toSet();
    final week = RegExp(r'\b(this|current|last|previous) week\b')
        .firstMatch(words)
        ?.group(1);
    final knownHistory = selectedNames.isNotEmpty ||
        types.contains('run') ||
        types.contains('workout') ||
        date != null &&
            (types.contains('exercise') ||
                words.startsWith('what did i do ')) ||
        RegExp(r'\b(last time|training|history|logged|lifted|pr)\b')
            .hasMatch(words) ||
        prior.isNotEmpty;
    if (!knownHistory) {
      return const SteelChatReply(
        text:
            'I can help with your workouts and runs. Ask what you lifted last time, how many sessions you logged this week, or what to put in your next workout.',
      );
    }

    String? view;
    try {
      await NeedleWorkoutService.ensureReady(
          onProgress: onProgress ?? (_, __) {});
      final raw = await NeedleWorkoutService.completeLocally(
        prior.isEmpty
            ? question
            : 'Previous question: $prior\nFollow-up: $question',
        tools: _historyTools,
      );
      view = NeedleWorkoutService.readToolFields(
          raw, _historyTool, _historyTools)?['view'] as String?;
    } on UnsupportedError {
      // Local records still answer the question on a device without Needle.
    } on PlatformException {
      // A failed inference does not make the retrieved records unavailable.
    } on StateError {
      // The native runtime may fail to initialize.
    } on FormatException {
      // The bundled model may be unreadable.
    }
    // ponytail: prioritize explicit cues where the small extraction model
    // abstains or confuses a statistic; richer phrasing can use its view.
    if (RegExp(r'\b(heaviest|highest weight|personal record|pr|max weight)\b')
        .hasMatch(words)) {
      view = 'heaviest';
    } else if (RegExp(r'\b(compare|progress|improv\w*|better)\b')
        .hasMatch(words)) {
      view = 'compare';
    } else if (RegExp(r'\b(how many|total|how much mileage)\b')
        .hasMatch(words)) {
      view = 'count';
    } else if (RegExp(r'\b(summarize|recap|weekly)\b').hasMatch(words)) {
      view = 'weekly';
    } else if (RegExp(
            r'\b(last time|last workout|last run|latest|most recent|time before)\b')
        .hasMatch(words)) {
      view = 'latest';
    } else if (date != null) {
      view = 'latest';
    }

    final now = DateTime.now();
    final lastWeek = week == 'last' || week == 'previous';
    final start = DateTime(
        now.year, now.month, now.day - now.weekday + 1 - (lastWeek ? 7 : 0));
    final end = DateTime(start.year, start.month, start.day + 7);
    final requestedDay = date ??
        (prior.isEmpty || view == 'compare'
            ? null
            : NeedleWorkoutService.requestedDateIn(prior));
    bool inPeriod(DateTime value) {
      if (requestedDay != null) return _date(value) == _date(requestedDay);
      return week == null && view != 'weekly' ||
          !value.isBefore(start) && value.isBefore(end);
    }

    final runOnly = types.contains('run') &&
        !types.contains('workout') &&
        selectedNames.isEmpty;
    final includeRuns = runOnly ||
        types.contains('run') ||
        selectedNames.isEmpty && !types.contains('workout') && view == 'weekly';
    final strength = runOnly
        ? <DailyWorkout>[]
        : workouts
            .where((workout) =>
                inPeriod(workout.date) &&
                (selectedNames.isEmpty ||
                    workout.trainingExercises
                        .any((ex) => selectedNames.contains(ex.exerciseName))))
            .toList();
    final running = includeRuns
        ? runs.where((run) => inPeriod(run.date)).toList()
        : <RunningLog>[];
    final activity = runOnly ? 'run' : 'workout';
    final focus =
        selectedNames.isEmpty ? '' : ' with ${selectedNames.join(' or ')}';
    if (strength.isEmpty && running.isEmpty) {
      final period = requestedDay != null
          ? ' on ${_date(requestedDay)}'
          : week != null || view == 'weekly'
              ? (lastWeek ? ' last week' : ' this week')
              : '';
      return SteelChatReply(
          text: 'I don’t see a logged $activity$focus$period.');
    }

    Iterable<LoggedExercise> exercises(DailyWorkout w) =>
        w.trainingExercises.where((ex) =>
            selectedNames.isEmpty || selectedNames.contains(ex.exerciseName));
    if (selectedNames.length == 1 &&
        RegExp(r'\b(next time|next session|aim for)\b').hasMatch(words)) {
      final name = selectedNames.single;
      final target = ProgressionService.suggestNextTarget(name, strength);
      if (target != null) {
        return SteelChatReply(
          text:
              'For your next $name session, try ${formatWeightReps(target.weight, target.reps)}. ${target.rationale}',
          sources: target.supportingSessions
              .map((session) =>
                  '${_date(session.date)} · ${formatWeightReps(session.topWeight, session.topWeightReps)}')
              .toList(),
        );
      }
    }
    if (view == 'heaviest' && strength.isNotEmpty) {
      ({DailyWorkout workout, LoggedExercise exercise, SetLog set})? best;
      for (final workout in strength) {
        for (final exercise in exercises(workout)) {
          for (final set in exercise.sets) {
            if (best == null || set.weight > best.set.weight) {
              best = (workout: workout, exercise: exercise, set: set);
            }
          }
        }
      }
      if (best != null) {
        final set = best.set;
        final label =
            '${_date(best.workout.date)} · ${best.exercise.exerciseName}';
        return SteelChatReply(
          text:
              'Your heaviest logged ${best.exercise.exerciseName} set was ${formatWeightReps(set.weight, set.reps)} on ${_date(best.workout.date)}.',
          sources: [label],
        );
      }
    }
    if (view == 'count' || view == 'weekly') {
      final scope = requestedDay != null
          ? ' on ${_date(requestedDay)}'
          : week != null || view == 'weekly'
              ? (lastWeek ? ' last week' : ' this week')
              : ' in your history';
      final summaries = <String>[];
      if (!runOnly) {
        final singleSession = followUp ||
            RegExp(r'\b(last time|last workout|latest|most recent)\b')
                .hasMatch(words);
        final sessions = singleSession ? strength.take(1).toList() : strength;
        final sets =
            sessions.expand(exercises).expand((ex) => ex.sets).toList();
        final steps = sets.expand((set) => set.subSets).where((step) => step.reps > 0);
        final count = sets.length + steps.length;
        final reps = sets.fold<int>(0, (total, set) => total + set.reps) + steps.fold<int>(0, (total, step) => total + step.reps);
        final volume =
            '$count ${count == 1 ? 'set' : 'sets'} and $reps ${reps == 1 ? 'rep' : 'reps'}';
        summaries.add(singleSession && sessions.isNotEmpty
            ? 'On ${_date(sessions.first.date)}, you logged $volume$focus.'
            : 'You logged ${sessions.length} ${sessions.length == 1 ? 'workout' : 'workouts'}$focus$scope, with $volume.');
      }
      if (includeRuns) {
        final miles = running.fold<int>(0, (sum, run) => sum + run.miles);
        summaries.add(
            'You logged ${running.length} ${running.length == 1 ? 'run' : 'runs'} totaling $miles ${miles == 1 ? 'mile' : 'miles'}$scope.');
      }
      return SteelChatReply(text: summaries.join(' '));
    }

    final earlier =
        RegExp(r'\b(time before|previous one|one before|penultimate)\b')
            .hasMatch(words);
    final rows = [
      for (final workout in strength)
        (
          date: workout.date,
          label:
              '${_date(workout.date)} · ${exercises(workout).map((ex) => ex.exerciseName).join(', ')}',
          details: exercises(workout)
              .map((ex) =>
                  '${ex.exerciseName}: ${ex.sets.expand((set) => [formatWeightReps(set.weight, set.reps), ...set.sequence.map(formatSetStep)]).join(', ')}')
              .join('\n')
        ),
      for (final run in running)
        (
          date: run.date,
          label: '${_date(run.date)} · ${run.miles} mi',
          details: 'You ran ${run.miles} ${run.miles == 1 ? 'mile' : 'miles'}.'
        ),
    ]..sort((a, b) => b.date.compareTo(a.date));
    final limit = view == 'compare'
        ? 2
        : view == 'list' || requestedDay != null
            ? 4
            : 1;
    final shown = rows.skip(earlier ? 1 : 0).take(limit).toList();
    if (shown.isEmpty) {
      return SteelChatReply(
          text:
              'I found one logged $activity$focus. I don’t see an earlier one.');
    }
    final intro = view == 'compare' && shown.length == 2
        ? 'Here are the two most recent entries$focus:'
        : shown.length == 1
            ? 'Here’s what you logged on ${_date(shown.single.date)}:'
            : 'Here are the matching entries$focus:';
    return SteelChatReply(
      text:
          '$intro\n${shown.map((row) => shown.length == 1 ? row.details : '${_date(row.date)}\n${row.details}').join('\n\n')}',
      sources: shown.map((row) => row.label).toList(),
    );
  }

  static Set<String> _matchedExercises(String question, Set<String> names) {
    final query = _terms(question);
    final matches = {
      for (final name in names) name: _terms(name).intersection(query).length
    };
    final best =
        matches.values.fold<int>(0, (max, score) => score > max ? score : max);
    return {
      if (best > 0)
        for (final entry in matches.entries)
          if (entry.value == best) entry.key
    };
  }

  static Future<List<SteelLocalDocument>> _loadDocuments(
    Isar db,
    List<Exercise> exercises,
  ) async {
    final workouts = await db.dailyWorkouts.where().sortByDateDesc().findAll();
    final runs = await db.runningLogs.where().sortByDateDesc().findAll();
    final folders = await db.workoutFolders.where().sortByName().findAll();
    // ponytail: rank the local history in memory for now; if logs grow substantially, cache summaries in an Isar index.
    final documents = <SteelLocalDocument>[];
    for (final workout in workouts) {
      final logged = workout.exercises.map((exercise) {
        final name = exercise.exerciseName ?? 'Unknown exercise';
        return {
          'name': name,
          'target_muscle': exercise.targetMuscle,
          'target_muscles': exercise.targetMuscles,
          'secondary_muscles': exercise.secondaryMuscles,
          'sets': exercise.sets
              .map((set) => {
                    'weight': set.weight,
                    'reps': set.reps,
                    'rest_pause_seconds': set.restPauseSeconds,
                    'sub_sets': set.subSets
                        .map((subSet) => {
                              'weight': subSet.weight,
                              'reps': subSet.reps,
                              'pause_seconds': subSet.pauseSeconds,
                              'exercise_name': subSet.exerciseName,
                              'target_muscles': subSet.targetMuscles,
                              'secondary_muscles': subSet.secondaryMuscles,
                            })
                        .toList(),
                  })
              .toList(),
        };
      }).toList();
      final names = logged.map((exercise) => exercise['name']).join(', ');
      documents.add(SteelLocalDocument(
        kind: 'workout',
        label: '${_date(workout.date)} · $names',
        date: workout.date,
        searchableText: '$names ${_date(workout.date)}',
        evidence: {
          'kind': 'workout',
          'id': workout.id,
          'date': _date(workout.date),
          'exercises': logged,
        },
      ));
    }
    for (final run in runs) {
      documents.add(SteelLocalDocument(
        kind: 'run',
        label: '${_date(run.date)} · ${run.miles} mile run',
        date: run.date,
        searchableText: 'run running miles ${run.miles} ${_date(run.date)}',
        evidence: {
          'kind': 'run',
          'id': run.id,
          'date': _date(run.date),
          'miles': run.miles,
        },
      ));
    }
    for (final exercise in exercises) {
      documents.add(SteelLocalDocument(
        kind: 'exercise',
        label: 'Exercise · ${exercise.name}',
        searchableText: [
          exercise.name,
          exercise.targetMuscle,
          ...exercise.targetMuscles,
          ...exercise.secondaryMuscles,
          ...exercise.folderNames,
        ].join(' '),
        evidence: {
          'kind': 'exercise',
          'id': exercise.id,
          'name': exercise.name,
          'target_muscle': exercise.targetMuscle,
          'target_muscles': exercise.targetMuscles,
          'secondary_muscles': exercise.secondaryMuscles,
          'favorite_folders': exercise.folderNames,
          'is_favorite': exercise.isFavorite,
        },
      ));
    }
    for (final folder in folders) {
      final folderExercises = exercises
          .where((exercise) => exercise.folderNames.contains(folder.name))
          .map((exercise) => exercise.name)
          .toList();
      documents.add(SteelLocalDocument(
        kind: 'folder',
        label: 'Favorites · ${folder.name}',
        searchableText: '${folder.name} ${folderExercises.join(' ')}',
        evidence: {
          'kind': 'folder',
          'id': folder.id,
          'name': folder.name,
          'exercises': folderExercises,
        },
      ));
    }
    return documents;
  }

  static Map<String, dynamic> _decode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } on FormatException {
      // The model output is not trusted as display text when it is malformed.
    }
    throw const FormatException('Steel returned an unreadable response.');
  }

  static Map<String, dynamic> _arguments(Object? value) {
    final parsed = value is String ? jsonDecode(value) : value;
    if (parsed is Map && parsed.keys.every((key) => key is String)) {
      return Map<String, dynamic>.from(parsed);
    }
    throw const FormatException('Steel returned invalid tool details.');
  }

  static Set<String> _terms(String value) => _words(value)
      .where((word) => word.length > 2 && !_stopWords.contains(word))
      .map((word) => word.length > 4 && word.endsWith('s')
          ? word.substring(0, word.length - 1)
          : word)
      .toSet();

  static List<String> _words(String value) =>
      _normalize(value).split(' ').where((word) => word.isNotEmpty).toList();

  static String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}
