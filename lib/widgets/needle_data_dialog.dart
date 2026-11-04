import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/needle_workout_service.dart';
import '../services/steel_guardrails.dart';
import '../services/theme_service.dart';
import 'steel_delete_confirmation_dialog.dart';

class NeedleDataDialog extends StatefulWidget {
  final VoidCallback? onChanged;

  const NeedleDataDialog({super.key, this.onChanged});

  @override
  State<NeedleDataDialog> createState() => _NeedleDataDialogState();
}

class _NeedleDataDialogState extends State<NeedleDataDialog> {
  static const _maxSessionExchanges = 10;
  final _requestController = TextEditingController();
  NeedleDataAction? _action;
  bool _working = false;
  String? _message;
  bool _error = false;
  final _sessionHistory = <Map<String, String>>[];
  int _exchangeCount = 0;

  String get _sessionMemoryLabel => _exchangeCount <= _maxSessionExchanges
      ? '$_exchangeCount/$_maxSessionExchanges exchanges in memory'
      : 'Remembering the last $_maxSessionExchanges of $_exchangeCount exchanges';

  AppTheme get _theme => ThemeService().getResolvedTheme(context);

  @override
  void dispose() {
    _requestController.dispose();
    unawaited(NeedleWorkoutService.resetConversation().catchError((_) {}));
    super.dispose();
  }

  Future<void> _askNeedle() async {
    final request = _requestController.text.trim();
    if (request.isEmpty || _working) return;
    if (request.length > 1200) {
      setState(() {
        _error = true;
        _message =
            'That’s a lot to sort through. Try one request in 1,200 characters or less.';
      });
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    final previousAction = _action;
    if (previousAction != null && previousAction.operation != 'read') {
      _replaceLastAssistantMessage(
          'That proposal was not approved, so Steel did not apply it.');
    }
    setState(() {
      _working = true;
      _action = null;
      _message = null;
      _error = false;
    });
    try {
      await NeedleWorkoutService.ensureReady(onProgress: (_, __) {});
      await NeedleWorkoutService.resetConversation();
      final action = await NeedleWorkoutService.proposeDataAction(
        request,
        sessionHistory: List<Map<String, String>>.unmodifiable(_sessionHistory),
      );
      if (action.operation == 'delete' &&
          SteelGuardrails.isBulkDeleteRequest(request)) {
        throw const FormatException(
          'Steel can delete one item at a time. Please name one record.',
        );
      }
      if (!SteelGuardrails.allowsOperation(request, action.operation)) {
        throw const FormatException(
          'Needle proposed an operation that was not explicit in your request. Please rephrase it.',
        );
      }
      if (!mounted) return;
      _rememberExchange(
        request,
        action.operation == 'read'
            ? action.summary
            : 'Steel proposed: ${action.summary} This has not been applied.',
      );
      setState(() {
        _action = action;
        _message = action.operation == 'read'
            ? action.summary
            : 'Here’s Steel’s proposal. Nothing changes until you approve it.';
      });
    } catch (error) {
      if (mounted) {
        _rememberExchange(request, _friendlyError(error));
        setState(() {
          _error = true;
          _message = _friendlyError(error);
        });
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  String _friendlyError(Object error, {bool applying = false}) {
    final detail = error.toString().toLowerCase();
    if (detail.contains('already exists')) {
      return 'There’s already an item with that name. Try a different name.';
    }
    if (detail.contains('no longer exists')) {
      return 'That item may have changed. Please refresh, then ask Steel again.';
    }
    if (detail.contains('one item at a time')) {
      return 'I can delete one item at a time. Please name one record.';
    }
    if (detail.contains('unsupportederror')) {
      return 'Steel needs a supported ARM Android device. You can still manage your records in HybridLog.';
    }
    if (applying) {
      return 'I couldn’t confirm that change finished. Check the record before trying again.';
    }
    return 'I couldn’t prepare that safely. Try naming the item and asking for one action at a time.';
  }

  void _rememberExchange(String request, String response) {
    _exchangeCount++;
    _sessionHistory
      ..add({'role': 'user', 'content': _limitContext(request)})
      ..add({'role': 'assistant', 'content': _limitContext(response)});
    while (_sessionHistory.length > _maxSessionExchanges * 2) {
      _sessionHistory.removeAt(0);
    }
  }

  String _limitContext(String value) =>
      value.length <= 300 ? value : '${value.substring(0, 297)}...';

  void _replaceLastAssistantMessage(String message) {
    for (var i = _sessionHistory.length - 1; i >= 0; i--) {
      if (_sessionHistory[i]['role'] == 'assistant') {
        _sessionHistory[i] = {
          'role': 'assistant',
          'content': _limitContext(message),
        };
        return;
      }
    }
  }

  Future<void> _approve() async {
    final action = _action;
    if (action == null || action.operation == 'read' || _working) return;
    if (action.operation == 'delete' && !await _confirmDelete(action.summary)) {
      return;
    }

    setState(() {
      _working = true;
      _message = null;
    });
    try {
      await NeedleWorkoutService.applyApprovedDataAction(action);
      widget.onChanged?.call();
      if (!mounted) return;
      final completed = switch (action.operation) {
        'create' => 'Done. I added it to your local app data.',
        'update' => 'Done. I saved that change on this device.',
        'delete' => 'Done. I deleted the selected item.',
        _ => 'Done.',
      };
      _replaceLastAssistantMessage(completed);
      setState(() {
        _action = null;
        _error = false;
        _message = completed;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = true;
          _message = _friendlyError(error, applying: true);
        });
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<bool> _confirmDelete(String summary) async {
    final theme = _theme;
    return await SteelDeleteConfirmationDialog.show(
          context,
          summary: summary,
          cardColor: theme.card,
          textColor: theme.text,
          secondaryTextColor: theme.subText,
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = _theme;
    final action = _action;
    return Dialog(
      backgroundColor: theme.card,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540, maxHeight: 700),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Icon(Icons.storage_outlined, color: theme.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Steel · app data',
                      style: TextStyle(
                          color: theme.text,
                          fontSize: 19,
                          fontWeight: FontWeight.bold)),
                ),
                IconButton(
                  onPressed: _working ? null : () => Navigator.pop(context),
                  icon: Icon(Icons.close, color: theme.subText),
                ),
              ]),
              Text(
                'Ask Steel to read or change your exercises, folders, workouts, or runs. It proposes one action at a time, and you approve every change.',
                style: TextStyle(color: theme.subText, fontSize: 12),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _requestController,
                minLines: 2,
                maxLines: 4,
                enabled: !_working,
                style: TextStyle(color: theme.text),
                decoration: InputDecoration(
                  hintText: 'For example: add an exercise called Incline Press',
                  hintStyle: TextStyle(color: theme.subText),
                  helperText: _sessionMemoryLabel,
                  helperStyle: TextStyle(color: theme.subText, fontSize: 11),
                  filled: true,
                  fillColor: theme.background,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _working ? null : _askNeedle,
                  style: FilledButton.styleFrom(backgroundColor: theme.accent),
                  icon: _working
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.auto_awesome, size: 17),
                  label: Text(_working ? 'Working…' : 'Ask Steel'),
                ),
              ),
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(_message!,
                      style: TextStyle(
                          color: _error ? Colors.red : theme.text,
                          fontSize: 13)),
                ),
              if (action != null && action.operation != 'read') ...[
                const SizedBox(height: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: theme.background,
                        borderRadius: BorderRadius.circular(14)),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${action.operation.toUpperCase()} · ${action.recordType.toUpperCase()}',
                            style: TextStyle(
                                color: theme.accent,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: .5),
                          ),
                          const SizedBox(height: 6),
                          Text(action.summary,
                              style: TextStyle(
                                  color: theme.text,
                                  fontWeight: FontWeight.w600)),
                          if (action.operation != 'delete') ...[
                            const SizedBox(height: 10),
                            SelectableText(
                              const JsonEncoder.withIndent('  ')
                                  .convert(action.record),
                              style: TextStyle(
                                  color: theme.subText,
                                  fontSize: 11,
                                  fontFamily: 'monospace'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _working ? null : _approve,
                  style: FilledButton.styleFrom(
                    backgroundColor: action.operation == 'delete'
                        ? Colors.red
                        : theme.accent,
                  ),
                  child: Text(switch (action.operation) {
                    'create' => 'Approve & create',
                    'update' => 'Approve & update',
                    'delete' => 'Review deletion',
                    _ => 'Approve',
                  }),
                ),
              ],
              if (action == null || action.operation == 'read') const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
