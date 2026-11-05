import 'package:dart_eval/dart_eval.dart';
import 'package:test/test.dart';

void main() {
  test('simple local function', () {
    final compiler = Compiler();
    final runtime = compiler.compileWriteAndLoad({
      't': {
        'main.dart': '''
          void main() {
            int square(int x) => x * x;
            print(square(5));
          }
        ''',
      },
    });
    expect(
      () => runtime.executeLib('package:t/main.dart', 'main'),
      prints('25\n'),
    );
  });

  test('local function calling another local function', () {
    final compiler = Compiler();
    final runtime = compiler.compileWriteAndLoad({
      't': {
        'main.dart': '''
          void main() {
            int square(int x) => x * x;
            int sumOfSquares(int a, int b) => square(a) + square(b);
            print(sumOfSquares(3, 4));
          }
        ''',
      },
    });
    expect(
      () => runtime.executeLib('package:t/main.dart', 'main'),
      prints('25\n'),
    );
  });

  test('local function with block body', () {
    final compiler = Compiler();
    final runtime = compiler.compileWriteAndLoad({
      't': {
        'main.dart': '''
          void main() {
            String greet(String name) {
              return 'Hello, \$name!';
            }
            print(greet('World'));
          }
        ''',
      },
    });
    expect(
      () => runtime.executeLib('package:t/main.dart', 'main'),
      prints('Hello, World!\n'),
    );
  });

  test('local function accessing outer variable', () {
    final compiler = Compiler();
    final runtime = compiler.compileWriteAndLoad({
      't': {
        'main.dart': '''
          void main() {
            var multiplier = 3;
            int multiply(int x) => x * multiplier;
            print(multiply(7));
          }
        ''',
      },
    });
    expect(
      () => runtime.executeLib('package:t/main.dart', 'main'),
      prints('21\n'),
    );
  });

  test('local function with record parameter capturing a record', () {
    final compiler = Compiler();
    final runtime = compiler.compileWriteAndLoad({
      't': {
        'main.dart': r'''
          (int, int)? span(int x) => x < 0 ? null : (x, x + 2);
          void main() {
            final own = span(1);
            if (own == null) return;
            bool overlaps((int, int) o) => o.$1 < own.$2 && own.$1 < o.$2;
            print(overlaps((2, 5)));
            print(overlaps((3, 5)));
          }
        ''',
      },
    });
    expect(
      () => runtime.executeLib('package:t/main.dart', 'main'),
      prints('true\nfalse\n'),
    );
  });

  test(
    'local function with nullable and named-field record parameters (non-null args)',
    () {
      final compiler = Compiler();
      final runtime = compiler.compileWriteAndLoad({
        't': {
          'main.dart': r'''
          void main() {
            int sum((int, int)? r) => r == null ? 0 : r.$1 + r.$2;
            int area(({int w, int h}) r) => r.w * r.h;
            print(sum((1, 2)));
                        print(area((w: 3, h: 4)));
          }
        ''',
        },
      });
      expect(
        () => runtime.executeLib('package:t/main.dart', 'main'),
        prints('3\n12\n'),
      );
    },
  );

  test('local function accepts null for nullable parameters', () {
    final compiler = Compiler();
    final runtime = compiler.compileWriteAndLoad({
      't': {
        'main.dart': r'''
          void main() {
            int count(int? x) => x == null ? 0 : x + 1;
            int size(List? l, {String? label}) => l == null ? -1 : l.length;
            String text((int, int)? r) => r == null ? 'none' : '${r.$1}-${r.$2}';
            print(count(1));
            print(count(null));
            print(size([1, 2]));
            print(size(null));
            print(size(null, label: null));
            print(text((1, 2)));
            print(text(null));
          }
        ''',
      },
    });
    expect(
      () => runtime.executeLib('package:t/main.dart', 'main'),
      prints('2\n0\n2\n-1\n-1\n1-2\nnone\n'),
    );
  });
}
