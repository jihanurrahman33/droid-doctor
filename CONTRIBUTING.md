# Contributing to droid_doctor

Thanks for helping. Bug reports with a project or a build log that reproduces
the problem are the most useful contribution.

## Setup

```sh
git clone https://github.com/jihanurrahman33/droid-doctor
cd droid-doctor
dart pub get
```

Before you open a pull request, these must pass:

```sh
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos
dart test
```

CI runs the tests on Linux, macOS and Windows, with the minimum Dart (3.6) and
the latest stable.

## Layout

| Path | What it holds |
|---|---|
| `bin/`, `lib/src/cli/` | The command-line entry point and commands |
| `lib/src/detect/` | Reads versions from Gradle files |
| `lib/src/rules/` | The compatibility checks |
| `lib/src/fix/` | The solver and the verified single-line edits |
| `lib/src/explain/` | Patterns that recognize build errors |
| `data/matrix.json` | The compatibility data, with a source link on every rule |
| `tool/` | The data update and embed scripts |
| `test/fixtures/` | Small Android projects used by the tests |

## Compatibility data

- Don't edit `lib/src/data/bundled_matrix.g.dart` by hand. After changing
  `data/matrix.json`, run `dart run tool/embed_matrix.dart`.
- Every rule needs a source link. Add the rule to `data/matrix.json`, a test
  for it, and raise `unknownFrom` only once the new releases are covered.
- A weekly workflow refreshes the data and opens a pull request that lists
  what a person has to review.

## Tests

- A test that asserts the exact versions the solver picks must use
  `snapshotMatrix()` from `test/hermetic.dart`, never `CompatMatrix.bundled()`.
  The bundled data changes with every refresh, and tests that read it broke the
  weekly update before.
- Add a fixture under `test/fixtures/` for a new kind of project.

## Commits and pull requests

- Short, imperative commit subjects, for example `Fix Windows path handling`.
- One change per pull request, with a note on how you tested it. Mention the
  Flutter, Gradle, AGP and Kotlin versions of any project you ran it on.
- Update `CHANGELOG.md` for anything a user would notice.

## Releasing (maintainer)

1. Update `version` in `pubspec.yaml` and `packageVersion` in
   `lib/src/cli/version.dart` (a test checks that they match), and add the
   changelog entry.
2. Merge to `main`, then push a tag: `git tag -a vX.Y.Z -m "droid_doctor X.Y.Z"`
   and `git push origin vX.Y.Z`. The Release workflow builds the binaries and
   the GitHub release. With the `PUB_DEV_PUBLISH` variable set to `true`, the
   Publish workflow also publishes to pub.dev.
3. Move the `v1` tag that the GitHub Action reference uses:
   `git tag -f v1 vX.Y.Z && git push -f origin v1`.

## Reporting a security issue

See [SECURITY.md](SECURITY.md). Please don't open a public issue.
