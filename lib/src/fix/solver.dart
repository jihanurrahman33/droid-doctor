import '../data/compat_matrix.dart';
import '../model/component.dart';
import '../model/finding.dart';
import '../model/project_snapshot.dart';
import '../model/version.dart';
import '../rules/compatibility_rules.dart';

enum Strategy {
  /// Fix errors (and Kotlin support-range warnings) with the smallest
  /// upgrades.
  minimal,

  /// Upgrade to the newest known versions (what `flutter create` generates).
  latest,
}

/// The components `fix` can change. The JDK is installed software, not a
/// project setting, so it is a constraint rather than a choice.
const solvableComponents = [Component.gradle, Component.agp, Component.kgp];

/// The chosen versions, and what still cannot be fixed by upgrading.
final class Solution {
  const Solution({required this.targets, required this.unresolved});

  /// Target version per component; only components that change.
  final Map<Component, Version> targets;

  /// Errors that remain even with [targets] (e.g. the JDK is too old).
  final List<Finding> unresolved;
}

/// Picks Gradle/AGP/KGP versions that satisfy every compatibility rule and
/// the Flutter release's minimums. Never downgrades.
final class Solver {
  const Solver(this.matrix);

  final CompatMatrix matrix;

  Solution solve(ProjectSnapshot project,
      {Strategy strategy = Strategy.minimal}) {
    final best = _search(project, strategy);
    if (best != null && best.errors == 0) {
      return Solution(targets: best.changes, unresolved: const []);
    }
    // No upgrade satisfies the current JDK: solve as if the JDK were right,
    // then report what the JDK must change to.
    final withoutJdk = _search(project.withVersions(clearJava: true), strategy);
    final changes = withoutJdk?.changes ?? best?.changes ?? const {};
    final upgraded = _apply(project, changes);
    return Solution(
      targets: changes,
      unresolved: [
        for (final f in _evaluate(upgraded))
          if (f.severity == Severity.error) f,
      ],
    );
  }

  ({Map<Component, Version> changes, int errors})? _search(
    ProjectSnapshot project,
    Strategy strategy,
  ) {
    final domains = {
      for (final c in solvableComponents)
        if (project.version(c) case final current?)
          c: _domain(c, current.value),
    };
    final components = domains.keys.toList();

    _Candidate? best;
    void visit(int index, Map<Component, int> picks) {
      if (index == components.length) {
        final changes = {
          for (final c in components)
            if (picks[c]! > 0) c: domains[c]![picks[c]!],
        };
        final findings = _evaluate(_apply(project, changes));
        final candidate = _Candidate(
          changes: changes,
          errors: findings.where((f) => f.severity == Severity.error).length,
          warnings:
              findings.where((f) => f.severity == Severity.warning).length,
          rankSum: picks.values.fold(0, (a, b) => a + b),
        );
        if (best == null || candidate.betterThan(best!, strategy)) {
          best = candidate;
        }
        return;
      }
      final c = components[index];
      for (var i = 0; i < domains[c]!.length; i++) {
        visit(index + 1, {...picks, c: i});
      }
    }

    visit(0, {});
    final found = best;
    return found == null
        ? null
        : (changes: found.changes, errors: found.errors);
  }

  /// The current version followed by every known release above it (index 0 is
  /// "no change").
  List<Version> _domain(Component component, Version current) {
    final unknownFrom = matrix.unknownFrom[component];
    return [
      current,
      for (final v in matrix.releases[component] ?? const <Version>[])
        if (v > current && (unknownFrom == null || v < unknownFrom)) v,
    ];
  }

  ProjectSnapshot _apply(ProjectSnapshot p, Map<Component, Version> changes) {
    Detected<Version>? updated(Component c) {
      final to = changes[c];
      final from = p.version(c);
      return to == null ? null : Detected(to, location: from?.location);
    }

    return p.withVersions(
      gradle: updated(Component.gradle),
      agp: updated(Component.agp),
      kgp: updated(Component.kgp),
      // minSdk is fixed separately; it must not make every candidate fail.
      clearMinSdk: true,
    );
  }

  /// Errors from compatibility and Flutter minimums, plus Kotlin
  /// support-range warnings. Flutter's "will be removed soon" warnings are
  /// left out so `minimal` doesn't force a major AGP upgrade.
  List<Finding> _evaluate(ProjectSnapshot p) => [
        ...const CompatibilityRule().check(p, matrix),
        for (final f in const FlutterRequirementsRule().check(p, matrix))
          if (f.severity == Severity.error) f,
      ];
}

final class _Candidate {
  const _Candidate({
    required this.changes,
    required this.errors,
    required this.warnings,
    required this.rankSum,
  });

  final Map<Component, Version> changes;
  final int errors;
  final int warnings;

  /// Sum of each pick's position above the current version.
  final int rankSum;

  bool betterThan(_Candidate other, Strategy strategy) {
    if (errors != other.errors) return errors < other.errors;
    if (warnings != other.warnings) return warnings < other.warnings;
    return switch (strategy) {
      Strategy.minimal => changes.length != other.changes.length
          ? changes.length < other.changes.length
          : rankSum < other.rankSum,
      Strategy.latest => rankSum > other.rankSum,
    };
  }
}
