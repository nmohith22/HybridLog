import re

with open('lib/screens/running_screen.dart', 'r', encoding='utf-8') as f:
    code = f.read()

# 1. Imports
code = code.replace("import '../main.dart';", "import '../main.dart';\nimport '../services/tutorial_service.dart';")

# 2. State variables
state_vars = '''
  final GlobalKey _runningGraphKey = GlobalKey();
  final GlobalKey _swipeNavKey = GlobalKey();
  final GlobalKey _settingsKey = GlobalKey();

  @override
'''
code = code.replace("  @override\n  void initState() {", state_vars + "  void initState() {")

# 3. initState additions
init_add = '''
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkTutorial();
    });
  }

  Future<void> _checkTutorial() async {
    bool hasSeen = await TutorialService.hasSeenTutorial();
    if (!hasSeen && mounted) {
      TutorialService.showMainTutorial(
        context: context,
        runningGraphKey: _runningGraphKey,
        settingsKey: _settingsKey,
        swipeNavKey: _swipeNavKey,
        onFinish: () async {
          await TutorialService.markTutorialSeen();
        }
      );
    }
  }
'''
code = code.replace("    _loadWeather();\n  }", "    _loadWeather();\n" + init_add)


# 4. Settings Dialog - just add the button!
settings_append = '''
              const Divider(color: Colors.black12),
              ListTile(
                leading: const Icon(Icons.school, color: Colors.grey),
                title: Text('Replay Tutorial', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                onTap: () async {
                  Navigator.pop(context);
                  await TutorialService.resetTutorial();
                  _checkTutorial();
                },
              ),
              const ThemePickerWidget(),
'''
code = code.replace("              const ThemePickerWidget(),", settings_append)


# 5. Add keys to widgets
code = code.replace("child: const Icon(Icons.chevron_right, color: Colors.grey, size: 28),", "child: Container(key: _swipeNavKey, child: const Icon(Icons.chevron_right, color: Colors.grey, size: 28)),")
code = code.replace("child: Icon(Icons.settings, color: isDark ? Colors.grey : Colors.black54, size: 22)),", "child: Container(key: _settingsKey, child: Icon(Icons.settings, color: isDark ? Colors.grey : Colors.black54, size: 22))),")
code = code.replace("child: RunningBlockGraph(", "child: Container(\n                      key: _runningGraphKey,\n                      child: RunningBlockGraph(")
code = code.replace("setState(() => _isGraphInteracting = isInteracting);\n                      },\n                    ),", "setState(() => _isGraphInteracting = isInteracting);\n                      },\n                    ),\n                    ),")

with open('lib/screens/running_screen.dart', 'w', encoding='utf-8') as f:
    f.write(code)
