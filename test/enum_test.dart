import 'package:dart_eval/dart_eval.dart';
import 'package:dart_eval/dart_eval_bridge.dart';
import 'package:dart_eval/src/eval/shared/stdlib/core/num.dart';
import 'package:test/test.dart';

void main() {
  group('Enum tests', () {
    late Compiler compiler;

    setUp(() {
      compiler = Compiler();
    });

    test('Basic enum', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            enum MyEnum {
              A, B, C
            }
            int main() {
              return MyEnum.B.index + MyEnum.C.index;
            }
          ''',
        },
      });

      expect(runtime.executeLib('package:example/main.dart', 'main'), 3);
    });

    test('Enum with field', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            enum MyEnum {
              A(1), B(2);
              final int x;
              const MyEnum(this.x);
            }
            int main() {
              return MyEnum.B.index + MyEnum.A.x;
            }
          ''',
        },
      });

      expect(runtime.executeLib('package:example/main.dart', 'main'), 2);
    });

    test('Enum equality', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            enum MyEnum {
              A, B, C
            }
            void main() {
              print(MyEnum.B == MyEnum.C);
              print(MyEnum.B == MyEnum.B);
            }
          ''',
        },
      });

      expect(
        () => runtime.executeLib('package:example/main.dart', 'main'),
        prints('false\ntrue\n'),
      );
    });

    test('Enum boxing error', () {
      final compiler2 = Compiler();
      compiler2.defineBridgeEnum(
        BridgeEnumDef(
          BridgeTypeRef(
            BridgeTypeSpec('package:my_package/show.dart', 'ShowType'),
          ),
          values: ['Movie', 'Series'],
        ),
      );
      final program = compiler2.compile({
        'my_package': {
          'main.dart': r'''
            import 'show.dart';
            class Media {
              Media(this.type, this.url);
              final ShowType type;
              String? url;
            }
            void main() {
              final requiredType = 'movie';
              final type = (requiredType == 'movie') ? 
                ShowType.Movie : ShowType.Series;
              
              final media = Media(type, 'example.com');
              print(media.url);
            }
          ''',
        },
      });
      final runtime = Runtime.ofProgram(program);
      runtime.registerBridgeEnumValues(
        'package:my_package/show.dart',
        'ShowType',
        {'Movie': $int(0), 'Series': $int(1)},
      );
      runtime.executeLib('package:my_package/main.dart', 'main');
    });

    test('Enum value index property from imported file', () {
      const libSource = '''
        enum TestEnum {
          alpha,
          beta
        }
      ''';

      const mainSource = '''
        import 'package:my_test_package/lib.dart';

        int main() {
          return TestEnum.beta.index;
        }
      ''';

      final runtime = compiler.compileWriteAndLoad({
        'my_test_package': {'main.dart': mainSource, 'lib.dart': libSource},
      });

      final result = runtime.executeLib(
        'package:my_test_package/main.dart',
        'main',
      );
      expect(result, 1);
    });

    test('Enum name getter', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            enum Color { red, green, blue }
            void main() {
              print(Color.green.name);
              print(Color.blue.name);
              print(Color.red.index);
            }
          ''',
        },
      });

      expect(() {
        runtime.executeLib('package:example/main.dart', 'main');
      }, prints('green\nblue\n0\n'));
    });

    test('Enum with methods and fields', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            enum Planet {
              earth(5), mars(6);
              final int id;
              const Planet(this.id);
              int doubled() => id * 2;
            }
            void main() {
              print(Planet.mars.doubled());
              print(Planet.earth.id);
            }
          ''',
        },
      });

      expect(() {
        runtime.executeLib('package:example/main.dart', 'main');
      }, prints('12\n5\n'));
    });

    test('Enum values list', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            enum Color { red, green, blue }
            void main() {
              print(Color.values.length);
              print(Color.values[1].name);
              print(Color.values.map((c) => c.name).join(","));
              var s = '';
              for (final c in Color.values) { s += '\${c.index}'; }
              print(s);
            }
          ''',
        },
      });

      expect(() {
        runtime.executeLib('package:example/main.dart', 'main');
      }, prints('3\ngreen\nred,green,blue\n012\n'));
    });

    test('Enum default toString and override', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            enum Color { red, green, blue }
            enum Shape {
              circle, square;
              String toString() => 'a shape';
            }
            void main() {
              print(Color.red.toString());
              print('picked \${Color.green}');
              print(Shape.circle.toString());
            }
          ''',
        },
      });

      expect(() {
        runtime.executeLib('package:example/main.dart', 'main');
      }, prints('Color.red\npicked Color.green\na shape\n'));
    });
  });
}
