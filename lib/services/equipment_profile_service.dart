import 'package:shared_preferences/shared_preferences.dart';

class EquipmentProfileService {
  static const _key = 'unavailableEquipment';

  static const categories = [
    'Barbell',
    'Dumbbells',
    'Bench',
    'Cable machine',
    'Weight machine',
    'Pull-up bar',
  ];

  static Future<Set<String>> loadUnavailable() async {
    final preferences = await SharedPreferences.getInstance();
    return (preferences.getStringList(_key) ?? const [])
        .where(categories.contains)
        .toSet();
  }

  static Future<void> saveUnavailable(Iterable<String> categories) async {
    final values =
        categories.where(EquipmentProfileService.categories.contains).toSet();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(_key, values.toList()..sort());
  }

  static List<String> categoriesForExercise(String name) {
    final value = name.toLowerCase();
    final required = <String>{};
    if (value.contains('cable') || value.contains('pulldown')) {
      required.add('Cable machine');
    }
    if (value.contains('machine') ||
        value.contains('pec deck') ||
        value.contains('smith') ||
        value.contains('leg press') ||
        value.contains('leg extension') ||
        value.contains('leg curl') ||
        value.contains('hammer strength') ||
        value.contains('life fitness') ||
        value.contains('hoist')) {
      required.add('Weight machine');
    }
    if (value.contains('barbell')) required.add('Barbell');
    if (value.contains('dumbbell')) required.add('Dumbbells');
    if (value.contains('bench')) required.add('Bench');
    if (value.contains('pull-up') ||
        value.contains('pull up') ||
        value.contains('chin-up')) {
      required.add('Pull-up bar');
    }
    return required.toList();
  }
}
