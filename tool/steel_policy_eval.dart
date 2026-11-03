import 'dart:convert';
import 'dart:io';

import '../lib/services/steel_guardrails.dart';

Future<void> main() async {
  final decoded = jsonDecode(await stdin.transform(utf8.decoder).join());
  if (decoded is! List) {
    stderr.writeln('Expected a JSON list of Steel policy cases.');
    exitCode = 2;
    return;
  }

  final decisions = <String>[];
  for (final value in decoded) {
    if (value is! Map ||
        value['request'] is! String ||
        value['operation'] is! String) {
      stderr.writeln('Every policy case needs a request and operation.');
      exitCode = 2;
      return;
    }
    final request = value['request'] as String;
    final operation = value['operation'] as String;
    final allowed = SteelGuardrails.allowsOperation(request, operation) &&
        !(operation == 'delete' &&
            SteelGuardrails.isBulkDeleteRequest(request));
    decisions.add(allowed ? 'allow' : 'deny');
  }
  stdout.write(jsonEncode(decisions));
}
