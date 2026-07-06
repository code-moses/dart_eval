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
  });
}
