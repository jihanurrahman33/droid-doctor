import '../model/finding.dart';
import '../plugins/plugin_auditor.dart';
import '../report/plugins_reporter.dart';
import 'runner.dart';

final class PluginsCommand extends ProjectCommand {
  PluginsCommand(super.context) {
    argParser
      ..addFlag('json', negatable: false, help: 'Print JSON output.')
      ..addFlag('offline',
          negatable: false,
          help: "Don't look up newer plugin versions on pub.dev.")
      ..addFlag('ci',
          negatable: false,
          help: 'Exit with code 1 on warnings too, and disable colors.');
  }

  @override
  String get name => 'plugins';

  @override
  String get description =>
      "Find plugins whose Android build blocks or breaks the app's build.";

  @override
  Future<int> run() async {
    final matrix = loadMatrix();
    final project = await scanProject();
    if (project == null) return ExitCode.usage;

    final List<AndroidPlugin> plugins;
    try {
      plugins = findAndroidPlugins(project.projectPath);
    } on PackagesNotResolvedException catch (e) {
      context.err.writeln(e);
      return ExitCode.usage;
    }

    final auditor = PluginAuditor(project, matrix);
    final audited = [for (final p in plugins) (p, auditor.audit(p))];
    final offline = args.flag('offline');
    Future<PluginReport> report(
            AndroidPlugin plugin, List<Finding> findings) async =>
        PluginReport(
          plugin,
          findings,
          // Only problem plugins need upgrade advice.
          info: offline || findings.isEmpty
              ? null
              : await context.packageInfo(plugin.name),
        );
    final reports = await Future.wait<PluginReport>([
      for (final (plugin, findings) in audited) report(plugin, findings),
    ]);

    final ci = args.flag('ci');
    final summary = [
      if (project.agp != null) 'AGP ${project.agp!.value}',
      if (auditor.appMinSdk != null) 'minSdk ${auditor.appMinSdk}',
      if (auditor.appCompileSdk != null) 'compileSdk ${auditor.appCompileSdk}',
    ].join(' · ');
    context.out.write(args.flag('json')
        ? '${renderPluginsJson(reports)}\n'
        : renderPlugins(reports, context: summary, color: !ci && color));

    final failing = reports.where((r) =>
        r.worst == Severity.error || (ci && r.worst == Severity.warning));
    return failing.isEmpty ? ExitCode.ok : ExitCode.problems;
  }
}
