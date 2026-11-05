import 'package:dart_eval/dart_eval.dart';
import 'package:dart_eval/stdlib/core.dart';
import 'package:test/test.dart';

void main() {
  group('Loop tests', () {
    late Compiler compiler;

    setUp(() {
      compiler = Compiler();
    });

    test('For loop', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            num main() {
              var i = 0;
              for (; i < 555; i++) {}
              return i;
            }
          ''',
        },
      });
      expect(
        runtime.executeLib('package:example/main.dart', 'main'),
        $int(555),
      );
    });

    test('For loop + branching', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
          dynamic doThing() {
            var count = 0;
            for (var i = 0; i < 1000; i++) {
              if (count < 500) {
                count--;
              } else if (count < 750) {
                count++;
              }
              count += i;
            }
            
            return count;
          }
        ''',
        },
      });

      expect(
        runtime.executeLib('package:example/main.dart', 'doThing'),
        $int(499472),
      );
    });

    test('Simple foreach', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            num main() {
              var i = 0;
              for (var x in [1, 2, 3, 4, 5]) {
                i += x;
              }
              return i;
            }
          ''',
        },
      });
      expect(runtime.executeLib('package:example/main.dart', 'main'), $int(15));
    });

    test('Foreach with dynamic iterable, specifying type in loop', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            num main() {
              var i = 0;
              dynamic list = [[1, 2], [3, 4], [5]];
              for (List<int> x in list) {
                i += x[0];
              }
              i++;
              return i;
            }
          ''',
        },
      });
      expect(runtime.executeLib('package:example/main.dart', 'main'), $int(10));
    });

    test('Simple while loop', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            num main() {
              var i = 0;
              while (i < 555) {
                i++;
              }
              return i;
            }
          ''',
        },
      });
      expect(
        runtime.executeLib('package:example/main.dart', 'main'),
        $int(555),
      );
    });

    test('Simple do-while loop', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            num main() {
              var i = 0;
              do {
                i++;
              } while (i < 555);
              return i;
            }
          ''',
        },
      });
      expect(
        runtime.executeLib('package:example/main.dart', 'main'),
        $int(555),
      );
    });

    test('For loop with break', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            num main() {
              var i = 0;
              for (; i < 555; i++) {
                print(i);
                if (i == 5) {
                  break;
                }
              }
              return i;
            }
          ''',
        },
      });
      expect(runtime.executeLib('package:example/main.dart', 'main'), $int(5));
    });

    test('Nested for loop with break', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            num main() {
              var i = 0;
              var j = 0;
              for (; i < 555; i++) {
                for (; j < 555; j++) {
                  if (j == 100) {
                    break;
                  }
                }
                if (i == 100) {
                  break;
                }
              }
              return i * 1000 + j;
            }
          ''',
        },
      });
      expect(
        runtime.executeLib('package:example/main.dart', 'main'),
        $int(100100),
      );
    });

    test('Nested loop with break does not corrupt register state (#298)', () {
      final runtime = compiler.compileWriteAndLoad({
        'example': {
          'main.dart': '''
            String main() {
              dynamic rows = [
                {'numero_venda': 1, 'valor_em_aberto': 10.0},
                {'numero_venda': 2, 'valor_em_aberto': 5.0},
              ];
              dynamic taxasRows = [
                {'numero_venda': 1, 'taxa': 'A'},
                {'numero_venda': 2, 'taxa': 'B'},
              ];
              final out = StringBuffer();
              for (final row in rows) {
                dynamic taxa;
                for (final t in taxasRows) {
                  if (row['numero_venda'] == t['numero_venda']) {
                    taxa = t;
                    break;
                  }
                }
                final abertoRaw = row['valor_em_aberto'];
                if (abertoRaw is num && taxa != null) {
                  out.write('\${row['numero_venda']}:\${taxa['taxa']};');
                }
              }
              return out.toString();
            }
          ''',
        },
      });
      expect(
        runtime.executeLib('package:example/main.dart', 'main'),
        $String('1:A;2:B;'),
      );
    });

    group('continue', () {
      dynamic run(String body, {String ret = 'dynamic'}) => compiler
          .compileWriteAndLoad({
            'example': {'main.dart': 'dynamic main() { $body }'},
          })
          .executeLib('package:example/main.dart', 'main');

      test('for-in: variable boxed later in the body, continue taken', () {
        expect(
          run(r'''
            final l = <int>[];
            for (final b in [1, 2, 3]) {
              if (b == 2) continue;
              l.add(b);
            }
            return l.join(',');
          '''),
          $String('1,3'),
        );
      });

      test('for-in: continue taken before the first boxing', () {
        expect(
          run(r'''
            final l = [];
            for (final b in [2, 2, 1]) {
              if (b == 2) continue;
              l.add(b);
            }
            return l.length;
          '''),
          $int(1),
        );
      });

      test('C-style for: update runs after continue', () {
        expect(
          run(r'''
            final l = <int>[];
            for (var i = 0; i < 6; i++) {
              if (i % 2 == 0) continue;
              l.add(i);
            }
            return l.join(',');
          '''),
          $String('1,3,5'),
        );
      });

      test('while: continue with boxing in the body', () {
        expect(
          run(r'''
            final l = <int>[];
            var i = 0;
            while (i < 5) {
              i++;
              if (i == 3) continue;
              l.add(i);
            }
            return l.join(',');
          '''),
          $String('1,2,4,5'),
        );
      });

      test('do-while: continue with boxing in the body', () {
        expect(
          run(r'''
            final l = <int>[];
            var i = 0;
            do {
              i++;
              if (i == 3) continue;
              l.add(i);
            } while (i < 5);
            return l.join(',');
          '''),
          $String('1,2,4,5'),
        );
      });

      test('body that always returns still loops through continue', () {
        expect(
          run(r'''
            for (final x in [1, 2, 3]) {
              if (x < 3) continue;
              return x;
            }
            return -1;
          '''),
          $int(3),
        );
        expect(
          run(r'''
            final seen = <int>[];
            for (var i = 0; i < 5; i++) {
              seen.add(i);
              if (i < 3) continue;
              return seen.join(',');
            }
            final tail = 'none';
            return tail;
          '''),
          $String('0,1,2,3'),
        );
        expect(
          run(r'''
            for (final x in [1, 2]) {
              if (x < 3) continue;
              return x;
            }
            final tail = 'none';
            return tail;
          '''),
          $String('none'),
        );
      });

      test('loop whose body always returns can still run zero times', () {
        expect(
          run(r'''
            for (final x in []) {
              return x;
            }
            final tail = 'none';
            final t2 = tail + '!';
            return t2;
          '''),
          $String('none!'),
        );
        expect(
          run(r'''
            var i = 0;
            while (i < 0) {
              return i;
            }
            final k = 5;
            return 'none$k';
          '''),
          $String('none5'),
        );
        expect(
          run(r'''
            for (var i = 0; i < 0; i++) {
              return i;
            }
            final k = 5;
            return 'none$k';
          '''),
          $String('none5'),
        );
      });

      test('nested loops and blocks: continue only affects the inner loop', () {
        expect(
          run(r'''
            final l = <String>[];
            for (final a in [1, 2]) {
              for (final b in [1, 2, 3]) {
                if (b == 2) {
                  if (a == 1) continue;
                }
                l.add('$a$b');
              }
              l.add('|');
            }
            return l.join(',');
          '''),
          $String('11,13,|,21,22,23,|'),
        );
      });
    });
  });
}
