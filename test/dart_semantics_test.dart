import 'package:dart_eval/dart_eval.dart';
import 'package:dart_eval/stdlib/core.dart';
import 'package:test/test.dart';

/// Edge-case tests verifying that evaluated code matches real Dart semantics.
/// Each test's expectation is what the equivalent native Dart program
/// produces.
void main() {
  late Compiler compiler;

  setUp(() {
    compiler = Compiler();
  });

  dynamic run(String source) {
    final runtime = compiler.compileWriteAndLoad({
      'example': {'main.dart': source},
    });
    return runtime.executeLib('package:example/main.dart', 'main');
  }

  group('Number semantics', () {
    test('Truncating division and euclidean modulo', () {
      expect(
        run('''
          String main() {
            return [7 ~/ 2, -7 ~/ 2, 7 % -2, -7 % 2, 7 % 2].join(',');
          }
        '''),
        $String('3,-3,1,1,1'),
      );
    });

    test('Double precision and int/double equality', () {
      expect(
        run('''
          String main() {
            final sum = 0.1 + 0.2;
            return [sum == 0.3, 1 == 1.0, sum.toStringAsFixed(1)].join(',');
          }
        '''),
        $String('false,true,0.3'),
      );
    });

    test('NaN is not equal to itself, division by zero yields infinity', () {
      expect(
        run('''
          String main() {
            final nan = 0 / 0;
            final inf = 1 / 0;
            return [nan == nan, nan.isNaN, inf.isInfinite, inf > 0].join(',');
          }
        '''),
        $String('false,true,true,true'),
      );
    });

    test('Bitwise and shift operators', () {
      expect(
        run('''
          String main() {
            return [1 << 3, 16 >> 2, 5 & 3, 5 | 2, 5 ^ 3].join(',');
          }
        '''),
        $String('8,4,1,7,6'),
      );
    });

    test('Integer parsing and radix conversion', () {
      expect(
        run('''
          String main() {
            return [int.parse('-42'), 255.toRadixString(16), int.parse('ff', radix: 16)].join(',');
          }
        '''),
        $String('-42,ff,255'),
      );
    });

    test('num method results: abs, clamp, floor/ceil/round on negatives', () {
      expect(
        run('''
          String main() {
            return [(-5).abs(), 7.clamp(1, 5), (-2.5).round(), (-2.5).floor(), (-2.5).ceil(), 2.5.round()].join(',');
          }
        '''),
        $String('5,5,-3,-3,-2,3'),
      );
    });
  });

  group('String semantics', () {
    test('Adjacent literals, raw strings and escapes', () {
      expect(
        run(r'''
          String main() {
            final adj = 'a' 'b';
            final raw = r'a\nb';
            return [adj, raw.length, 'A', '\x41'].join(',');
          }
        '''),
        $String('ab,4,A,A'),
      );
    });

    test('Indexing, substring edge cases and code units', () {
      expect(
        run('''
          String main() {
            final s = 'hello';
            return [s[1], s.substring(2, 2).isEmpty, s.codeUnitAt(0), s.substring(3)].join(',');
          }
        '''),
        $String('e,true,104,lo'),
      );
    });

    test('Nested interpolation and expression interpolation', () {
      expect(
        run(r'''
          String main() {
            final x = 3;
            return '${'inner ${x * 2}'} outer ${x + 1}';
          }
        '''),
        $String('inner 6 outer 4'),
      );
    });

    test('split/join round trip, replaceAll, padding and trim', () {
      expect(
        run('''
          String main() {
            return [
              'a,b,c'.split(',').join('-'),
              'banana'.replaceAll('a', 'o'),
              '5'.padLeft(3, '0'),
              ' hi '.trim(),
              'abc'.indexOf('z'),
            ].join('|');
          }
        '''),
        $String('a-b-c|bonono|005|hi|-1'),
      );
    });

    test('compareTo, startsWith, endsWith and contains', () {
      expect(
        run('''
          String main() {
            return [
              'a'.compareTo('b'),
              'b'.compareTo('a'),
              'a'.compareTo('a'),
              'dart'.startsWith('da'),
              'dart'.endsWith('rt'),
              'dart'.contains('ar'),
            ].join(',');
          }
        '''),
        $String('-1,1,0,true,true,true'),
      );
    });
  });

  group('Null safety semantics', () {
    test('?? and ??= evaluate the right operand only when needed', () {
      expect(
        run('''
          var log = '';
          int effect(int v) { log = log + 'e\$v;'; return v; }
          String main() {
            int? a;
            final r1 = a ?? effect(1);
            int? b = 5;
            final r2 = b ?? effect(2);
            b ??= effect(3);
            return [r1, r2, b, log].join(',');
          }
        '''),
        $String('1,5,5,e1;'),
      );
    });

    test('?. short-circuits on null and returns null', () {
      expect(
        run('''
          String main() {
            String? s;
            final r = s?.toUpperCase();
            String? t = 'ok';
            final u = t?.toUpperCase();
            return [r == null, u].join(',');
          }
        '''),
        $String('true,OK'),
      );
    });

    test('Chained null-aware access on nullable class fields', () {
      expect(
        run('''
          class Node {
            Node? next;
            int value;
            Node(this.value);
          }
          String main() {
            final a = Node(1);
            a.next = Node(2);
            return [a.next?.value, a.next?.next?.value == null].join(',');
          }
        '''),
        $String('2,true'),
      );
    });
  });

  group('Control flow semantics', () {
    test('Short-circuit && and || skip right operand side effects', () {
      expect(
        run('''
          var log = '';
          bool effect(bool v, String tag) { log = log + tag; return v; }
          String main() {
            final a = effect(false, 'a') && effect(true, 'b');
            final b = effect(true, 'c') || effect(true, 'd');
            return [a, b, log].join(',');
          }
        '''),
        $String('false,true,ac'),
      );
    });

    test('do-while runs at least once; while false never runs', () {
      expect(
        run('''
          String main() {
            var log = '';
            do { log = log + 'once;'; } while (false);
            while (false) { log = log + 'never;'; }
            var i = 0;
            do { i++; } while (i < 3);
            return [log, i].join(',');
          }
        '''),
        $String('once;,3'),
      );
    });

    test('for loop with multiple declarations and updaters', () {
      expect(
        run('''
          int main() {
            var total = 0;
            for (var i = 0, j = 10; i < j; i++, j--) {
              total += j - i;
            }
            return total;
          }
        '''),
        30,
      );
    });

    test('break and continue interact correctly in nested loops', () {
      expect(
        run('''
          String main() {
            var log = '';
            for (var i = 0; i < 3; i++) {
              for (var j = 0; j < 3; j++) {
                if (j == 2) break;
                if (i == 1) continue;
                log = log + '\$i\$j;';
              }
            }
            return log;
          }
        '''),
        $String('00;01;20;21;'),
      );
    });

    test('Nested ternary expressions associate correctly', () {
      expect(
        run('''
          String main() {
            String grade(int s) => s > 89 ? 'A' : s > 79 ? 'B' : s > 69 ? 'C' : 'F';
            return [grade(95), grade(85), grade(72), grade(12)].join(',');
          }
        '''),
        $String('A,B,C,F'),
      );
    });

    test('switch on strings with grouped cases and default', () {
      expect(
        run('''
          String classify(String s) {
            switch (s) {
              case 'a':
              case 'e':
              case 'i':
              case 'o':
              case 'u':
                return 'vowel';
              case 'z':
                return 'rare';
              default:
                return 'consonant';
            }
          }
          String main() {
            return [classify('a'), classify('z'), classify('k')].join(',');
          }
        '''),
        $String('vowel,rare,consonant'),
      );
    });
  });

  group('Function and closure semantics', () {
    test('Currying: closures over closures', () {
      expect(
        run('''
          int main() {
            final mul = (int a) => (int b) => a * b;
            final triple = mul(3);
            return triple(4) + mul(2)(5);
          }
        '''),
        22,
      );
    });

    test('Closures share mutable captured state', () {
      expect(
        run('''
          String main() {
            var count = 0;
            final inc = () { count++; };
            final dec = () { count--; };
            inc(); inc(); inc(); dec();
            return [count].join('');
          }
        '''),
        $String('2'),
      );
    });

    test('Optional positional and named parameter defaults', () {
      expect(
        run('''
          String pos(int a, [int b = 2, int c = 3]) => '\$a\$b\$c';
          String named(int a, {int x = 7, int? y}) => '\$a\$x\${y ?? 0}';
          String main() {
            return [pos(1), pos(1, 9), pos(1, 9, 8), named(1), named(1, y: 5), named(1, x: 2, y: 3)].join(',');
          }
        '''),
        $String('123,193,198,170,175,123'),
      );
    });

    test('Local function recursion and mutual recursion', () {
      expect(
        run('''
          bool isEven(int n) => n == 0 ? true : isOdd(n - 1);
          bool isOdd(int n) => n == 0 ? false : isEven(n - 1);
          int main() {
            int fact(int n) => n <= 1 ? 1 : n * fact(n - 1);
            return fact(5) + (isEven(10) ? 1 : 0) + (isOdd(7) ? 1 : 0);
          }
        '''),
        122,
      );
    });

    test('Immediately invoked function expression', () {
      expect(
        run('''
          int main() {
            return (() => 5)() + ((int x) => x * 2)(10);
          }
        '''),
        25,
      );
    });

    test('Function passed as argument and invoked by callee', () {
      expect(
        run('''
          int apply(int Function(int) f, int v) => f(v);
          int addOne(int x) => x + 1;
          int main() {
            return apply(addOne, 1) + apply((x) => x * 10, 2);
          }
        '''),
        22,
      );
    });
  });

  group('Increment, decrement and compound assignment', () {
    test('Postfix returns old value, prefix returns new value', () {
      expect(
        run('''
          String main() {
            var i = 5;
            final post = i++;
            final pre = ++i;
            var j = 5;
            final postD = j--;
            final preD = --j;
            return [post, pre, i, postD, preD, j].join(',');
          }
        '''),
        $String('5,7,7,5,3,3'),
      );
    });

    test('Compound assignment on locals, fields, and list elements', () {
      expect(
        run('''
          class Counter { int n = 10; }
          String main() {
            var x = 8;
            x ~/= 3;
            x *= 5;
            x -= 1;
            x %= 6;
            final c = Counter();
            c.n += 5;
            final list = [1, 2, 3];
            list[1] += 10;
            return [x, c.n, list[1]].join(',');
          }
        '''),
        $String('3,15,12'),
      );
    });
  });

  group('Class semantics', () {
    test('Virtual dispatch with super call chains', () {
      expect(
        run('''
          class A { String m() => 'A'; }
          class B extends A { String m() => 'B>' + super.m(); }
          class C extends B { String m() => 'C>' + super.m(); }
          String main() {
            final A obj = C();
            return obj.m();
          }
        '''),
        $String('C>B>A'),
      );
    });

    test('Getters and setters behave like computed properties', () {
      expect(
        run('''
          class Celsius {
            double degrees;
            Celsius(this.degrees);
            double get fahrenheit => degrees * 1.8 + 32;
            set fahrenheit(double f) => degrees = (f - 32) / 1.8;
          }
          String main() {
            final t = Celsius(100.0);
            final boiling = t.fahrenheit;
            t.fahrenheit = 32.0;
            return [boiling, t.degrees].join(',');
          }
        '''),
        $String('212.0,0.0'),
      );
    });

    test('Static state is shared across instances', () {
      expect(
        run('''
          class Registry {
            static int count = 0;
            static int bump() => ++count;
            Registry() { bump(); }
          }
          int main() {
            Registry(); Registry(); Registry();
            Registry.bump();
            return Registry.count;
          }
        '''),
        4,
      );
    });

    test('Operator overloads compose with compound assignment', () {
      expect(
        run('''
          class Vec {
            final int x, y;
            Vec(this.x, this.y);
            Vec operator +(Vec o) => Vec(x + o.x, y + o.y);
            Vec operator *(int k) => Vec(x * k, y * k);
          }
          String main() {
            var v = Vec(1, 2);
            v += Vec(3, 4);
            final w = v * 2;
            return [v.x, v.y, w.x, w.y].join(',');
          }
        '''),
        $String('4,6,8,12'),
      );
    });

    test('Cascades apply mutations to the same target and return it', () {
      expect(
        run('''
          class Box { int a = 0; int b = 0; }
          String main() {
            final box = Box()
              ..a = 1
              ..b = 2;
            final list = [3, 1, 2]
              ..sort()
              ..add(9);
            return [box.a, box.b, list.join('')].join(',');
          }
        '''),
        $String('1,2,1239'),
      );
    });

    test('Initializer lists run before the constructor body', () {
      expect(
        run('''
          class P {
            final int doubled;
            int tracked = 0;
            P(int v) : doubled = v * 2 {
              tracked = doubled + 1;
            }
          }
          String main() {
            final p = P(21);
            return [p.doubled, p.tracked].join(',');
          }
        '''),
        $String('42,43'),
      );
    });

    test('Factory constructor can return a cached instance', () {
      expect(
        run('''
          class Singleton {
            static Singleton? _instance;
            int hits = 0;
            Singleton._();
            factory Singleton() {
              final inst = _instance ??= Singleton._();
              inst.hits++;
              return inst;
            }
          }
          int main() {
            Singleton();
            Singleton();
            return Singleton().hits;
          }
        '''),
        3,
      );
    });

    test('implements satisfies is-checks and dispatches to implementation', () {
      expect(
        run('''
          abstract class Shape { int area(); }
          class Square implements Shape {
            final int side;
            Square(this.side);
            int area() => side * side;
          }
          String main() {
            final Shape s = Square(4);
            return [s.area(), s is Shape, s is Square].join(',');
          }
        '''),
        $String('16,true,true'),
      );
    });
  });

  group('Enum semantics', () {
    test('values order, index, name and identity equality', () {
      expect(
        run('''
          enum Direction { north, east, south, west }
          String main() {
            final d = Direction.south;
            return [
              d.index,
              d.name,
              Direction.values.length,
              d == Direction.south,
              d == Direction.north,
              Direction.values[1].name,
            ].join(',');
          }
        '''),
        $String('2,south,4,true,false,east'),
      );
    });

    test('switch over enum values', () {
      expect(
        run('''
          enum Signal { red, yellow, green }
          String act(Signal s) {
            switch (s) {
              case Signal.red: return 'stop';
              case Signal.yellow: return 'slow';
              case Signal.green: return 'go';
            }
          }
          String main() => [act(Signal.red), act(Signal.green)].join(',');
        '''),
        $String('stop,go'),
      );
    });
  });

  group('Collection semantics', () {
    test('Lists are aliased references, not copies', () {
      expect(
        run('''
          String main() {
            final a = [1, 2, 3];
            final b = a;
            b[0] = 9;
            b.add(4);
            return [a[0], a.length].join(',');
          }
        '''),
        $String('9,4'),
      );
    });

    test('Iterable chains: map/where/fold/any/every/take/skip', () {
      expect(
        run('''
          String main() {
            final nums = [1, 2, 3, 4, 5, 6];
            return [
              nums.where((n) => n % 2 == 0).map((n) => n * 10).join('-'),
              nums.fold(0, (a, b) => a + b),
              nums.any((n) => n > 5),
              nums.every((n) => n > 0),
              nums.take(2).join(''),
              nums.skip(4).join(''),
            ].join('|');
          }
        '''),
        $String('20-40-60|21|true|true|12|56'),
      );
    });

    test('Map putIfAbsent, update, containsValue and entry iteration', () {
      expect(
        run('''
          String main() {
            final m = {'a': 1, 'b': 2};
            m.putIfAbsent('c', () => 3);
            m.putIfAbsent('a', () => 99);
            m.update('b', (v) => v * 10);
            var acc = '';
            for (final k in m.keys) { acc = acc + '\$k\${m[k]};'; }
            return [acc, m.containsValue(20), m.length].join('|');
          }
        '''),
        $String('a1;b20;c3;|true|3'),
      );
    });

    test('Set deduplicates and preserves membership semantics', () {
      expect(
        run('''
          String main() {
            final s = <int>{1, 2, 2, 3};
            final added = s.add(3);
            final addedNew = s.add(4);
            return [s.length, added, addedNew, s.contains(2), s.contains(9)].join(',');
          }
        '''),
        $String('4,false,true,true,false'),
      );
    });

    test('Spread and collection-if/for compose in a single literal', () {
      expect(
        run('''
          String main() {
            final base = [2, 3];
            final flag = true;
            final list = [1, ...base, if (flag) 4, for (var i = 5; i < 7; i++) i];
            return list.join('');
          }
        '''),
        $String('123456'),
      );
    });

    test('Nested collections: map of lists supports deep mutation', () {
      expect(
        run('''
          String main() {
            final m = <String, List<int>>{'a': [1], 'b': [2, 3]};
            m['a']!.add(10);
            m['b']![0] = 20;
            return [m['a']!.join('-'), m['b']!.join('-')].join(',');
          }
        '''),
        $String('1-10,20-3'),
      );
    });

    test('List.generate and sort with custom comparator', () {
      expect(
        run('''
          String main() {
            final squares = List.generate(4, (i) => i * i);
            final words = ['bb', 'a', 'ccc'];
            words.sort((a, b) => a.length.compareTo(b.length));
            return [squares.join(','), words.join(',')].join('|');
          }
        '''),
        $String('0,1,4,9|a,bb,ccc'),
      );
    });
  });

  group('Record and pattern semantics', () {
    test('Record field access and positional/named mixing', () {
      expect(
        run(r'''
          (int, {String tag}) build() => (42, tag: 'x');
          String main() {
            final r = build();
            return '${r.$1},${r.tag}';
          }
        '''),
        $String('42,x'),
      );
    });

    test('Destructuring declarations for records and lists', () {
      expect(
        run('''
          String main() {
            final (a, b) = (1, 'two');
            final [x, y, z] = [10, 20, 30];
            return [a, b, x + y + z].join(',');
          }
        '''),
        $String('1,two,60'),
      );
    });

    test('if-case with map pattern and guard', () {
      expect(
        run('''
          String main() {
            final data = {'kind': 'circle', 'radius': 5};
            var out = 'none';
            if (data case {'kind': 'circle', 'radius': int r} when r > 3) {
              out = 'big circle \$r';
            }
            return out;
          }
        '''),
        $String('big circle 5'),
      );
    });

    test('switch expression with relational and wildcard patterns', () {
      expect(
        run('''
          String size(int n) => switch (n) {
            < 0 => 'negative',
            0 => 'zero',
            > 0 && < 10 => 'small',
            _ => 'large',
          };
          String main() {
            return [size(-5), size(0), size(3), size(99)].join(',');
          }
        '''),
        $String('negative,zero,small,large'),
      );
    });
  });

  group('Exception semantics', () {
    test('finally runs on the return path and preserves the return value', () {
      expect(
        run('''
          var log = '';
          String f() {
            try {
              log = log + 'try;';
              return 'fromTry';
            } finally {
              log = log + 'finally;';
            }
          }
          String main() {
            final r = f();
            return [r, log].join('|');
          }
        '''),
        $String('fromTry|try;finally;'),
      );
    });

    test('First matching on-clause wins and rethrow escalates', () {
      expect(
        run('''
          String main() {
            var log = '';
            try {
              try {
                throw FormatException('bad');
              } on StateError {
                log = log + 'state;';
              } on FormatException {
                log = log + 'format;';
                rethrow;
              }
            } catch (e) {
              log = log + 'outer;';
            }
            return log;
          }
        '''),
        $String('format;outer;'),
      );
    });

    test('Thrown non-Exception values are caught by untyped catch', () {
      expect(
        run('''
          String main() {
            try {
              throw 'plain string';
            } catch (e) {
              return 'caught: \$e';
            }
          }
        '''),
        $String('caught: plain string'),
      );
    });

    test('finally runs when an exception propagates through', () {
      expect(
        run('''
          var log = '';
          void inner() {
            try {
              throw StateError('x');
            } finally {
              log = log + 'innerFinally;';
            }
          }
          String main() {
            try {
              inner();
            } catch (e) {
              log = log + 'caught;';
            }
            return log;
          }
        '''),
        $String('innerFinally;caught;'),
      );
    });
  });

  group('Type test semantics', () {
    test('is/is! respect the class hierarchy and num supertypes', () {
      expect(
        run('''
          class Animal {}
          class Dog extends Animal {}
          String main() {
            final Animal a = Dog();
            final Object n = 3;
            return [a is Dog, a is Animal, n is num, n is int, n is double, 'x' is! int].join(',');
          }
        '''),
        $String('true,true,true,true,false,true'),
      );
    });

    test('dynamic values keep their runtime type for is-checks', () {
      expect(
        run('''
          String main() {
            dynamic d = 'text';
            final wasString = d is String;
            d = 42;
            final wasInt = d is int;
            return [wasString, wasInt].join(',');
          }
        '''),
        $String('true,true'),
      );
    });

    test('bare as-List cast (no type args) supports boxing and members', () {
      // Regression: a cast to `List` without type arguments produced a type
      // with empty specifiedTypeArgs, which crashed boxIfNeeded when the
      // value was subsequently boxed (e.g. by string interpolation).
      expect(
        run(r'''
          dynamic make() => [1, 2, 3];
          String main() {
            final l = make() as List;
            return '${l.length}:$l';
          }
        '''),
        $String('3:[1, 2, 3]'),
      );
    });
  });

  group('Async semantics', () {
    test(
      'await preserves sequential ordering across async boundaries',
      () async {
        final result = await run('''
        Future<String> step(String log, String tag) async => log + tag;
        Future<String> main() async {
          var log = 'start;';
          log = await step(log, 'one;');
          log = await step(log, 'two;');
          return log;
        }
      ''');
        expect(result.$reified, 'start;one;two;');
      },
    );

    test('try/catch captures errors thrown after await', () async {
      final result = await run('''
        Future<int> boom() async {
          throw StateError('kaboom');
        }
        Future<String> main() async {
          try {
            await boom();
            return 'no error';
          } catch (e) {
            return 'caught';
          }
        }
      ''');
      expect(result.$reified, 'caught');
    });
  });
}
