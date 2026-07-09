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

  group('List pattern length and rest tests', () {
    late Compiler compiler;

    setUp(() {
      compiler = Compiler();
    });

    test('Wrong-length and null subjects fail cleanly', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            String describe(List<int>? x) {
              if (x case [var a, var b]) return 'two:\${a + b}';
              return 'no';
            }
            void main() {
              print(describe([1, 2]));
              print(describe([1]));       // too short
              print(describe([1, 2, 3])); // too long
              print(describe(<int>[]));   // empty
              print(describe(null));      // null subject
            }
          ''',
        },
      });

      expect(() {
        runtime.executeLib('package:example/main.dart', 'main');
      }, prints('two:3\nno\nno\nno\nno\n'));
    });

    test('Nested list patterns with wrong inner length fail cleanly', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            void main() {
              final ok = [[1, 2], [3, 4]];
              if (ok case [[var a, _], [_, var d]]) print(a + d);
              final ragged = [[1], [3, 4]];
              if (ragged case [[var a, var b], [var c, var d]]) {
                print(a + b + c + d);
              } else {
                print('no-match');
              }
            }
          ''',
        },
      });

      expect(() {
        runtime.executeLib('package:example/main.dart', 'main');
      }, prints('5\nno-match\n'));
    });

    test('Rest elements in list patterns', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            void main() {
              final x = [1, 2, 3, 4, 5];
              if (x case [var a, ...]) print(a);
              if (x case [..., var last]) print(last);
              if (x case [var first, ..., var lastEl]) print(first + lastEl);
              if (x case [_, ...var mid, _]) print(mid.join(","));
              // too short for the required before+after elements
              final short = [1];
              if (short case [var a, ..., var b]) {
                print(a + b);
              } else {
                print('too-short');
              }
            }
          ''',
        },
      });

      expect(() {
        runtime.executeLib('package:example/main.dart', 'main');
      }, prints('1\n5\n6\n2,3,4\ntoo-short\n'));
    });

    test('Named rest binds the whole list and empty middles', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            void main() {
              final x = [1, 2, 3];
              if (x case [...var all]) print(all.join(","));
              final pair = [1, 2];
              if (pair case [var a, ...var mid, var b]) {
                print('\$a-\${mid.length}-\$b');
              }
            }
          ''',
        },
      });

      expect(() {
        runtime.executeLib('package:example/main.dart', 'main');
      }, prints('1,2,3\n1-0-2\n'));
    });
  });

  group('Map pattern tests', () {
    late Compiler compiler;

    setUp(() {
      compiler = Compiler();
    });

    test('Map pattern matches keys and binds values, missing key fails', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': r'''
            String describe(Object o) {
              switch (o) {
                case {'type': 'circle', 'r': int r}:
                  return 'circle r=$r';
                case {'type': 'rect', 'w': int w, 'h': int h}:
                  return 'rect ${w}x$h';
                default:
                  return 'unknown';
              }
            }
            String main() {
              final out = <String>[];
              out.add(describe({'type': 'circle', 'r': 5}));
              out.add(describe({'type': 'rect', 'w': 3, 'h': 4}));
              out.add(describe({'type': 'circle'}));
              out.add(describe({'type': 'triangle', 'r': 1}));
              out.add(describe(42));
              return out.join('|');
            }
          ''',
        },
      });
      expect(
        runtime.executeLib('package:example/main.dart', 'main'),
        $String('circle r=5|rect 3x4|unknown|unknown|unknown'),
      );
    });

    test('Map pattern in irrefutable declaration destructures values', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': r'''
            String main() {
              final m = {'a': 1, 'b': 2, 'c': 3};
              final {'a': x, 'c': z} = m;
              return '$x,$z';
            }
          ''',
        },
      });
      expect(
        runtime.executeLib('package:example/main.dart', 'main'),
        $String('1,3'),
      );
    });
  });

  group('Object pattern tests', () {
    late Compiler compiler;

    setUp(() {
      compiler = Compiler();
    });

    test('Object pattern matches type and destructures getters', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': r'''
            class Point {
              final int x;
              final int y;
              Point(this.x, this.y);
            }
            String describe(Object o) {
              switch (o) {
                case Point(x: 0, y: var y):
                  return 'y-axis at $y';
                case Point(x: var x, y: var y):
                  return 'point $x,$y';
                default:
                  return 'not a point';
              }
            }
            String main() {
              final out = <String>[];
              out.add(describe(Point(0, 9)));
              out.add(describe(Point(2, 3)));
              out.add(describe('hello'));
              return out.join('|');
            }
          ''',
        },
      });
      expect(
        runtime.executeLib('package:example/main.dart', 'main'),
        $String('y-axis at 9|point 2,3|not a point'),
      );
    });

    test('Object pattern with field shorthand and irrefutable destructure', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': r'''
            class Point {
              final int x;
              final int y;
              Point(this.x, this.y);
            }
            String main() {
              final p = Point(7, 8);
              final Point(:x, :y) = p;
              String shorthand = 'nope';
              if (p case Point(:var x)) shorthand = 'x=$x';
              return '$x,$y|$shorthand';
            }
          ''',
        },
      });
      expect(
        runtime.executeLib('package:example/main.dart', 'main'),
        $String('7,8|x=7'),
      );
    });
  });
}
