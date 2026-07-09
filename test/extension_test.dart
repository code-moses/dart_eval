import 'package:dart_eval/dart_eval.dart';
import 'package:dart_eval/src/eval/shared/stdlib/core/base.dart';
import 'package:test/test.dart';

void main() {
  group('Extension methods', () {
    late Compiler compiler;

    setUp(() {
      compiler = Compiler();
    });

    test('Extension method with bare and explicit this member access', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': r'''
            extension StringExt on String {
              String shout() => toUpperCase() + '!';
              String politely() => this.toLowerCase();
            }
            String main() => 'Hi'.shout() + '/' + 'LOUD'.politely();
          ''',
        },
      });
      expect(
        runtime.executeLib('package:example/main.dart', 'main'),
        $String('HI!/loud'),
      );
    });

    test('Extension getter', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': r'''
            extension IntExt on int {
              int get doubled => this * 2;
            }
            int main() => 21.doubled;
          ''',
        },
      });
      expect(runtime.executeLib('package:example/main.dart', 'main'), 42);
    });

    test('Extension method with arguments', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': r'''
            extension IntExt on int {
              int addAll(int a, int b) => this + a + b;
            }
            int main() => 10.addAll(5, 3);
          ''',
        },
      });
      expect(runtime.executeLib('package:example/main.dart', 'main'), 18);
    });

    test('Extension on a script class', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': r'''
            class Box { final int v; Box(this.v); }
            extension BoxExt on Box {
              int squared() => v * v;
            }
            int main() => Box(6).squared();
          ''',
        },
      });
      expect(runtime.executeLib('package:example/main.dart', 'main'), 36);
    });

    test('Extension member calls another extension member', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': r'''
            extension StrExt on String {
              String shout() => loud() + '!';
              String loud() => toUpperCase();
            }
            String main() => 'hi'.shout();
          ''',
        },
      });
      expect(
        runtime.executeLib('package:example/main.dart', 'main'),
        $String('HI!'),
      );
    });

    test('Instance method takes precedence over extension', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': r'''
            class C { String greet() => 'instance'; }
            extension CExt on C {
              String greet() => 'extension';
            }
            String main() => C().greet();
          ''',
        },
      });
      expect(
        runtime.executeLib('package:example/main.dart', 'main'),
        $String('instance'),
      );
    });

    test('Chained extension getters', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': r'''
            extension IntExt on int {
              int get inc => this + 1;
            }
            int main() => 5.inc.inc.inc;
          ''',
        },
      });
      expect(runtime.executeLib('package:example/main.dart', 'main'), 8);
    });

    test('Unnamed extension', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': r'''
            extension on int {
              int get cubed => this * this * this;
            }
            int main() => 3.cubed;
          ''',
        },
      });
      expect(runtime.executeLib('package:example/main.dart', 'main'), 27);
    });

    test('Extension defined in an imported library', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'ext.dart': r'''
            extension StringExt on String {
              String shout() => toUpperCase() + '!';
              int get twice => length * 2;
            }
          ''',
          'main.dart': r'''
            import 'ext.dart';
            String main() => 'hi'.shout() + '/' + 'abc'.twice.toString();
          ''',
        },
      });
      expect(
        runtime.executeLib('package:example/main.dart', 'main'),
        $String('HI!/6'),
      );
    });
  });
}
