import 'dart:typed_data';

import 'package:dart_eval/dart_eval.dart';
import 'package:dart_eval/src/eval/runtime/runtime.dart';
import 'package:dart_eval/src/eval/shared/stdlib/core/base.dart';
import 'package:dart_eval/src/eval/shared/stdlib/core/num.dart';
import 'package:test/test.dart';

/// Compiles [source] with box-state verification enabled and runs `main`.
dynamic _runVerified(String source) {
  final compiler = Compiler()..verifyBoxing = true;
  final program = compiler.compile({
    'example': {'main.dart': source},
  });
  final runtime = Runtime.ofProgram(program);
  return runtime.executeLib('package:example/main.dart', 'main');
}

void main() {
  group('Box-state verification (Compiler.verifyBoxing)', () {
    // These exercise concrete-typed box/unbox transitions across the features
    // that historically drifted. With verification on, any divergence between
    // the compiler's box belief and the runtime representation throws at the
    // offending op; a correct result means the invariant held throughout.
    test('Inheritance and polymorphic dispatch verify clean', () {
      expect(
        _runVerified(r'''
          class Animal { String noise() => 'generic'; }
          class Dog extends Animal { String noise() => 'woof'; }
          String main() {
            final list = <Animal>[Dog(), Animal()];
            final buf = <String>[];
            for (final a in list) { buf.add(a.noise()); }
            return buf.join(',');
          }
        '''),
        $String('woof,generic'),
      );
    });

    test('Enums, patterns and list ops verify clean', () {
      expect(
        _runVerified(r'''
          enum Color { red, green, blue; String describe() => '$name/$index'; }
          int main() {
            final m = {'a': 1, 'b': 2};
            var total = 0;
            if (m case {'a': int x, 'b': int y}) total = x + y;
            final labels = Color.values.map((c) => c.describe()).toList();
            return total + labels.length + [1, 2, 3].where((e) => e > 1).length;
          }
        '''),
        8,
      );
    });

    test('Records, closures, equality and postfix ops verify clean', () {
      // Regression: the box-state sweep (explicit `boxed:` at Variable
      // construction) corrected several sites whose implicit flag was
      // untruthful — record field lists, closure arg-type lists, CheckEq
      // results and postfix-increment slot copies. This exercises them all
      // with verification on.
      expect(
        _runVerified(r'''
          int main() {
            final rec = (1, name: 'xy');
            final f = (int a) => a + rec.$1;
            var n = f(2);
            if (n != 4) n++;
            return n + rec.name.length;
          }
        '''),
        6,
      );
    });

    test('Extension methods verify clean', () {
      expect(
        _runVerified(r'''
          extension StringExt on String {
            String shout() => toUpperCase() + '!';
            int get twice => length * 2;
          }
          String main() => 'hi'.shout() + '/' + 'abc'.twice.toString();
        '''),
        $String('HI!/6'),
      );
    });
  });

  group('AssertBoxState op', () {
    // Prove the op actually catches drift, not just that correct programs pass.
    final runtime = Runtime(Uint8List(0).buffer.asByteData());

    test('throws when a boxed slot holds a raw value', () {
      runtime.frame = [10];
      expect(
        () => AssertBoxState.make(0, true).run(runtime),
        throwsA(isA<Exception>()),
      );
    });

    test('throws when an unboxed slot holds a boxed value', () {
      runtime.frame = [$int(10)];
      expect(
        () => AssertBoxState.make(0, false).run(runtime),
        throwsA(isA<Exception>()),
      );
    });

    test('passes when representations match', () {
      runtime.frame = [$int(10), 10];
      expect(() => AssertBoxState.make(0, true).run(runtime), returnsNormally);
      expect(() => AssertBoxState.make(1, false).run(runtime), returnsNormally);
    });

    test('treats null as consistent with either state', () {
      runtime.frame = [null];
      expect(() => AssertBoxState.make(0, true).run(runtime), returnsNormally);
      expect(() => AssertBoxState.make(0, false).run(runtime), returnsNormally);
    });
  });
}
