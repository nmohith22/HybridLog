class SteelGuardrails {
  static final _bulkDelete =
      RegExp(r'\b(all|every|each|both|multiple|several|bulk|everything)\b');
  static final _negatedAction = RegExp(
    r"\b(don't|do not|never|without)\s+(delete|remove|erase|create|add|make|log|record|update|edit|change|rename|modify)\b",
  );
  static final _suggestionInsteadOfAction = RegExp(
    r'\b(what|which)\b.{0,40}\b(should|could|can)\s+i\s+(create|add|make|log|record|save)\b',
  );

  static bool allowsOperation(String request, String operation) {
    final text = request.toLowerCase();
    if (operation == 'read') return true;
    if (_negatedAction.hasMatch(text)) return false;
    if (operation == 'delete') {
      return !_bulkDelete.hasMatch(text) &&
          RegExp(r'\b(delete|remove|erase)\b').hasMatch(text);
    }
    if (operation == 'create') {
      return !_suggestionInsteadOfAction.hasMatch(text) &&
          RegExp(r'\b(create|add|make|log|record|save)\b').hasMatch(text);
    }
    if (operation == 'update') {
      return RegExp(r'\b(update|edit|change|rename|modify)\b').hasMatch(text);
    }
    return false;
  }

  static bool isBulkDeleteRequest(String request) =>
      _bulkDelete.hasMatch(request.toLowerCase());
}
