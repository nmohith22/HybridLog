# HybridLog repository instructions

## Test gate

- Run the full test suite locally before building a release APK or running `git push`. Test the same code and test inputs that will be built or pushed.
- Run `flutter test --reporter expanded` with `HYBRIDLOG_NEEDLE_QA` set to the compatible Needle CLI so the Steel CRUD test uses the bundled model. Use the runtime revision pinned in [the release workflow](.github/workflows/release-apk.yml).
- Install the dependencies from `evals/requirements.txt` and run `pytest -q evals` with `RAGAS_DO_NOT_TRACK=true` and Flutter's `dart` on PATH.
- Proceed only after both suites pass. If a check fails or cannot run, resolve the issue and rerun the checks before building or pushing. GitHub Actions repeats these checks before publishing.
