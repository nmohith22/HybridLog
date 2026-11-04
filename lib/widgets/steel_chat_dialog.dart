import 'dart:async';

import 'package:flutter/material.dart';

import '../services/needle_workout_service.dart';
import '../services/steel_chat_service.dart';
import '../services/steel_guardrails.dart';
import '../services/theme_service.dart';
import '../utils/weight_reps_format.dart';
import 'steel_delete_confirmation_dialog.dart';

class SteelChatDialogResult {
  final bool openPlanner;
  final WorkoutLogDraft? draft;

  const SteelChatDialogResult({this.openPlanner = false, this.draft});
}

class SteelChatDialog extends StatefulWidget {
  final VoidCallback onDataChanged;

  const SteelChatDialog({super.key, required this.onDataChanged});

  @override
  State<SteelChatDialog> createState() => _SteelChatDialogState();
}

class _SteelChatDialogState extends State<SteelChatDialog> {
  static const _maxExchanges = 10;
  static const _suggestions = [
    ('Build a workout', 'Use my recent training and equipment.'),
    ('Log a workout', 'Help me turn a workout into a draft.'),
    ('Ask my history', 'What did I do last time?'),
    ('Weekly recap', 'Summarize my training this week.'),
  ];

  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <_SteelMessage>[
    _SteelMessage(
      role: 'assistant',
      text:
          'Hi, I’m Steel. Ask me about your training, or tell me what you need.',
    ),
  ];
  final _history = <Map<String, String>>[];
  int _exchangeCount = 0;
  int _loaded = 0;
  int _total = -1;
  bool _working = false;

  AppTheme get _theme => ThemeService().getResolvedTheme(context);
  String get _memoryLabel => _exchangeCount <= _maxExchanges
      ? '$_exchangeCount/$_maxExchanges exchanges in memory'
      : 'Remembering the last $_maxExchanges of $_exchangeCount exchanges';

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    unawaited(NeedleWorkoutService.resetConversation().catchError((_) {}));
    super.dispose();
  }

  Future<void> _send([String? message]) async {
    final request = (message ?? _input.text).trim();
    if (_working || request.isEmpty) return;
    if (request.length > 1200) {
      setState(() => _messages.add(_SteelMessage(
            role: 'assistant',
            text:
                'Keep each message under 1,200 characters and I can help with it.',
            isError: true,
          )));
      _scrollToEnd();
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _input.clear();
      _working = true;
      _loaded = 0;
      _total = -1;
      _messages.add(_SteelMessage(role: 'user', text: request));
    });
    _scrollToEnd();
    try {
      await NeedleWorkoutService.ensureReady(onProgress: (loaded, total) {
        if (mounted)
          setState(() {
            _loaded = loaded;
            _total = total;
          });
      });
      final reply = await SteelChatService.ask(
        request,
        sessionHistory: List.unmodifiable(_history),
      );
      if (!mounted) return;
      setState(() {
        _messages.add(_SteelMessage(
          role: 'assistant',
          text: reply.text,
          reply: reply,
          request: request,
        ));
        _remember(request, reply.text);
      });
    } catch (error) {
      if (!mounted) return;
      final message = _friendlyError(error);
      setState(() {
        _messages.add(_SteelMessage(
          role: 'assistant',
          text: message,
          isError: true,
        ));
        _remember(request, message);
      });
    } finally {
      if (mounted) {
        setState(() => _working = false);
        _scrollToEnd();
      }
    }
  }

  String _friendlyError(Object error) {
    if (error is FormatException) return error.message.toString();
    if (error is UnsupportedError ||
        error.toString().contains('UnsupportedError')) {
      return 'Steel needs a supported ARM Android device. Your workout data stays in the app, and you can still use the regular workout logger.';
    }
    return 'I couldn’t finish that. Try asking about one exercise, workout, or change at a time.';
  }

  void _remember(String request, String response) {
    _exchangeCount++;
    _history
      ..add({'role': 'user', 'content': _limit(request)})
      ..add({'role': 'assistant', 'content': _limit(response)});
    while (_history.length > _maxExchanges * 2) {
      _history.removeAt(0);
    }
  }

  String _limit(String text) =>
      text.length <= 300 ? text : '${text.substring(0, 297)}...';

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _selectSuggestion(int index) {
    if (index == 0) {
      Navigator.pop(context, const SteelChatDialogResult(openPlanner: true));
      return;
    }
    _send(_suggestions[index].$2);
  }

  Future<void> _approve(_SteelMessage message) async {
    final action = message.reply?.action;
    if (action == null || action.operation == 'read' || _working) return;
    final request = message.request ?? '';
    if (!SteelGuardrails.allowsOperation(request, action.operation)) {
      setState(() => message.text = action.operation == 'delete'
          ? 'I can delete one item at a time. Please name one record.'
          : 'I can only apply a change you clearly asked me to make.');
      return;
    }
    if (action.operation == 'delete') {
      final approved = await SteelDeleteConfirmationDialog.show(
        context,
        summary: action.summary,
        cardColor: _theme.card,
        textColor: _theme.text,
        secondaryTextColor: _theme.subText,
      );
      if (approved != true) return;
    }
    setState(() => _working = true);
    try {
      await NeedleWorkoutService.applyApprovedDataAction(action);
      widget.onDataChanged();
      if (!mounted) return;
      setState(() {
        message.text = switch (action.operation) {
          'create' => 'Done. I added it to your local app data.',
          'update' => 'Done. I saved that change on this device.',
          'delete' => 'Done. I deleted the selected item.',
          _ => 'Done.',
        };
        message.reply = null;
      });
    } catch (_) {
      if (mounted)
        setState(() => message.text =
            'I couldn’t confirm that change finished. Check the record before trying again.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = _theme;
    return Dialog(
      backgroundColor: theme.card,
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: MediaQuery.sizeOf(context).height * .92,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          child: Column(children: [
            Row(children: [
              Icon(Icons.auto_awesome, color: theme.accent),
              const SizedBox(width: 10),
              Expanded(
                  child: Text('Steel',
                      style: TextStyle(
                          color: theme.text,
                          fontSize: 19,
                          fontWeight: FontWeight.bold))),
              IconButton(
                tooltip: 'Close',
                onPressed: _working ? null : () => Navigator.pop(context),
                icon: Icon(Icons.close, color: theme.subText),
              ),
            ]),
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _messages.length + (_working ? 1 : 0),
                itemBuilder: (context, index) {
                  if (_working && index == _messages.length) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(4, 8, 36, 10),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            LinearProgressIndicator(
                              value: _total > 0
                                  ? (_loaded / _total).clamp(0, 1)
                                  : null,
                              color: theme.accent,
                              backgroundColor: theme.background,
                            ),
                            const SizedBox(height: 8),
                            Text(
                                _loaded == 0
                                    ? 'Getting Steel ready…'
                                    : 'Steel is thinking…',
                                style: TextStyle(
                                    color: theme.subText, fontSize: 12)),
                          ]),
                    );
                  }
                  return _messageBubble(_messages[index], theme);
                },
              ),
            ),
            ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text('SUGGESTED PROMPTS',
                    style: TextStyle(
                        color: theme.subText,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1)),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 2,
                children: List.generate(
                    _suggestions.length,
                    (index) => ActionChip(
                          label: Text(_suggestions[index].$1,
                              style:
                                  TextStyle(color: theme.text, fontSize: 11)),
                          avatar: Icon(
                              [
                                Icons.fitness_center,
                                Icons.edit_note,
                                Icons.manage_search,
                                Icons.insights
                              ][index],
                              size: 16,
                              color: theme.accent),
                          backgroundColor: theme.background,
                          onPressed:
                              _working ? null : () => _selectSuggestion(index),
                          side: BorderSide(
                              color: theme.accent.withValues(alpha: .22)),
                        )),
              ),
              const SizedBox(height: 8),
            ],
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 4,
                  enabled: !_working,
                  maxLength: 1200,
                  buildCounter: (context,
                          {required currentLength,
                          required isFocused,
                          maxLength}) =>
                      null,
                  textCapitalization: TextCapitalization.sentences,
                  onSubmitted: (_) => _send(),
                  style: TextStyle(color: theme.text),
                  decoration: InputDecoration(
                    hintText: 'Ask Steel anything…',
                    hintStyle: TextStyle(color: theme.subText),
                    filled: true,
                    fillColor: theme.background,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: 'Send',
                onPressed: _working || _input.text.trim().isEmpty
                    ? null
                    : () => _send(),
                style: IconButton.styleFrom(
                    backgroundColor: theme.accent,
                    foregroundColor: theme.background),
                icon: const Icon(Icons.send_rounded),
              ),
            ]),
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Row(children: [
                Expanded(
                    child: Text(_memoryLabel,
                        style: TextStyle(color: theme.subText, fontSize: 10))),
                Text('Your workout data stays on this device.',
                    style: TextStyle(color: theme.subText, fontSize: 10)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _messageBubble(_SteelMessage message, AppTheme theme) {
    final fromUser = message.role == 'user';
    final reply = message.reply;
    return Align(
      alignment: fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 440),
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color:
              fromUser ? theme.accent.withValues(alpha: .18) : theme.background,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(15),
            topRight: const Radius.circular(15),
            bottomLeft: Radius.circular(fromUser ? 15 : 4),
            bottomRight: Radius.circular(fromUser ? 4 : 15),
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(message.text,
              style: TextStyle(
                  color: message.isError ? theme.accent : theme.text,
                  fontSize: 13,
                  height: 1.35)),
          if (reply?.draft case final draft?) ...[
            const SizedBox(height: 10),
            _detailCard(theme, Icons.edit_note, 'Workout draft', [
              draft.exercise.name,
              ...draft.sets
                  .map((set) => formatWeightReps(set.weight, set.reps)),
            ]),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () =>
                  Navigator.pop(context, SteelChatDialogResult(draft: draft)),
              icon: const Icon(Icons.fact_check_outlined, size: 17),
              label: const Text('Review in logger'),
            ),
          ],
          if (reply?.action case final action?) ...[
            const SizedBox(height: 10),
            _detailCard(theme, Icons.storage_outlined, 'Proposed change',
                [action.summary]),
            if (action.operation != 'read') ...[
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _working ? null : () => _approve(message),
                style: FilledButton.styleFrom(
                    backgroundColor: theme.accent,
                    foregroundColor: theme.background),
                icon: const Icon(Icons.check, size: 17),
                label: const Text('Approve change'),
              ),
            ],
          ],
          if (reply != null && reply.selectedExercises.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...reply.selectedExercises.map((exercise) => Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text('• ${exercise.name}',
                      style: TextStyle(color: theme.text, fontSize: 12)),
                )),
          ],
          if (reply != null && reply.sources.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('From your app data: ${reply.sources.take(4).join(' · ')}',
                style: TextStyle(color: theme.subText, fontSize: 10)),
          ],
        ]),
      ),
    );
  }

  Widget _detailCard(
          AppTheme theme, IconData icon, String title, List<String> lines) =>
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: theme.card, borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 16, color: theme.accent),
            const SizedBox(width: 7),
            Text(title,
                style: TextStyle(
                    color: theme.text,
                    fontWeight: FontWeight.w600,
                    fontSize: 12))
          ]),
          const SizedBox(height: 6),
          ...lines.map((line) => Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(line,
                  style: TextStyle(color: theme.subText, fontSize: 11)))),
        ]),
      );
}

class _SteelMessage {
  final String role;
  String text;
  SteelChatReply? reply;
  final bool isError;
  final String? request;

  _SteelMessage({
    required this.role,
    required this.text,
    this.reply,
    this.isError = false,
    this.request,
  });
}
