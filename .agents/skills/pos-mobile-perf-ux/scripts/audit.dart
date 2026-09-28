// ignore_for_file: avoid_print
// POS static perf/UX audit. Heuristic only: a hit is a lead, not a verdict.
// Run from the Flutter project root:
//   dart run .agents/skills/pos-mobile-perf-ux/scripts/audit.dart [lib]
import 'dart:io';

class Rule {
  Rule(this.id, this.severity, this.pattern, this.why, {this.unless});
  final String id;
  final String severity; // HIGH | MED | INFO
  final RegExp pattern;
  final String why;
  final RegExp? unless; // if this matches in the next 8 lines, ignore the hit
}

List<String>? _read(File f) {
  try {
    return f.readAsLinesSync();
  } catch (_) {
    return null;
  }
}

void main(List<String> args) {
  if (args.contains('--help') || args.contains('-h')) {
    print('POS static perf/UX audit (heuristic, read-only).');
    print('Usage: dart run <path-to>/audit.dart [directory, default: lib]');
    print('Prints HIGH/MED/INFO leads as file:line, plus setState density and large files.');
    return;
  }
  final root = Directory(args.isNotEmpty ? args.first : 'lib');
  if (!root.existsSync()) {
    print('Directory not found: ${root.path}. Run from the Flutter project root.');
    exit(2);
  }

  final rules = <Rule>[
    Rule('shrinkwrap', 'HIGH', RegExp(r'shrinkWrap:\s*true'),
        'Lays out the whole list at once; defeats virtualization. Use slivers / CustomScrollView.'),
    Rule('intrinsic', 'HIGH', RegExp(r'\bIntrinsic(Height|Width)\b'),
        'Extra layout pass, quadratic when nested. Use fixed sizes or Table.'),
    Rule('eager-list', 'HIGH', RegExp(r'\b(ListView|GridView)(\.count|\.extent)?\('),
        'Non-builder list builds every child up front. Use .builder / .separated for data-driven lists.'),
    Rule('savelayer', 'HIGH', RegExp(r'\b(BackdropFilter|ShaderMask|ColorFiltered)\('),
        'Offscreen layer per frame; very costly on low-end GPUs.'),
    Rule('future-in-build', 'HIGH', RegExp(r'\b(future|stream):\s*[\w.]+\('),
        'Future/Stream created inline restarts on every rebuild. Create once (initState / controller).'),
    Rule('image-nocache', 'HIGH', RegExp(r'\bImage\.(network|file|memory)\('),
        'Decodes at full resolution. Set cacheWidth/cacheHeight or use ResizeImage.',
        unless: RegExp(r'cacheWidth|cacheHeight|ResizeImage')),
    Rule('money-double', 'HIGH',
        RegExp(r'\bdouble\??\s+\w*(price|total|amount|cost|tax|discount|change|balance|payment|tendered)\w*',
            caseSensitive: false),
        'Floating point money drifts. Use integer minor units (centavos).'),
    Rule('single-scroll', 'MED', RegExp(r'SingleChildScrollView'),
        'If its Column holds a dynamic list, every row is built. Use SliverList.'),
    Rule('opacity', 'MED', RegExp(r'\bOpacity\('),
        'Can force saveLayer. Prefer FadeTransition / AnimatedOpacity or alpha in the color.'),
    Rule('clip-savelayer', 'MED', RegExp(r'Clip\.antiAliasWithSaveLayer'),
        'Explicit saveLayer clip. Use Clip.hardEdge or antiAlias.'),
    Rule('mediaquery-of', 'MED', RegExp(r'MediaQuery\.of\('),
        'Rebuilds on any MediaQuery change (keyboard). Use MediaQuery.sizeOf / paddingOf / viewInsetsOf.'),
    Rule('jsondecode', 'MED', RegExp(r'\bjsonDecode\('),
        'Large payloads decode on the UI isolate. Use Isolate.run above ~50 KB.'),
    Rule('select-all', 'MED', RegExp(r'''\.select\(\s*(['"]\*['"])?\s*\)'''),
        'Fetches every column. List columns explicitly and paginate.'),
    Rule('polling', 'MED', RegExp(r'\b(Timer|Stream)\.periodic\('),
        'Polling burns battery and multiplies server load by device count.'),
    Rule('big-shadow', 'INFO', RegExp(r'BoxShadow\('),
        'Blurred shadows repeated per list item cost raster time. Prefer a border in lists.'),
    Rule('drift-watch', 'INFO', RegExp(r'\.watch(Single)?\('),
        'Every write to a watched table re-runs the query. Keep it narrow and limited.'),
    Rule('print', 'INFO', RegExp(r'(^|[^\w.])print\('),
        'print() is not stripped in release. Use debugPrint behind kDebugMode or a logger.'),
  ];

  final files = root
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) =>
          f.path.endsWith('.dart') &&
          !f.path.endsWith('.g.dart') &&
          !f.path.endsWith('.freezed.dart'))
      .toList();

  final hits = <String, List<String>>{for (final r in rules) r.id: <String>[]};
  final setStateCount = <String, int>{};
  final largeFiles = <String, int>{};

  for (final f in files) {
    final lines = _read(f);
    if (lines == null) continue;
    final path = f.path.replaceAll('\\', '/');
    if (lines.length > 400) largeFiles[path] = lines.length;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trimLeft();
      if (trimmed.startsWith('//')) continue;
      if (line.contains('setState(')) {
        setStateCount[path] = (setStateCount[path] ?? 0) + 1;
      }
      for (final r in rules) {
        if (!r.pattern.hasMatch(line)) continue;
        if (r.unless != null) {
          final end = (i + 8 < lines.length) ? i + 8 : lines.length - 1;
          final window = lines.sublist(i, end + 1).join('\n');
          if (r.unless!.hasMatch(window)) continue;
        }
        final shown = trimmed.length > 90 ? trimmed.substring(0, 90) : trimmed;
        hits[r.id]!.add('$path:${i + 1}  $shown');
      }
    }
  }

  print('# POS static audit (files: ${files.length}, root: ${root.path})');
  print('Heuristic only. A hit is a lead, not a verdict. Zero hits does NOT mean fast:');
  print('measure with --profile on a real low-end device.\n');

  final totals = <String, int>{'HIGH': 0, 'MED': 0, 'INFO': 0};
  for (final sev in ['HIGH', 'MED', 'INFO']) {
    for (final r in rules.where((r) => r.severity == sev)) {
      final list = hits[r.id]!;
      if (list.isEmpty) continue;
      totals[sev] = totals[sev]! + list.length;
      print('## [$sev] ${r.id} (${list.length})');
      print('Why: ${r.why}');
      for (final h in list.take(25)) {
        print('  $h');
      }
      if (list.length > 25) print('  ... ${list.length - 25} more');
      print('');
    }
  }

  final ss = setStateCount.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  if (ss.isNotEmpty) {
    print('## setState() density, top 10 (high counts suggest wide rebuilds)');
    for (final e in ss.take(10)) {
      print('  ${e.value.toString().padLeft(4)}  ${e.key}');
    }
    print('');
  }
  if (largeFiles.isNotEmpty) {
    print('## Files over 400 lines (review for oversized build methods)');
    final lf = largeFiles.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final e in lf.take(10)) {
      print('  ${e.value.toString().padLeft(5)}  ${e.key}');
    }
    print('');
  }
  print('Totals: HIGH=${totals['HIGH']} MED=${totals['MED']} INFO=${totals['INFO']}');
}
