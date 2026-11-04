import 'dart:convert';

import 'package:isar/isar.dart';

import '../models/fitness_schema.dart';
import 'database_service.dart';
import 'equipment_profile_service.dart';
import 'needle_workout_service.dart';
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
    final wantsRecent = _words(question).any(_recentWords.contains);
    final thisWeek =
        RegExp(r'\b(this week|current week)\b', caseSensitive: false)
            .hasMatch(question);
    final today = DateTime.now();
    final weekStart = DateTime(today.year, today.month, today.day)
        .subtract(Duration(days: today.weekday - DateTime.monday));
    final ranked = <({SteelLocalDocument document, double score})>[];

    for (final document in documents) {
      if (thisWeek &&
          (document.kind == 'workout' || document.kind == 'run') &&
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
      if (wantsRecent &&
          (document.kind == 'workout' || document.kind == 'run')) {
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
  }) async {
    final request = question.trim();
    if (request.isEmpty) {
      throw const FormatException('Type a message for Steel first.');
    }
    if (request.length > 1200) {
      throw const FormatException('Keep each message under 1,200 characters.');
    }

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
        text:
            'I couldn’t find a reliable answer yet. Try asking about a specific exercise, workout date, or what you want to log.',
        sources: retrieved.map((source) => source.label).toList(),
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
      case 'manage_data':
        final action =
            await NeedleWorkoutService.validateProposedDataAction(raw);
        if (action.operation == 'delete' &&
            SteelGuardrails.isBulkDeleteRequest(request)) {
          throw const FormatException(
              'Steel can delete one item at a time. Please name one record.');
        }
        if (!SteelGuardrails.allowsOperation(request, action.operation)) {
          throw const FormatException(
              'I can only change app data when you clearly ask me to. Please say exactly what you want changed.');
        }
        return SteelChatReply(
          text: action.operation == 'read'
              ? action.summary
              : 'Here’s my proposal. Nothing changes until you approve it.',
          sources: retrieved.map((source) => source.label).toList(),
          action: action,
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
