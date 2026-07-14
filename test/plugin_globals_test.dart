import 'dart:typed_data';

import 'package:dart_eval/dart_eval.dart';
import 'package:dart_eval/dart_eval_bridge.dart';
import 'package:dart_eval/stdlib/core.dart';
import 'package:test/test.dart';

/// These tests document and verify the pattern for providing host-defined
/// global values (e.g. `currententry`, `currentuser`) to scripts through an
/// [EvalPlugin], instead of stitching them into the source before compiling.
///
/// The payoff: the script (plus the plugin's bridge declarations and getter
/// source) is compiled ONCE and can be cached as EVC bytecode. The host values
/// are resolved at runtime through a bridge function, so they can change on
/// every execution without recompiling. Scripts keep the existing syntax
/// (`currententry['quantity'] as int`) unchanged; the only addition is a
/// static import of the plugin's globals library.

/// Wraps a host-side JSON-style map (`Map<String, dynamic>`) for script
/// access. Scripts use indexer syntax (`entry['key']`), `[]=` assignment and
/// `containsKey`, mirroring how a plain Map behaves.
class $HostEntry implements $Instance {
  $HostEntry.wrap(this.$value);

  @override
  final Map<String, dynamic> $value;

  static const $type = BridgeTypeRef(
    BridgeTypeSpec('package:hostdata/hostdata.dart', 'HostEntry'),
  );

  static const $declaration = BridgeClassDef(
    BridgeClassType($type),
    constructors: {},
    methods: {
      '[]': BridgeMethodDef(
        BridgeFunctionDef(
          returns: BridgeTypeAnnotation(
            BridgeTypeRef(CoreTypes.dynamic),
            nullable: true,
          ),
          params: [
            BridgeParameter(
              'key',
              BridgeTypeAnnotation(BridgeTypeRef(CoreTypes.string)),
              false,
            ),
          ],
        ),
      ),
      '[]=': BridgeMethodDef(
        BridgeFunctionDef(
          returns: BridgeTypeAnnotation(BridgeTypeRef(CoreTypes.voidType)),
          params: [
            BridgeParameter(
              'key',
              BridgeTypeAnnotation(BridgeTypeRef(CoreTypes.string)),
              false,
            ),
            BridgeParameter(
              'value',
              BridgeTypeAnnotation(
                BridgeTypeRef(CoreTypes.dynamic),
                nullable: true,
              ),
              false,
            ),
          ],
        ),
      ),
      'containsKey': BridgeMethodDef(
        BridgeFunctionDef(
          returns: BridgeTypeAnnotation(BridgeTypeRef(CoreTypes.bool)),
          params: [
            BridgeParameter(
              'key',
              BridgeTypeAnnotation(BridgeTypeRef(CoreTypes.string)),
              false,
            ),
          ],
        ),
      ),
    },
    getters: {},
    setters: {},
    fields: {},
    wrap: true,
  );

  @override
  $Value? $getProperty(Runtime runtime, String identifier) {
    switch (identifier) {
      case '[]':
        return $Function((rt, target, args) {
          final v = $value[args[0]!.$value as String];
          // Recursively wrap so nested JSON (lists, maps, primitives) is
          // usable from the script with casts like `as List` / `as Map`.
          return rt.wrap(v, recursive: true);
        });
      case '[]=':
        return $Function((rt, target, args) {
          $value[args[0]!.$value as String] = args[1]?.$reified;
          return null;
        });
      case 'containsKey':
        return $Function((rt, target, args) {
          return $bool($value.containsKey(args[0]!.$value as String));
        });
      case 'toString':
        return $Function((rt, target, args) => $String($value.toString()));
    }
    throw UnimplementedError('HostEntry has no property "$identifier"');
  }

  @override
  void $setProperty(Runtime runtime, String identifier, $Value value) {
    throw UnimplementedError();
  }

  @override
  dynamic get $reified => $value;

  @override
  int $getRuntimeType(Runtime runtime) => runtime.lookupType($type.spec!);
}

/// Registers the [$HostEntry] bridge class plus top-level getters
/// (`currententry`, `currentuser`, ...) that resolve host state at runtime.
///
/// The getters live in an [addSource] library so scripts access them as plain
/// top-level identifiers; each access calls the bridged `hostEntry` function,
/// which reads from [entries] — plain Dart state the host can mutate or
/// replace between executions.
class HostDataPlugin implements EvalPlugin {
  HostDataPlugin([Map<String, Map<String, dynamic>>? entries])
    : entries = entries ?? {};

  /// Live host state, keyed by global name. Mutable at any time; scripts see
  /// the current values on their next access, with no recompilation.
  final Map<String, Map<String, dynamic>> entries;

  static const globalNames = [
    'currententry',
    'currentuser',
    'currentrow',
    'parententry',
  ];

  @override
  String get identifier => 'package:hostdata';

  @override
  void configureForCompile(BridgeDeclarationRegistry registry) {
    registry.defineBridgeClass($HostEntry.$declaration);
    registry.defineBridgeTopLevelFunction(
      const BridgeFunctionDeclaration(
        'package:hostdata/hostdata.dart',
        'hostEntry',
        BridgeFunctionDef(
          returns: BridgeTypeAnnotation($HostEntry.$type),
          params: [
            BridgeParameter(
              'key',
              BridgeTypeAnnotation(BridgeTypeRef(CoreTypes.string)),
              false,
            ),
          ],
        ),
      ),
    );
    registry.addSource(
      DartSource('package:hostdata/globals.dart', '''
        import 'package:hostdata/hostdata.dart';
        ${globalNames.map((n) => "HostEntry get $n => hostEntry('$n');").join('\n')}
      '''),
    );
  }

  @override
  void configureForRuntime(Runtime runtime) {
    runtime.registerBridgeFunc('package:hostdata/hostdata.dart', 'hostEntry', (
      rt,
      target,
      args,
    ) {
      final key = args[0]!.$value as String;
      final entry = entries[key];
      if (entry == null) {
        throw ArgumentError('No host entry for "$key"');
      }
      return $HostEntry.wrap(entry);
    });
  }
}

void main() {
  /// Compiles [sources] once with the plugin's compile-time config applied.
  Program compileWithPlugin(Map<String, String> sources) {
    final compiler = Compiler();
    compiler.addPlugin(HostDataPlugin());
    return compiler.compile({'example': sources});
  }

  /// Builds a runtime for [program] whose globals resolve from [entries].
  Runtime runtimeWith(
    Program program,
    Map<String, Map<String, dynamic>> entries,
  ) {
    final runtime = Runtime.ofProgram(program);
    runtime.addPlugin(HostDataPlugin(entries));
    return runtime;
  }

  group('Plugin-provided host globals', () {
    test('backwards-compatible indexer syntax on a plugin global', () {
      final program = compileWithPlugin({
        'main.dart': '''
          import 'package:hostdata/globals.dart';
          int main() {
            var quantity = currententry['quantity'] as int;
            return quantity * 2;
          }
        ''',
      });
      final runtime = runtimeWith(program, {
        'currententry': {'quantity': 21},
      });
      expect(runtime.executeLib('package:example/main.dart', 'main'), 42);
    });

    test('host values change between executions without recompiling', () {
      final program = compileWithPlugin({
        'main.dart': '''
          import 'package:hostdata/globals.dart';
          int main() => currententry['quantity'] as int;
        ''',
      });

      final entry = <String, dynamic>{'quantity': 1};
      final runtime = runtimeWith(program, {'currententry': entry});

      expect(runtime.executeLib('package:example/main.dart', 'main'), 1);
      entry['quantity'] = 999;
      expect(runtime.executeLib('package:example/main.dart', 'main'), 999);
      entry['quantity'] = -5;
      expect(runtime.executeLib('package:example/main.dart', 'main'), -5);
    });

    test('precompiled EVC bytecode is reusable with fresh host state', () {
      final program = compileWithPlugin({
        'main.dart': '''
          import 'package:hostdata/globals.dart';
          int main() {
            var quantity = currententry['quantity'] as int;
            var factor = currentuser['factor'] as int;
            return quantity * factor;
          }
        ''',
      });

      // Serialize once — this is what the host application would cache.
      final Uint8List cached = program.write();

      int runFromCache(Map<String, Map<String, dynamic>> entries) {
        final runtime = Runtime(ByteData.sublistView(cached));
        runtime.addPlugin(HostDataPlugin(entries));
        return runtime.executeLib('package:example/main.dart', 'main') as int;
      }

      expect(
        runFromCache({
          'currententry': {'quantity': 6},
          'currentuser': {'factor': 7},
        }),
        42,
      );
      expect(
        runFromCache({
          'currententry': {'quantity': 3},
          'currentuser': {'factor': 5},
        }),
        15,
      );
    });

    test('scripts can write back to host state with []=', () {
      final program = compileWithPlugin({
        'main.dart': '''
          import 'package:hostdata/globals.dart';
          void main() {
            var quantity = currententry['quantity'] as int;
            currententry['total'] = quantity * 3;
            currententry['note'] = 'computed';
          }
        ''',
      });

      final entry = <String, dynamic>{'quantity': 14};
      final runtime = runtimeWith(program, {'currententry': entry});
      runtime.executeLib('package:example/main.dart', 'main');

      expect(entry, {'quantity': 14, 'total': 42, 'note': 'computed'});
    });

    test('nested JSON values: lists, maps, null and containsKey', () {
      final program = compileWithPlugin({
        'main.dart': r'''
          import 'package:hostdata/globals.dart';
          String main() {
            final tags = currententry['tags'] as List;
            final meta = currententry['meta'] as Map;
            final missing = currententry['nope'];
            final has = currententry.containsKey('meta');
            return '${tags.length}:${tags[1]}:${meta['unit']}:$missing:$has';
          }
        ''',
      });

      final runtime = runtimeWith(program, {
        'currententry': {
          'tags': ['a', 'b', 'c'],
          'meta': {'unit': 'kg', 'depth': 2},
        },
      });
      expect(
        runtime.executeLib('package:example/main.dart', 'main'),
        $String('3:b:kg:null:true'),
      );
    });

    test('globals are accessible from every module that imports them', () {
      final program = compileWithPlugin({
        'helper.dart': '''
          import 'package:hostdata/globals.dart';
          String userName() => currentuser['name'] as String;
          int rowIndex() => currentrow['index'] as int;
        ''',
        'main.dart': '''
          import 'package:hostdata/globals.dart';
          import 'package:example/helper.dart';
          String main() {
            final parent = parententry['id'] as String;
            return '\${userName()}/\${rowIndex()}/\$parent';
          }
        ''',
      });

      final runtime = runtimeWith(program, {
        'currentuser': {'name': 'stefan'},
        'currentrow': {'index': 3},
        'parententry': {'id': 'E-100'},
      });
      expect(
        runtime.executeLib('package:example/main.dart', 'main'),
        $String('stefan/3/E-100'),
      );
    });

    test('string values and interpolation keep working unchanged', () {
      final program = compileWithPlugin({
        'main.dart': r'''
          import 'package:hostdata/globals.dart';
          String main() {
            var name = currententry['name'] as String;
            var quantity = currententry['quantity'] as int;
            return '$name x$quantity';
          }
        ''',
      });

      final runtime = runtimeWith(program, {
        'currententry': {'name': 'Widget', 'quantity': 4},
      });
      expect(
        runtime.executeLib('package:example/main.dart', 'main'),
        $String('Widget x4'),
      );
    });
  });
}
