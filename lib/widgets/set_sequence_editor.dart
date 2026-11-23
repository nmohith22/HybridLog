import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/fitness_schema.dart';

class SetSequenceEditor extends StatelessWidget {
  final SetLog set;
  final VoidCallback onChanged;
  final Future<Exercise?> Function() chooseExercise;

  const SetSequenceEditor({
    super.key,
    required this.set,
    required this.onChanged,
    required this.chooseExercise,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 16, top: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final step in set.subSets)
          Padding(
            key: ObjectKey(step),
            padding: const EdgeInsets.symmetric(vertical: 4),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                    child: Text(
                  step.exerciseName != null
                      ? 'Superset · ${step.exerciseName}'
                      : step.pauseSeconds != null
                          ? 'Rest-pause'
                          : 'Dropset',
                  style: TextStyle(
                      color: colors.onSurface, fontWeight: FontWeight.w600),
                )),
                IconButton(
                  tooltip: 'Remove step',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    set.subSets.remove(step);
                    onChanged();
                  },
                ),
              ]),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (step.pauseSeconds != null) ...[
                  Expanded(
                      child: _number(
                          'Seconds',
                          step.pauseSeconds.toString(),
                          (value) => step.pauseSeconds =
                              int.tryParse(value)?.clamp(0, 60) ?? 0,
                          maxLength: 2,
                          validator: (value) =>
                              (int.tryParse(value ?? '') ?? 0) > 60
                                  ? 'Max 60'
                                  : null)),
                  const SizedBox(width: 8),
                ],
                Expanded(
                    child: _number(
                        'Weight',
                        step.weight == 0
                            ? ''
                            : step.weight
                                .toString()
                                .replaceFirst(RegExp(r'\.0$'), ''),
                        (value) => step.weight = double.tryParse(value) ?? 0,
                        decimal: true)),
                const SizedBox(width: 8),
                Expanded(
                    child: _number(
                        'Reps',
                        step.reps == 0 ? '' : step.reps.toString(),
                        (value) => step.reps = int.tryParse(value) ?? 0,
                        maxLength: 4)),
              ]),
            ]),
          ),
        Wrap(spacing: 4, children: [
          TextButton(
              onPressed: () {
                set.subSets.add(SubSetLog());
                onChanged();
              },
              child: const Text('Add dropset')),
          TextButton(
              onPressed: () {
                set.subSets.add(SubSetLog()
                  ..pauseSeconds = 15
                  ..weight = set.subSets.lastOrNull?.weight ?? set.weight);
                onChanged();
              },
              child: const Text('Add rest-pause')),
          TextButton(
              onPressed: () async {
                final exercise = await chooseExercise();
                if (!context.mounted || exercise == null) return;
                set.subSets.add(SubSetLog()
                  ..exerciseName = exercise.name
                  ..targetMuscles = (exercise.targetMuscles.isEmpty
                          ? [exercise.targetMuscle]
                          : exercise.targetMuscles)
                      .toList()
                  ..secondaryMuscles = exercise.secondaryMuscles.toList());
                onChanged();
              },
              child: const Text('Add superset')),
        ]),
      ]),
    );
  }

  Widget _number(
    String label,
    String value,
    ValueChanged<String> onChanged, {
    int? maxLength,
    bool decimal = false,
    FormFieldValidator<String>? validator,
  }) =>
      TextFormField(
        initialValue: value,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        inputFormatters: [
          decimal
              ? FilteringTextInputFormatter.allow(
                  RegExp(r'^\d{0,7}(\.\d{0,2})?$'))
              : FilteringTextInputFormatter.digitsOnly,
          if (maxLength != null) LengthLimitingTextInputFormatter(maxLength),
        ],
        onChanged: onChanged,
        validator: validator,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        decoration: InputDecoration(
          labelText: label,
          suffixText: decimal ? 'lb' : null,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          isDense: true,
        ),
      );
}
