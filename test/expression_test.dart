import 'package:dart_eval/dart_eval.dart';
import 'package:dart_eval/src/eval/shared/stdlib/core/num.dart';
import 'package:test/test.dart';

void main() {
  group('Expression tests', () {
    late Compiler compiler;

    setUp(() {
      compiler = Compiler();
    });

    test('"is" expression', () {
      final runtime = compiler.compileWriteAndLoad({
        'eval_test': {
          'main.dart': '''
            void main() {
              print(1 is int);
              print(2 is! String);
              print([] is List);
              print(RegExp(r'.*') is RegExp);
              print(RegExp(r'.*') is! RegExp);
              print(RegExp(r'.*') is String);
              print(Y() is X);
              print(X() is Y);
            }

            class X {
              X();
            }

            class Y extends X {
              Y();
            }
          ''',
        },
      });

      expect(() {
        runtime.executeLib('package:eval_test/main.dart', 'main');
      }, prints('true\ntrue\ntrue\ntrue\nfalse\nfalse\ntrue\nfalse\n'));
    });

    test('"is" expression with nullable types', () {
      final runtime = compiler.compileWriteAndLoad({
        'eval_test': {
          'main.dart': '''
            void main() {
              final m = {"a": null, "b": "x"};
              print(m["a"] is String?);
              print(m["a"] is String);
              print(m["a"] is! String?);
              print(m["b"] is String?);
              print(m["b"] is String);
              String? s;
              print(s is String);
              print(s is String?);
              s = "hello";
              print(s is String);
              print(s is int?);
            }
          ''',
        },
      });

      expect(() {
        runtime.executeLib('package:eval_test/main.dart', 'main');
      }, prints('true\nfalse\nfalse\ntrue\ntrue\nfalse\ntrue\ntrue\nfalse\n'));
    });

    test('"as" cast with nullable types', () {
      final runtime = compiler.compileWriteAndLoad({
        'eval_test': {
          'main.dart': '''
            void main() {
              final m = {"a": null, "b": "x"};
              print(m["a"] as String?);
              print(m["b"] as String?);
              try {
                print(m["b"] as int?);
              } catch (e) {
                print("cast error");
              }
            }
          ''',
        },
      });

      expect(() {
        runtime.executeLib('package:eval_test/main.dart', 'main');
      }, prints('null\nx\ncast error\n'));
    });

    test('Is with Object type and branch', () {
      final runtime = compiler.compileWriteAndLoad({
        'eval_test': {
          'main.dart': '''
            void main() {
              Object x = 42;
              if (x is int) {
                print(x + 1);
              }
            }
          ''',
        },
      });
      expect(() {
        runtime.executeLib('package:eval_test/main.dart', 'main');
      }, prints('43\n'));
    });

    test('Is num', () {
      final runtime = compiler.compileWriteAndLoad({
        'eval_test': {
          'main.dart': '''
            num main () {
              var myfunc = ([dynamic a, dynamic b = 4]) {
                if(a is num && b is num){
                  return a + b;
                }
                return 0;
              };
              return myfunc(2);
            }
          ''',
        },
      });

      expect(runtime.executeLib('package:eval_test/main.dart', 'main'), $num<num>(6));
    });

    test('Null coalescing operator', () {
      final runtime = compiler.compileWriteAndLoad({
        'eval_test': {
          'main.dart': '''
            void main() {
              print(null ?? 1);
              print(2 ?? 1);
            }
          ''',
        },
      });

      expect(() {
        runtime.executeLib('package:eval_test/main.dart', 'main');
      }, prints('1\n2\n'));
    });

    test('Null coalescing copy method', () {
      final runtime = compiler.compileWriteAndLoad({
        'eval_test': {
          'main.dart': '''
            class X {
              X({required this.a, required this.b});

              final int a;
              final int b;
              X copy({
                int? a,
                int? b,
              }) {
                return X(a: a ?? this.a, b: b ?? this.b);
              }

              toString() => 'X(a: \$a, b: \$b)';
            }

            void main() {
              print(X(a: 1, b: 2).copy(a: 3));
              print(X(a: 1, b: 2).copy(b: 3));
              print(X(a: 1, b: 2).copy(a: 3, b: 4));
            }
          ''',
        },
      });

      expect(() {
        runtime.executeLib('package:eval_test/main.dart', 'main');
      }, prints('X(a: 3, b: 2)\nX(a: 1, b: 3)\nX(a: 3, b: 4)\n'));
    });

    test('Null coalescing assignment', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            void main() {
              var x;
              x ??= 1;
              print(x);
              x ??= 2;
              print(x);
            }
           ''',
        },
      });

      expect(() {
        runtime.executeLib('package:example/main.dart', 'main');
      }, prints('1\n1\n'));
    });

    test("Not expression", () {
      final runtime = compiler.compileWriteAndLoad({
        'eval_test': {
          'main.dart': '''
            void main() {
              print(!true);
              print(!false);
            }
          ''',
        },
      });

      expect(() {
        runtime.executeLib('package:eval_test/main.dart', 'main');
      }, prints('false\ntrue\n'));
    });

    test('Bitwise int operators', () {
      final runtime = compiler.compileWriteAndLoad({
        'eval_test': {
          'main.dart': '''
            void main() {
              print(1 & 2);
              print(1 | 2);
              print(1 << 2);
              print(1 >> 2);
              print(1 ^ 2);
            }
          ''',
        },
      });

      expect(() {
        runtime.executeLib('package:eval_test/main.dart', 'main');
      }, prints('0\n3\n4\n0\n3\n'));
    });

    test('Conditional expression', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            int main () {
              return fun(3);
            }
            
            int fun(int a) {
              return a > 2 ? 1 : 2;
            }
           ''',
        },
      });

      expect(runtime.executeLib('package:example/main.dart', 'main'), 1);
    });

    test('Simple cascade', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            void main() {
              var x = X();
              x..a = 1..b = 2;
              print(x.a);
              print(x.b);
            }
            
            class X {
              int a = 0;
              int b = 0;
            }
           ''',
        },
      });

      expect(() {
        runtime.executeLib('package:example/main.dart', 'main');
      }, prints('1\n2\n'));
    });

    test('Cascade with method call', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            void main() {
              var x = X();
              x..a = 1..b = 2..printValues();
            }
            
            class X {
              int a = 0;
              int b = 0;
              void printValues() {
                print(a);
                print(b);
              }
            }
           ''',
        },
      });

      expect(() {
        runtime.executeLib('package:example/main.dart', 'main');
      }, prints('1\n2\n'));
    });

    test('Class cast', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            void main() {
              dynamic x = X();
              print((x as X).getName());
            }
            
            class X {
              String getName() => 'X class';
            }
           ''',
        },
      });

      expect(() {
        runtime.executeLib('package:example/main.dart', 'main');
      }, prints('X class\n'));
    });

    test('Num cast', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            void main() {
              num x = 1;
              print((x as int) + 1);
            }
           ''',
        },
      });

      expect(() {
        runtime.executeLib('package:example/main.dart', 'main');
      }, prints('2\n'));
    });

    test('Failing cast', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            void main() {
              dynamic x = X();
              print((x as Y).getName());
            }
            
            class X { String getName() => 'X class'; }
            class Y { String getName() => 'Y class'; }
           ''',
        },
      });

      expect(() {
        runtime.executeLib('package:example/main.dart', 'main');
      }, throwsA(anything));
    });

    test('Null-shorted property access', () {
      final runtime = Compiler().compileWriteAndLoad({
        'example': {
          'main.dart': '''
          void main() {
            X? x;
            print(x?.a);
            x = X();
            print(x?.a);
          }
          
          class X {
            int a = 1;
          }
         ''',
        },
      });

      expect(() {
        runtime.executeLib('package:example/main.dart', 'main');
      }, prints('null\n1\n'));
    });

    test('Null-shorted method call', () {
      final runtime = Compiler().compileWriteAndLoad({
        'example': {
          'main.dart': '''
          void main() {
            X x;
            print(x?.a());
            x = X();
            print(x?.a());
          }

          class X {
            int a() => 1;
          }
         ''',
        },
      });

      expect(() {
        runtime.executeLib('package:example/main.dart', 'main');
      }, prints('null\n1\n'));
    });

    test('Method invocation on null-coalesced dynamic value', () {
      final runtime = compiler.compileWriteAndLoad({
        'eval_test': {
          'main.dart': '''
            void main() {
              dynamic rows = [
                {'faixa_aging': null, 'valor_em_aberto': 10.0},
                {'faixa_aging': '31-60', 'valor_em_aberto': 5.0},
              ];
              for (final row in rows) {
                final faixa = (row['faixa_aging'] ?? 'N/A').toString();
                print(faixa);
              }
            }
          ''',
        },
      });

      expect(() {
        runtime.executeLib('package:eval_test/main.dart', 'main');
      }, prints('N/A\n31-60\n'));
    });

    test("Integer arithmetic on parsed strings", () async {
      final runtime = compiler.compileWriteAndLoad({
        "eval_test": {
          "main.dart": '''
            void main() {
              final currententry = {"StartOnTime": "09:00", "EndOnTime": "10:00"};
              List<String> startParts = currententry["StartOnTime"].toString().split(":");
              List<String> endParts = currententry["EndOnTime"].toString().split(":");
              int startMinutes = int.parse(startParts[0]) * 60 + int.parse(startParts[1]);
              int endMinutes = int.parse(endParts[0]) * 60 + int.parse(endParts[1]);
              print((endMinutes - startMinutes) / 60.0);
            }
          ''',
        },
      });

      // assert
      expect(() {
        runtime.executeLib('package:eval_test/main.dart', 'main');
      }, prints('1.0\n'));
    });

    test("Null-aware operator with string concatenation", () async {
      final runtime = compiler.compileWriteAndLoad({
        "eval_test": {
          "main.dart": '''
            void main() {
              final currententry = {"CustomerEmail": null, "FixedEmail": "mail@example.com"};
              String? mail = currententry["CustomerEmail"] as String?;
              if (!(mail ?? "").contains("@")) {
                print(currententry["FixedEmail"]);
              } else {
                print(mail + ";" + currententry["FixedEmail"]);
              }
            }
          ''',
        },
      });

      // assert
      expect(() {
        runtime.executeLib('package:eval_test/main.dart', 'main');
      }, prints('mail@example.com\n'));
    });

    test('Equality with null operands never invokes operator ==', () {
      final runtime = compiler.compileWriteAndLoad({
        'eval_test': {
          'main.dart': '''
            class A {
              @override
              bool operator ==(Object? other) => true;
            }
            void main() {
              A? a = A();
              print(a == null);
              print(a != null);
              A? b;
              print(b == null);
              print(a == a);
            }
          ''',
        },
      });

      expect(() {
        runtime.executeLib('package:eval_test/main.dart', 'main');
      }, prints('false\ntrue\ntrue\ntrue\n'));
    });

    test('Unary minus on num and dynamic operands', () {
      final runtime = compiler.compileWriteAndLoad({
        'eval_test': {
          'main.dart': '''
            void main() {
              int i = 5;
              print(-i);
              num n = 5;
              print(-n);
              dynamic d = 2.5;
              print(-d);
              dynamic j = -3;
              print(-j);
            }
          ''',
        },
      });

      expect(() {
        runtime.executeLib('package:eval_test/main.dart', 'main');
      }, prints('-5\n-5\n-2.5\n3\n'));
    });

    test('Ternary with mixed boxed branches', () {
      final runtime = compiler.compileWriteAndLoad({
        'eval_test': {
          'main.dart': '''
            void main() {
              final m = {"a": null, "b": "full"};
              print(m["a"] == null ? "empty" : m["a"]);
              print(m["b"] == null ? "empty" : m["b"]);
            }
          ''',
        },
      });

      expect(() {
        runtime.executeLib('package:eval_test/main.dart', 'main');
      }, prints('empty\nfull\n'));
    });

    test('Nested ternary', () {
      final runtime = compiler.compileWriteAndLoad({
        'eval_test': {
          'main.dart': '''
            void main() {
              int x = 5;
              print(x > 3 ? (x > 4 ? "big" : "mid") : "small");
              print(x < 3 ? "small" : (x < 4 ? "mid" : "big"));
            }
          ''',
        },
      });

      expect(() {
        runtime.executeLib('package:eval_test/main.dart', 'main');
      }, prints('big\nbig\n'));
    });

    test('String interpolation of null values', () {
      final runtime = compiler.compileWriteAndLoad({
        'eval_test': {
          'main.dart': '''
            void main() {
              String? s;
              print("value: \$s");
              dynamic d = {"a": null}["a"];
              print("value: \$d");
              s = "set";
              print("value: \$s");
            }
          ''',
        },
      });

      expect(() {
        runtime.executeLib('package:eval_test/main.dart', 'main');
      }, prints('value: null\nvalue: null\nvalue: set\n'));
    });

    test('Null-aware access on nullable locals', () {
      final runtime = compiler.compileWriteAndLoad({
        'eval_test': {
          'main.dart': '''
            void main() {
              String? s;
              print(s?.length);
              print(s?.contains("a"));
              s = "abc";
              print(s?.length);
              print(s?.isEmpty);
              print(s?.toUpperCase());
            }
          ''',
        },
      });

      expect(() {
        runtime.executeLib('package:eval_test/main.dart', 'main');
      }, prints('null\nnull\n3\nfalse\nABC\n'));
    });

    test('Chained null-aware accesses', () {
      final runtime = compiler.compileWriteAndLoad({
        'eval_test': {
          'main.dart': '''
            void main() {
              String? s = " ab ";
              print(s?.trim()?.length);
              print(s?.trim().length);
              s = null;
              print(s?.trim()?.length);
            }
          ''',
        },
      });

      expect(() {
        runtime.executeLib('package:eval_test/main.dart', 'main');
      }, prints('2\n2\nnull\n'));
    });

    test('"as" cast on unboxed value', () {
      final runtime = compiler.compileWriteAndLoad({
        'eval_test': {
          'main.dart': '''
            void main() {
              int i = 5;
              num n = i as num;
              print(n);
              print(5.5 as double);
            }
          ''',
        },
      });

      expect(() {
        runtime.executeLib('package:eval_test/main.dart', 'main');
      }, prints('5\n5.5\n'));
    });

    test('Named params and ternary', () {
      final runtime = Compiler().compileWriteAndLoad({
        'example': {
          'main.dart': '''
            String main(bool encrypt) {
              final encoding = cryptoHandler(encrypt: encrypt);
              return encoding;
            }
            
            String cryptoHandler({encrypt = true}) {
              return (encrypt) ? 'utf8' : 'base64';
            }
            
         ''',
        },
      });

      expect(runtime.executeLib('package:example/main.dart', 'main', [true])?.$value, 'utf8');
    });

    test('Null assertion', () {
      final runtime = Compiler().compileWriteAndLoad({
        'example': {
          'main.dart': '''
          void main() {
            X? x;
            x = X();
            print(x!.a);
          }

          class X {
            int a = 1;
          }
         ''',
        },
      });

      expect(() => runtime.executeLib('package:example/main.dart', 'main'), prints('1\n'));
    });

    test('Short-circuiting logical operators', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
          bool doTrue() {
            print('True executed');
            return true;
          }

          bool doFalse() {
            print('False executed');
            return false;
          }

          void main() {
            var x = doTrue() || doFalse();
            print(x);
            x = doFalse() && doTrue();
            print(x);
          }
          ''',
        },
      });

      expect(() {
        runtime.executeLib('package:example/main.dart', 'main');
      }, prints('True executed\ntrue\nFalse executed\nfalse\n'));
    });

    test('parameterized type literal as variable initializer', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            void main() {
              var t = List<int>;
              print(t == List);
            }
          ''',
        },
      });

      expect(() => runtime.executeLib('package:example/main.dart', 'main'), prints('true\n'));
    });
  });
}
