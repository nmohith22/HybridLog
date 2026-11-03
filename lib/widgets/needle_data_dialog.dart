import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/needle_workout_service.dart';
import '../services/theme_service.dart';

class NeedleDataDialog extends StatefulWidget {
  final VoidCallback? onChanged;

  const NeedleDataDialog({super.key, this.onChanged});

  @override
  State<NeedleDataDialog> createState() => _NeedleDataDialogState();
}

class _NeedleDataDialogState extends State<NeedleDataDialog> {
  final _requestController = TextEditingController();
  NeedleDataAction? _action;
  bool _working = false;
  String? _message;
  bool _error = false;

  AppTheme get _theme => ThemeService().getResolvedTheme(context);

  @override
  void dispose() {
    _requestController.dispose();
    super.dispose();
  }

  Future<void> _askNeedle() async {
    final request = _requestController.text.trim();
    if (request.isEmpty || _working) return;
    setState(() {
      _working = true;
      _action = null;
      _message = null;
      _error = false;
    });
    try {
      await NeedleWorkoutService.ensureReady(onProgress: (_, __) {});
      await NeedleWorkoutService.resetConversation();
      final action = await NeedleWorkoutService.proposeDataAction(request);
      if (!_requestExplicitlyAllows(request, action.operation)) {
        throw const FormatException(
          'Needle proposed an operation that was not explicit in your request. Please rephrase it.',
        );
      }
      if (!mounted) return;
      setState(() {
        _action = action;
        _message = action.operation == 'read'
            ? action.summary
            : 'Review Needle’s proposal below. Nothing is saved until you approve it.';
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = true;
          _message = error.toString().replaceFirst('FormatException: ', '');
        });
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  bool _requestExplicitlyAllows(String request, String operation) {
    final text = request.toLowerCase();
    if (operation == 'read') return true;
    if (RegExp(
      r"\b(don't|do not|never|without)\s+(delete|remove|erase|create|add|make|log|record|update|edit|change|rename|modify)\b",
    ).hasMatch(text)) {
      return false;
    }
    final pattern = switch (operation) {
      'create' => r'\b(create|add|make|log|record|save)\b',
      'update' => r'\b(update|edit|change|rename|modify)\b',
      'delete' => r'\b(delete|remove|erase)\b',
      'read' =>
        r'\b(show|list|find|read|tell|what|which|when|how many|how much)\b',
      _ => r'(?!)',
    };
    return RegExp(pattern).hasMatch(text);
  }

  Future<void> _approve() async {
    final action = _action;
    if (action == null || action.operation == 'read' || _working) return;
    if (action.operation == 'delete' && !await _confirmDelete(action)) return;

    setState(() {
      _working = true;
      _message = null;
    });
    try {
      await NeedleWorkoutService.applyApprovedDataAction(action);
      widget.onChanged?.call();
      if (!mounted) return;
      setState(() {
        _action = null;
        _error = false;
        _message = 'Approved ${action.operation} completed.';
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = true;
          _message = error.toString().replaceFirst('Bad state: ', '');
        });
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<bool> _confirmDelete(NeedleDataAction action) async {
    final theme = _theme;
    var checked = false;
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => StatefulBuilder(
            builder: (context, setModalState) => AlertDialog(
              backgroundColor: theme.card,
              titlePadding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
              title: Row(children: [
                Expanded(
                  child: Text('Confirm deletion',
                      style: TextStyle(
                          color: theme.text, fontWeight: FontWeight.bold)),
                ),
                IconButton(
                  tooltip: 'Cancel deletion',
                  onPressed: () => Navigator.pop(dialogContext, false),
                  icon: const Icon(Icons.close, color: Colors.red),
                ),
              ]),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(action.summary, style: TextStyle(color: theme.text)),
                  const SizedBox(height: 12),
                  Text('This deletion cannot be undone.',
                      style: TextStyle(color: theme.subText)),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: checked,
                    activeColor: Colors.red,
                    title: Text('I want to delete this item',
                        style: TextStyle(color: theme.text, fontSize: 13)),
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: (value) =>
                        setModalState(() => checked = value ?? false),
                  ),
                ],
              ),
              actions: [
                FilledButton(
                  onPressed:
                      checked ? () => Navigator.pop(dialogContext, true) : null,
                  style: FilledButton.styleFrom(
                      backgroundColor: Colors.red,
                      disabledBackgroundColor:
                          Colors.red.withValues(alpha: .3)),
                  child: const Text('Delete'),
                ),
              ],
            ),
          ),
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
                  child: Text('Manage app data',
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
                'Ask Needle to read or change your exercises, folders, workouts, or runs. It only proposes one action at a time; you approve every change.',
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
                  hintText: 'Example: add an exercise named Incline Press',
                  hintStyle: TextStyle(color: theme.subText),
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
                  label: Text(_working ? 'Working…' : 'Ask Needle'),
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
