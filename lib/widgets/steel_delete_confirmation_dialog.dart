import 'package:flutter/material.dart';

class SteelDeleteConfirmationDialog extends StatefulWidget {
  final String summary;
  final Color cardColor;
  final Color textColor;
  final Color secondaryTextColor;

  const SteelDeleteConfirmationDialog({
    super.key,
    required this.summary,
    required this.cardColor,
    required this.textColor,
    required this.secondaryTextColor,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String summary,
    required Color cardColor,
    required Color textColor,
    required Color secondaryTextColor,
  }) =>
      showDialog<bool>(
        context: context,
        builder: (_) => SteelDeleteConfirmationDialog(
          summary: summary,
          cardColor: cardColor,
          textColor: textColor,
          secondaryTextColor: secondaryTextColor,
        ),
      );

  @override
  State<SteelDeleteConfirmationDialog> createState() =>
      _SteelDeleteConfirmationDialogState();
}

class _SteelDeleteConfirmationDialogState
    extends State<SteelDeleteConfirmationDialog> {
  bool _checked = false;

  @override
  Widget build(BuildContext context) => AlertDialog(
        backgroundColor: widget.cardColor,
        titlePadding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
        title: Row(children: [
          Expanded(
            child: Text('Confirm deletion',
                style: TextStyle(
                    color: widget.textColor, fontWeight: FontWeight.bold)),
          ),
          IconButton(
            tooltip: 'Cancel deletion',
            onPressed: () => Navigator.pop(context, false),
            icon: const Icon(Icons.close, color: Colors.red),
          ),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.summary, style: TextStyle(color: widget.textColor)),
            const SizedBox(height: 12),
            Text('This deletion cannot be undone.',
                style: TextStyle(color: widget.secondaryTextColor)),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _checked,
              activeColor: Colors.red,
              title: Text('I want to delete this item',
                  style: TextStyle(color: widget.textColor, fontSize: 13)),
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: (value) => setState(() => _checked = value ?? false),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: _checked ? () => Navigator.pop(context, true) : null,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
              disabledBackgroundColor: Colors.red.withValues(alpha: .3),
            ),
            child: const Text('Delete'),
          ),
        ],
      );
}
