import 'package:dart_eval/dart_eval.dart';
import 'package:dart_eval/src/eval/shared/stdlib/core/base.dart';
import 'package:test/test.dart';

void main() {
  group('Patterns', () {
    late Compiler compiler;

    setUp(() {
      compiler = Compiler();
    });

    test('Destructure record with variable declaration pattern', () {
      final runtime = compiler.compileWriteAndLoad({
        'eval_test': {
          'main.dart': r'''
            void main() {
              var data = (1, name: "Elise");
              final (a, :name) = data;
              print(a);
              print(name);
            }
          ''',
        },
      });

      expect(() {
        runtime.executeLib('package:eval_test/main.dart', 'main');
      }, prints('1\nElise\n'));
    });

    test('Destructure record with variable assignment pattern', () {
      final runtime = compiler.compileWriteAndLoad({
        'eval_test': {
          'main.dart': r'''
            void main() {
              var data = (1, name: "Elise");
              int a = 0;
              String name = "";
              (a, :name) = data;
              print(a);
              print(name);
            }
          ''',
        },
      });

      expect(() {
        runtime.executeLib('package:eval_test/main.dart', 'main');
      }, prints('1\nElise\n'));
    });

    test('Destructure record across function boundary', () {
      final runtime = compiler.compileWriteAndLoad({
        'eval_test': {
          'main.dart': r'''
            (int, {String greeting}) getData() {
              return (42, greeting: "Hello");
            }

            void main() {
              final (number, :greeting) = getData();
              print(number);
              print(greeting);
            }
          ''',
        },
      });

      expect(() {
        runtime.executeLib('package:eval_test/main.dart', 'main');
      }, prints('42\nHello\n'));
    });

    test('Destructure list with variable declaration pattern', () {
      final runtime = compiler.compileWriteAndLoad({
        'eval_test': {
          'main.dart': r'''
            void main() {
              var numbers = [1, 2, 3];
              final [first, _, third] = numbers;
              print(first);
              print(third);
            }
          ''',
        },
      });
      expect(() {
        runtime.executeLib('package:eval_test/main.dart', 'main');
      }, prints('1\n3\n'));
    });
  });

  group('Switch pattern tests', () {
    late Compiler compiler;

    setUp(() {
      compiler = Compiler();
    });

    test('Switch matching record pattern', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            String main() {
              var data = (1, name: "Elise");
              switch (data) {
                case (0, name: var n):
                  return "Fail";
                case (1, name: var n):
                  return n + " is the name";
                default:
                  return "Unknown";
              }
            }
          ''',
        },
      });
      expect(
        runtime.executeLib('package:example/main.dart', 'main'),
        $String('Elise is the name'),
      );
    });

    test('Switch matching list pattern', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            String main() {
              var data = [1, 2, 3];
              switch (data) {
                case [1, 2, var x]:
                  return "Matched with x = " + x.toString();
                case [var a, var b]:
                  return "Matched with a = " + a.toString() + ", b = " + b.toString();
                default:
                  return "No match";
              }
            }
          ''',
        },
      });
      expect(
        runtime.executeLib('package:example/main.dart', 'main'),
        $String('Matched with x = 3'),
      );
    });

    test('Switch with pattern guard', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            String main() {
              var data = (1, name: "Elise");
              switch (data) {
                case (var id, name: var n) when id > 5:
                  return n + " has ID " + id.toString();
                default:
                  return "No match";
              }
            }
          ''',
        },
      });
      expect(
        runtime.executeLib('package:example/main.dart', 'main'),
        $String('No match'),
      );
    });

    test('Switch with relational pattern', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            String main() {
              var data = 10;
              switch (data) {
                case >5:
                  return "Greater than 5";
                case <=5:
                  return "5 or less";
                default:
                  return "No match";
              }
            }
          ''',
        },
      });
      expect(
        runtime.executeLib('package:example/main.dart', 'main'),
        $String('Greater than 5'),
      );
    });
  });

  group('If-case pattern tests', () {
    late Compiler compiler;

    setUp(() {
      compiler = Compiler();
    });

    test('If-case with list pattern binding', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            int main() {
              final x = [1, 2];
              if (x case [var a, var b]) return a + b;
              return -1;
            }
          ''',
        },
      });

      expect(runtime.executeLib('package:example/main.dart', 'main'), 3);
    });

    test('If-case with guard and else', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            String classify(int x) {
              if (x case int n when n > 3) return 'big:\$n';
              else return 'small';
            }
            void main() {
              print(classify(5));
              print(classify(2));
            }
          ''',
        },
      });

      expect(() {
        runtime.executeLib('package:example/main.dart', 'main');
      }, prints('big:5\nsmall\n'));
    });

    test('If-case with record and constant patterns', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            void main() {
              final p = (3, 4);
              if (p case (var a, var b)) print(a * b);
              final t = 'user';
              if (t case 'user') print('is-user');
            }
          ''',
        },
      });

      expect(() {
        runtime.executeLib('package:example/main.dart', 'main');
      }, prints('12\nis-user\n'));
    });

    test('If-case that does not match falls through', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            int main() {
              final x = [1, 2, 3];
              if (x case [var a, var b]) return a + b;
              return -1;
            }
          ''',
        },
      });

      expect(runtime.executeLib('package:example/main.dart', 'main'), -1);
    });

    test('Typed variable pattern promotes the bound variable', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            void main() {
              Object o = 7;
              if (o case int n) print(n + 1);
              Object s = 'hello';
              if (s case String str) print(str.length);
              Object r = (1, 'two');
              if (r case (int a, String b)) print(a + b.length);
            }
          ''',
        },
      });

      expect(() {
        runtime.executeLib('package:example/main.dart', 'main');
      }, prints('8\n5\n4\n'));
    });

    test('Typed pattern promotion in switch expression', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            String describe(Object o) => switch (o) {
              int n when n > 10 => 'big-int:\${n + 1}',
              int n => 'int:\${n + 1}',
              double d => 'double:\${d + 0.5}',
              String s => 'string:\${s.length}',
              _ => 'other',
            };
            void main() {
              print(describe(5));
              print(describe(50));
              print(describe(2.0));
              print(describe('abc'));
            }
          ''',
        },
      });

      expect(() {
        runtime.executeLib('package:example/main.dart', 'main');
      }, prints('int:6\nbig-int:51\ndouble:2.5\nstring:3\n'));
    });

    test('Nested list and mixed record/list patterns', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            void main() {
              final grid = [[1, 2], [3, 4]];
              if (grid case [[var a, _], [_, var d]]) print(a + d);
              final deep = [[[5]]];
              if (deep case [[[var v]]]) print(v);
              final listOfRecords = [(1, 2), (3, 4)];
              if (listOfRecords case [(var a, _), (_, var d)]) print(a + d);
              final recordOfLists = ([1, 2], [3, 4]);
              if (recordOfLists case ([var a, _], [_, var d])) print(a + d);
              // inner length mismatch does not match
              final ragged = [[1, 2, 3], [4]];
              if (ragged case [[var a, var b], [var c]]) {
                print(a + b + c);
              } else {
                print('no-match');
              }
            }
          ''',
        },
      });

      expect(() {
        runtime.executeLib('package:example/main.dart', 'main');
      }, prints('5\n5\n5\n5\nno-match\n'));
    });

    test('Pattern guard is not evaluated when the pattern does not match', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            void main() {
              var counter = 0;
              int bump() { counter++; return 100; }
              Object o = 'x';
              // int n binds nothing (o is a String), so the guard - which
              // would misuse the binding and call bump() - must be skipped
              if (o case int n when n > bump()) {
                print('matched');
              }
              print(counter);
            }
          ''',
        },
      });

      expect(() {
        runtime.executeLib('package:example/main.dart', 'main');
      }, prints('0\n'));
    });
  });
}
