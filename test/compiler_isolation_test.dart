import 'package:dart_eval/dart_eval.dart';
import 'package:dart_eval/stdlib/core.dart';
import 'package:test/test.dart';

// Regression tests for cross-compilation state leakage. TypeRef used to keep
// a static resolution cache keyed by numeric library ID, so a type resolved
// in one compilation could leak into a later compilation where the same
// library ID + class name mapped to a different hierarchy, crashing
// TypeRef.getRuntimeIndices with a null check error.
void main() {
  group('Compiler isolation', () {
    test(
      'sequential compilations with conflicting class hierarchies',
      () {
        final runtime1 = Compiler().compileWriteAndLoad({
          'example': {
            'main.dart': '''
            class Base {
              int value() => 1;
            }
            class Foo extends Base {}
            int main() => Foo().value();
            ''',
          },
        });
        expect(
          runtime1.executeLib('package:example/main.dart', 'main'),
          1,
        );

        // Same package, file, and class name, but Foo no longer has a
        // superclass named Base; a stale cached resolution of Foo would
        // reference a type this compilation never registered.
        final runtime2 = Compiler().compileWriteAndLoad({
          'example': {
            'main.dart': '''
            class Foo {
              int value() => 2;
            }
            int main() => Foo().value();
            ''',
          },
        });
        expect(
          runtime2.executeLib('package:example/main.dart', 'main'),
          2,
        );
      },
    );

    test('recompiling with the same Compiler instance', () {
      final compiler = Compiler();
      final runtime1 = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
          class Base {
            int value() => 1;
          }
          class Foo extends Base {}
          int main() => Foo().value();
          ''',
        },
      });
      expect(
        runtime1.executeLib('package:example/main.dart', 'main'),
        1,
      );

      final runtime2 = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
          class Foo {
            int value() => 2;
          }
          int main() => Foo().value();
          ''',
        },
      });
      expect(
        runtime2.executeLib('package:example/main.dart', 'main'),
        2,
      );
    });

    test('compiling while another program\'s async code is running', () async {
      final runtimeA = Compiler().compileWriteAndLoad({
        'example': {
          'main.dart': '''
          class Base {
            int value() => 1;
          }
          class Foo extends Base {}
          Future<int> main() async {
            await Future.delayed(Duration(milliseconds: 100));
            return Foo().value();
          }
          ''',
        },
      });
      final futureA =
          runtimeA.executeLib('package:example/main.dart', 'main') as Future;

      // Compile and start program B while program A is suspended on its
      // timer, so both async programs are in flight simultaneously.
      final runtimeB = Compiler().compileWriteAndLoad({
        'example': {
          'main.dart': '''
          class Foo {
            int value() => 2;
          }
          Future<int> main() async {
            await Future.delayed(Duration(milliseconds: 20));
            return Foo().value();
          }
          ''',
        },
      });
      final futureB =
          runtimeB.executeLib('package:example/main.dart', 'main') as Future;

      final results = await Future.wait([futureA, futureB]);
      expect(results, [$int(1), $int(2)]);
    });
  });
}
