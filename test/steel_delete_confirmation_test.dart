import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_app/widgets/steel_delete_confirmation_dialog.dart';

void main() {
  Future<Completer<bool?>> openDeleteDialog(WidgetTester tester) async {
    final result = Completer<bool?>();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result.complete(await SteelDeleteConfirmationDialog.show(
                context,
                summary: 'Delete Tuesday run.',
                cardColor: Colors.white,
                textColor: Colors.black,
                secondaryTextColor: Colors.grey,
              ));
            },
            child: const Text('Open deletion confirmation'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Open deletion confirmation'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('delete starts disabled and red X cancels', (tester) async {
    final result = await openDeleteDialog(tester);
    final delete = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Delete'),
    );
    expect(delete.onPressed, isNull);
    expect(find.byTooltip('Cancel deletion'), findsOneWidget);
    expect(
      tester
          .widget<Icon>(find.descendant(
            of: find.byTooltip('Cancel deletion'),
            matching: find.byIcon(Icons.close),
          ))
          .color,
      Colors.red,
    );

    await tester.tap(find.byTooltip('Cancel deletion'));
    await tester.pumpAndSettle();
    expect(await result.future, false);
    expect(find.text('Confirm deletion'), findsNothing);
  });

  testWidgets('delete only proceeds after the checkbox is checked',
      (tester) async {
    final result = await openDeleteDialog(tester);
    await tester.tap(find.text('I want to delete this item'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Delete'))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(await result.future, true);
    expect(find.text('Confirm deletion'), findsNothing);
  });
}
