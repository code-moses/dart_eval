[![Build status](https://img.shields.io/github/actions/workflow/status/ethanblake4/dart_eval/dart.yml?branch=master)](https://github.com/ethanblake4/dart_eval/actions/workflows/dart.yml)
[![License: BSD-3](https://img.shields.io/badge/license-BSD3-purple.svg)](https://opensource.org/licenses/BSD-3-Clause)
[![Web example](https://img.shields.io/badge/web-example-blue.svg)](https://ethanblake.xyz/evalpad)
[![Star on Github](https://img.shields.io/github/stars/ethanblake4/dart_eval?logo=github&colorB=orange&label=stars)](https://github.com/ethanblake4/dart_eval)
[![Github-sponsors](https://img.shields.io/badge/sponsor-30363D?logo=GitHub-Sponsors&logoColor=#EA4AAA)](https://github.com/sponsors/ethanblake4)

> ## About this fork
>
> This fork ([code-moses/dart_eval](https://github.com/code-moses/dart_eval)) is ahead of
> [ethanblake4/dart_eval](https://github.com/ethanblake4/dart_eval) by the following changes:
>
> **Opt-in features**
> - `Compiler.softNullableCasts`: C#-style soft casts — when enabled, a failed cast to a
>   *nullable* type (`myValue as MyType?`) evaluates to null instead of throwing, composing
>   with `??` and `?.`. Casts to non-nullable types remain strict. Defaults to off (standard
>   Dart semantics).
> - `Compiler.verifyBoxing`: debugging aid that emits runtime assertions at every
>   concrete-typed box/unbox transition, so box-state drift between the compiler's belief and
>   the actual runtime representation fails fast at the offending op instead of surfacing as a
>   distant type error. Defaults to off.
>
> **Dynamic dispatch & method invocation fixes**
> - Method calls on `dynamic` receivers no longer pass the receiver as the first argument to
>   builtin methods (e.g. `s.split(":")` splitting by the receiver itself)
> - Operators on interpreted classes (e.g. `Vec(1) + Vec(2)`) invoke with the correct target
> - Arguments are boxed across dynamic dispatch boundaries; missing optional arguments are
>   null-padded (`l.sort()`, `join()`, `toList()` on dynamic receivers)
> - Explicit `.call()` on functions compiles; unary minus works on `num`/`dynamic` operands
> - `dynamic`-typed values holding functions can be invoked (e.g. a closure returned from
>   another closure: `mul(3)(4)`); the static-vs-dynamic dispatch decision is derived once at
>   variable construction instead of being re-derived inconsistently at call sites
> - Invoking a missing method on a `dynamic` receiver throws a catchable `NoSuchMethodError`
>   (matching Dart) instead of crashing the interpreter with a host error
>
> **Null safety & nullability fixes**
> - `as`/`is` respect nullability (`null as String?`, `null is String?`); `as` no longer
>   crashes on unboxed values
> - `==`/`!=` never invoke a user-defined `operator ==` with a null operand (Dart semantics)
> - Null-aware access on unboxed nullable receivers, chained null-aware operators
>   (`s?.trim()?.length`), string interpolation of null values, and the null-aware spread
>   operator (`...?`) all work correctly
>
> **Expression fixes**
> - Conditional (ternary) expressions: consistent boxing across branches and correct results
>   when nested
> - Null-coalescing with `toString()` and nested loop runtime flow corruption (pre-session
>   fixes, [#298](https://github.com/ethanblake4/dart_eval/pull/298)/[#299](https://github.com/ethanblake4/dart_eval/pull/299))
>
> **Runtime & memory fixes**
> - Closures created in loops capture loop variables per iteration instead of observing the
>   final/reused slot value ([#269](https://github.com/ethanblake4/dart_eval/issues/269))
> - Large collection literals no longer overflow the fixed-size runtime frame
>   ([#297](https://github.com/ethanblake4/dart_eval/issues/297))
> - Index assignment on `dynamic` receivers, e.g. `k['a']['b'] = 'd'` on an untyped map
>   ([#228](https://github.com/ethanblake4/dart_eval/issues/228))
>
> **New language support**
> - Extension methods and getters (`extension StringExt on String { String shout() => ... }`),
>   including bare/`this` member access inside bodies, cross-library use, and most-specific
>   `on`-type resolution (instance members still take precedence)
> - Switch expressions (`switch (x) { 1 => 'a', _ => 'b' }`) with constant, list, record, map
>   and object patterns, `when` guards and variable binding, usable in any expression position
> - If-case statements (`if (value case pattern when guard) ...`) with pattern variable binding
> - Map patterns (`{'k': int v}`) and object patterns (`Point(x: 0, y: var y)`), in switches,
>   if-case, and irrefutable declarations (`final Point(:x, :y) = p;`)
> - Logical patterns (`> 0 && < 10`, `p1 || p2`) with short-circuit semantics
> - Typed pattern variables promote (`if (o case int n) n + 1`); nested and mixed
>   record/list patterns (`[[a, _], [_, d]]`); rest elements (`[first, ...rest, last]`)
> - `continue` statements in loops (previously unimplemented; labels remain unsupported)
> - `late final` fields without initializers are assignable, e.g. from a constructor body
>   (the once-only runtime check is not enforced)
> - Self-recursive local functions (`int fact(int n) => n <= 1 ? 1 : n * fact(n - 1);`)
> - Assignment to static fields by bare identifier inside class bodies
>   (`static int count = 0; static int bump() => ++count;`)
> - Null-aware index operator (`target?[index]`), including chained forms like `m?['a']?[1]`
> - `String` `*` operator (`'ab' * 3`)
> - Spread (`...`/`...?`), `if` and `for` elements in set and map literals, matching the
>   existing support for list literals
> - Script enums: implicit `name`/`index` getters (also as bare identifiers inside enum
>   methods), static `values` list, a default `toString` (`EnumName.constant`), and
>   instance methods/getters
> - Inherited `Object` methods (`toString`, `hashCode`, `==`) on script class instances that
>   don't override them
> - Stdlib: `Map.putIfAbsent`, `Map.update`, `Map.containsValue`; `Set.add` returns whether
>   the value was added
>
> **Dart semantics correctness fixes**
> - `??=` only evaluates its right-hand side when the target is null, and the expression
>   yields the target's final value
> - `finally` blocks preserve a pending `return` from the try body (previously the value was
>   lost and the function returned null)
> - Boxing a list preserves its identity, so aliased references observe mutations
>   (`final b = a; b.add(4);` changes `a.length`) — boxing previously copied the list
> - Cascade property assignments (`Box()..a = 1..b = 2`) mutate the actual target instead of
>   recompiling the target expression into a fresh instance
> - Numeric result typing matches Dart: `/` is always `double` (so `0 / 0` is NaN), `~/` is
>   always `int`, and `double + int` is `double` rather than `num`
> - Double literals are stored as float64 in bytecode (previously float32, so `1.8` lost
>   precision); note this changes the EVC bytecode layout, so cached `.evc` files must be
>   recompiled
> - Uninitialized statics/globals (`static Foo? x;`) read as null instead of executing stray
>   bytecode at program offset 0
> - Two consecutive loops no longer corrupt the frame: a do-while's exit path leaked the last
>   iteration's allocations, shifting every subsequent slot
> - Relational patterns no longer corrupt the switch subject's representation for later cases
>   (any switch with two numeric patterns was affected)
> - `$List.view` works in evaluated code: unboxing it yields a write-through view that wraps
>   elements on read and writes back to the host list (new `$ValueView` interface)
>
> **Additional fixes**
> - Script class inheritance: inherited method calls, polymorphic dispatch through a base-typed
>   reference, subclass methods reached via cast/promotion, and multi-level inheritance now work
>   (previously corrupted the compiled program when extending another script class)
> - Ternary/switch-expression results keep correct boxing (returning class instances or enums,
>   reading a local in a branch, or assigning the result to a typed `int` no longer crash)
> - Pattern guards are only evaluated when the pattern matches (no stale bindings or side effects)
> - List patterns verify length and match null/short subjects cleanly, so `[1, 2, 3]` no longer
>   matches `[var a, var b]` and a wrong-length or null subject fails instead of crashing
> - Structural pattern type tests are null-safe: a null subject (e.g. an absent map key) fails
>   the match instead of crashing on the `is` check
> - Tree shaking keeps imported declarations used by *sibling* declarations of a non-entrypoint
>   library (previously only the first declaration's dependencies survived, so e.g. the second
>   helper function using a different imported getter failed to compile)
> - A bare `as List` cast (no type arguments) no longer crashes the compiler when the value is
>   subsequently boxed (e.g. by string interpolation)
>
> **Documented patterns**
> - [test/plugin_globals_test.dart](test/plugin_globals_test.dart) demonstrates providing
>   host-defined globals (e.g. `currententry['quantity'] as int`) through an `EvalPlugin` — a
>   bridge class with `[]`/`[]=` plus `addSource` top-level getters — so scripts are compiled
>   and cached once as EVC bytecode while host values change freely between executions.
>
> All fixes are covered by regression tests; the full upstream test suite passes (575 tests,
> none skipped). [test/dart_semantics_test.dart](test/dart_semantics_test.dart) additionally
> asserts, feature by feature, that evaluated code matches what the equivalent native Dart
> program produces.

`dart_eval` is an extensible bytecode compiler and interpreter for the Dart language, 
written in Dart, enabling dynamic execution and codepush for Flutter and Dart AOT.

| dart_eval    | [![pub package](https://img.shields.io/pub/v/dart_eval.svg?label=dart_eval&color=teal)](https://pub.dev/packages/dart_eval)          |
| ------------ | ------------------------------------------------------------------------------------------------------------------------------------ |
| flutter_eval | [![pub package](https://img.shields.io/pub/v/flutter_eval.svg?label=flutter_eval&color=blue)](https://pub.dev/packages/flutter_eval) |
| eval_annotation | [![pub package](https://img.shields.io/pub/v/eval_annotation.svg?label=eval_annotation&color=orange)](https://pub.dev/packages/eval_annotation) |

The primary aspect of `dart_eval`'s goal is to be interoperable with real 
Dart code. The automated [interop and binding](#interop-and-binding) generation system allows
classes created in 'real Dart' to be used inside the interpreter, and classes
created in the interpreter to be used outside it.

dart_eval's compiler is powered under the hood by the Dart 
[analyzer](https://pub.dev/packages/analyzer), so it achieves 100% correct and 
up-to-date parsing. While compilation and execution aren't quite there yet, dart_eval
has over 550 tests that are run in CI to ensure correctness.

Currently dart_eval implements a majority of the Dart spec, but there 
are still missing features like generators, mixins and typedefs (this fork adds
extension methods, switch expressions, logical patterns, `continue`, late field
assignment and more — see [About this fork](#about-this-fork)).
In addition, parts of the standard library haven't been implemented. See the
[language feature support table](#language-feature-support-table) for details.

If you use this project, please consider a small donation on [GitHub Sponsors](https://github.com/sponsors/ethanblake4) to help support its development.

## Usage

> **Note**: See the README for [flutter_eval](https://pub.dev/packages/flutter_eval) for
information on setting up Flutter code push.

A basic usage example of the `eval` method, which is a simple shorthand to
execute Dart code at runtime:

```dart
import 'package:dart_eval/dart_eval.dart';

void main() {
  print(eval('2 + 2')); // -> 4
  
  final program = r'''
      class Cat {
        Cat(this.name);
        final String name;
        String speak() => "I'm $name!";
      }
      String main() {
        final cat = Cat('Fluffy');
        return cat.speak();
      }
  ''';
  
  print(eval(program, function: 'main')); // prints 'I'm Fluffy!'
}
```

## Passing arguments
In most cases, you should wrap arguments you pass to dart_eval in `$Value`
wrappers, such as `$String` or `$Map`. These 'boxed types' have information 
about what they are and how to modify them, and you can access their underlying
value with the `$value` property. However, ints, doubles, bools, 
and Lists are treated as primitives and should be passed without wrapping
when their exact type is specified in the function signature:

```dart
final program = '''
  int main(int count, String str) {
    return count + str.length;
  }
''';

print(eval(program, function: 'main', args: [1, $String('Hi!')])); // -> 4
```

When calling a function or constructor externally, you must specify all arguments - even optional and named ones - in order, using null to indicate the absence of an argument (whereas $null() indicates a null value).

## Passing callbacks
You can pass callbacks as arguments to dart_eval using `$Closure`:
  
```dart
import 'package:dart_eval/dart_eval.dart';
import 'package:dart_eval/dart_eval_bridge.dart';

void main() {
  final program = '''
    void main(Function callback) {
      callback('Hello');
    }
  ''';

  eval(program, function: 'main', args: [
    $Closure((runtime, target, args) {
      print(args[0]!.$value + '!');
      return null;
    })
  ]); // -> prints 'Hello!'
}
```

## Advanced usage
For more advanced usage, you can use the Compiler and Runtime classes directly,
which will allow you to use multiple 'files' and customize how the program is run:

```dart
import 'package:dart_eval/dart_eval.dart';

void main() {
  final compiler = Compiler();
  
  final program = compiler.compile({'my_package': {
    'main.dart': '''
      import 'package:my_package/finder.dart';
      void main() {
        final parentheses = findParentheses('Hello (world)');
        if (parentheses.isNotEmpty) print(parentheses); 
      }
    ''',
    'finder.dart': r'''
      List<int> findParentheses(string) {
        final regex = RegExp(r'\((.*?)\)');
        final matches = regex.allMatches(string);
        return matches.map((match) => match.start).toList();
      }
    '''
  }});
  
  final runtime = Runtime.ofProgram(program);
  print(runtime.executeLib(
    'package:my_package/main.dart', 'main')); // prints '[6]'
}
```

## Entrypoints and tree-shaking

dart_eval uses tree-shaking to avoid compiling unused code. By default, 
any file named `main.dart` or that contains [runtime overrides](#runtime-overrides) will be treated as an entrypoint and guaranteed to be compiled in its entirety. To add additional entrypoints, append URIs to the
`Compiler.entrypoints` array:

```dart
final compiler = Compiler();
compiler.entrypoints.add('package:my_package/some_file.dart');
compiler.compile(...);
```

## Compiling to a file

If possible, it's recommended to pre-compile your Dart code to EVC bytecode,
to avoid runtime compilation overhead. (This is still runtime code execution, it's
just executing a more efficient code format.) Multiple files will be compiled to a
single bytecode block.

```dart
import 'dart:io';
import 'package:dart_eval/dart_eval.dart';

void main() {
  final compiler = Compiler();
  
  final program = compiler.compile({'my_package': {
    'main.dart': '''
      int main() {
        var count = 0;
        for (var i = 0; i < 1000; i++) {
          count += i;
        }
        return count;
      }
    '''
  }});
  
  final bytecode = program.write();
  
  final file = File('program.evc');
  file.writeAsBytesSync(bytecode);
}
```

You can then load and execute the program later:

```dart
import 'dart:io';
import 'package:dart_eval/dart_eval.dart';

void main() {
  final file = File('program.evc');
  final bytecode = file
      .readAsBytesSync()
      .buffer
      .asByteData();
  
  final runtime = Runtime(bytecode);
  print(runtime.executeLib(
    'package:my_package/main.dart', 'main')); // prints '499500'
}
```

## Using the CLI
The dart_eval CLI allows you to compile existing Dart projects to EVC bytecode,
as well as run and inspect EVC bytecode files.

To enable the CLI globally, run:

`dart pub global activate dart_eval`

### Compiling a project

The CLI supports compiling standard Dart projects. To compile a project, run:

```bash
cd my_project
dart_eval compile -o program.evc
```

This will generate an EVC file in the current directory called `program.evc`.
dart_eval will attempt to compile Pub packages, but it's recommended to
avoid them as they may use features that dart_eval doesn't support yet.

The compiler also supports compiling with JSON-encoded bridge bindings. To add
these, create a folder in your project root called `.dart_eval`, add a
`bindings` subfolder, and place JSON binding files there. The compiler will
automatically load these bindings and make them available to your project.

### Running a program

To run the generated EVC file, use:

`dart_eval run program.evc -p package:my_package/main.dart -f main`

Note that the run command does *not* support bindings, so any file compiled
with bindings will need to be run in a specialized runner that includes the
necessary runtime bindings.

### Inspecting an EVC file

You can dump the op codes of an EVC file using:

`dart_eval dump program.evc`

## Return values

Like with arguments, dart_eval will return a `$Value` wrapper for most values
except ints, doubles, bools, and Lists. If you don't like this inconsistency,
specifying a function's return value as `dynamic` will force dart_eval to
always box the return value in a `$Value` wrapper.

> Note that this does not apply to the `eval()` method, which automatically
unboxes all return values for convenience.

## Security and permissions

dart_eval is designed to be secure. The dart_eval runtime functions like a virtual
machine, effectively sandboxing the code it executes. By default, the runtime will
not allow running programs to access the file system, network, or other system 
resources, but these permissions can be enabled on a granular basis using 
`runtime.grant`:

```dart
final runtime = Runtime(bytecode);

// Allow full access to the file system
runtime.grant(FilesystemPermission.any);

// Allow access to a specific network domain
runtime.grant(NetworkPermission.url('example.com'));

// Allow access to a specific network resource
runtime.grant(NetworkPermission.url('https://dart.dev/api/users.json'));

// Using the eval() method
eval(source, permissions: [
  NetworkPermission.any,
  FilesystemReadPermission.directory('/home/user/mydata'), 
  ProcessRunPermission(RegExp(r'^ls$'))
]);
```

Permissions can also be revoked using `runtime.revoke`.

When writing bindings that access sensitive resources, you can check whether a 
permission is enabled by adding the `@AssertPermission` annotation.
Out of the box, dart_eval includes the FilesystemPermission, 
NetworkPermission, and Process(Run/Kill)Permission classes 
('filesystem', 'network', and 'process' domains, respectively)
as well as read/write only variations of FilesystemPermission, but 
you can also create your own custom permissions by implementing the Permission
interface.

## Interop and binding

dart_eval contains a suite of interop features allowing it to work with native
Dart values and vice versa. Core Dart types are all backed by a native Dart value,
and you can access the backing value using the `$value` property of a `$Value`.

To enable your own classes and functions to be used in dart_eval, you can use the 
dart_eval CLI to generate *bindings*, which give the dart_eval compiler and runtime
access to your code. To do this, first annotate your class with the `@Bind` 
annotation from the [eval_annotation](https://pub.dev/packages/eval_annotation) package.
Then, run `dart_eval bind` in your project directory to generate bindings and a plugin
to register them.

For example, to create a wrapper binding for a class `Book`, simply annotate it:

```dart
import 'package:eval_annotation/eval_annotation.dart';

@Bind()
class Book {
  final List<String> pages;

  Book(this.pages);
  String getPage(int index) => pages[index];
}
```

Running `bind` will generate bindings in `book.eval.dart`, as well as an 
`eval_plugin.dart` file containing the plugin. Now, you can use it in dart_eval
by adding the plugin to the `Compiler` and `Runtime`:

```dart
import 'package:dart_eval/dart_eval.dart';

final compiler = Compiler();
compiler.addPlugin(MyAppPlugin());
final program = compiler.compile({'my_package': {
  'main.dart': '''
    import 'package:my_app/book.dart';
    
    Book main() {
      final book = Book(['Page 1', 'Page 2']);
      return book;
    }
  '''
}});

final runtime = Runtime.ofProgram(program);
runtime.addPlugin(MyAppPlugin()); // MyAppPlugin is the generated plugin

final book = runtime.executeLib('package:my_package/main.dart', 'main').$value as Book;
print(book.getPage(0)); // prints 'Page 1'
```

This approach, known as wrapper interop, will allow you to use the `Book` class in dart_eval, 
pass it as an argument, and call its methods. It also exposes a `$Book` wrapper class that 
can be used to wrap an existing `Book` instance, allowing it to be passed to dart_eval.

However, if we instead want to to extend the class or use it as an interface, we'll need to 
use a different approach called *bridge interop*. To generate a bridge class, simply change
the `@Bind` annotation to `@Bind(bridge: true)`. Note that using bridge interop will *not* 
allow you to wrap an existing instance of `Book`.

After generating the bridge class, you can use it in dart_eval like this:

```dart
import 'package:dart_eval/dart_eval.dart';
import 'package:my_app/book.dart';

final compiler = Compiler();
compiler.addPlugin(MyAppPlugin());
final program = compiler.compile({'my_package': {
  'main.dart': '''
    import 'package:my_app/book.dart';

    class MyBook extends Book {
      MyBook(super.pages);

      @override
      String getPage(int index) {
        return 'MyBook: ${super.getPage(index)}';
      }
    }

    MyBook main() {
      final book = MyBook(['Page 1', 'Page 2']);
      return book;
    }
  '''
}});

final runtime = Runtime.ofProgram(program);
runtime.addPlugin(MyAppPlugin()); // MyAppPlugin is the generated plugin

final book = runtime.executeLib('package:my_package/main.dart', 'main') as Book;
print(book.getPage(0)); // prints 'MyBook: Page 1'
```

If you want to use a class from another Dart package, in some cases you may be able to avoid
cloning the package by simply writing a subclass and adding the `@Bind(implicitSupers: true)` 
annotation, which creates bindings for all inherited methods and properties.

The binding generator also supports binding classes that rely on an
existing plugin by using JSON binding files. To add these, create a folder in your project 
root called `.dart_eval`, add a `bindings` subfolder, and place JSON binding files there.

Currently, the binding generator does not support directly creating JSON bindings, but
they can be created by first generating Dart bindings and then making a script to convert them 
to JSON with a `BridgeSerializer`.

For some specialized use cases, bindings may need to be manually adjusted or written from scratch.
For information about this, refer to the 
[wrapper interop wiki page](https://github.com/ethanblake4/dart_eval/wiki/Wrappers) and 
[bridge interop wiki page](https://github.com/ethanblake4/dart_eval/wiki/Bridge-classes).

## Runtime overrides

dart_eval includes a runtime overrides system that allows you to dynamically 
swap in new implementations of functions and constructors at runtime.
To use it, add a null-coalescing call to the `runtimeOverride()` method
at every spot you want to be able to swap:

```dart
void main() {
  // Give the override a unique ID
  final result = runtimeOverride('#myFunction') ?? myFunction();
  print(result);
}

String myFunction() => 'Original version of string';
```

Note that in some cases you may have to cast the return value of `runtimeOverride`
as dart_eval is unable to specify generic parameters to the Dart type system.

Next, mark a function in the eval code with the @RuntimeOverride annotation:

```dart
@RuntimeOverride('#myFunction')
String myFunction() => 'Updated version of string'
```

Finally, follow the normal instructions to compile and run the program, but
call `loadGlobalOverrides` on the Runtime.
This will set the runtime as the single global runtime for the program, and 
load its overrides to be accessible by hot wrappers.

When the program is run, the runtime will automatically replace the
function call with the new implementation.

Overrides can also be versioned, allowing you to roll out updates to a function
immediately using dart_eval and revert to a new native implementation after
an official update is released. To version an override, simply add a semver
version constraint to the `@RuntimeOverride` annotation:

```dart
@RuntimeOverride('#login_page_get_data', version: '<1.4.0')
```

When running the program, specify its current version by setting the value of
the `runtimeOverrideVersion` global property:

```dart
runtimeOverrideVersion = Version.parse('1.3.0');
```

Now, when the program is run, the runtime will automatically replace the instantiation
only if the app version is less than 1.4.0.

## Contributing

See [Contributing](https://github.com/ethanblake4/dart_eval/blob/master/CONTRIBUTING.md).

## FAQ

### How does it work?

`dart_eval` is a fully Dart-based implementation of a bytecode compiler and runtime. 
First, the Dart analyzer is used to parse the code into an AST (abstract syntax tree). 
Then, the compiler looks at each of the declarations in turn, and recursively compiles
to a linear bytecode format.

For evaluation dart_eval uses Dart's optimized dynamic dispatch. This means each bytecode
is actually a class implementing `EvcOp` and we call its `run()` method to execute it.
Bytecodes can do things like push and pop values on the stack, add numbers, and jump to 
other places in the program, as well as more complex Dart-specific operations like 
create a class.

See the [in-depth overview wiki page](https://github.com/ethanblake4/dart_eval/wiki/In-depth-overview) for more information.

### Does it support Flutter?

Yes! Check out [flutter_eval](https://pub.dev/packages/flutter_eval).

### How fast is it?

Preliminary testing shows that `dart_eval` running in AOT-compiled Dart 
is 10-50x slower than standard AOT Dart and is approximately on par with a 
language like Ruby.
It's important to remember this only applies to code running directly in the 
dart_eval VM, and not any code it interacts with. For example, most Flutter apps spend 
the vast majority of their performance budget in the Flutter framework itself, so the
speed impact of dart_eval is usually negligible.

### Is this allowed in the App Store?

Though Apple's official guidelines are unclear, many popular apps use similar
techniques to dynamically update their code. For example, apps built on
React Native often use its custom Hermes JavaScript engine to enable dynamic 
code updates. Note that Apple is likely to remove apps if they introduce policy 
violations in updates, regardless of the technology used.

## Language feature support table

The following table details the language features supported by dart_eval with native Dart code. Feature support
may vary when bridging.

In addition to the per-feature tests below, [dart_semantics_test.dart](test/dart_semantics_test.dart)
holds 57 edge-case tests asserting that evaluated code matches what the equivalent native
Dart program produces (numeric typing, string handling, null safety, control flow, closures,
classes, collections, patterns, exceptions, and async).

| Feature | Support level | Tests |
| ------- | ------------- | ----- |
| Imports | ✅ | [lib_composition_test.dart](test/lib_composition_test.dart) |
| Exports | ✅ | [lib_composition_test.dart](test/lib_composition_test.dart) |
| `part` / `part of` | ✅ | [lib_composition_test.dart](test/lib_composition_test.dart) |
| `show` and `hide` | ✅ | [lib_composition_test.dart](test/lib_composition_test.dart) |
| Conditional imports | ❌ | N/A |
| Prefixed imports | ✅ | [prefixed_import_test.dart](test/prefixed_import_test.dart) |
| Deferred imports | ❌ | N/A |
| Functions | ✅ | [function_test.dart](test/function_test.dart) |
| Local functions | ✅ (this fork: self-recursion) | [local_fn_test.dart](test/local_fn_test.dart) |
| Anonymous functions | ✅ | [function_test.dart](test/function_test.dart) |
| Arrow functions | ✅ | [function_test.dart](test/function_test.dart) |
| Sync generators | ❌ | N/A |
| Async generators | ❌ | N/A |
| Tear-offs | ✅ | [tearoff_test.dart](test/tearoff_test.dart) |
| For loops | ✅ | [loop_test.dart](test/loop_test.dart) |
| While loops | ✅ | [loop_test.dart](test/loop_test.dart) |
| Do-while loops | ✅ | [loop_test.dart](test/loop_test.dart) |
| For-each loops | ✅ | [loop_test.dart](test/loop_test.dart) |
| Async for-each | ❌ | N/A |
| Switch statements | ✅ | [switch_test.dart](test/switch_test.dart), [switch_break_test.dart](test/switch_break_test.dart) |
| Switch expressions | ✅ (this fork) | [switch_test.dart](test/switch_test.dart) |
| `break` & `continue` | ✅ (this fork adds `continue`; labels ❌) | [loop_test.dart](test/loop_test.dart), [dart_semantics_test.dart](test/dart_semantics_test.dart) |
| If statements | ✅ | [loop_test.dart](test/loop_test.dart) |
| Try-catch | ✅ | [exception_test.dart](test/exception_test.dart), [errors_test.dart](test/errors_test.dart) |
| Try-catch-finally | ✅ (this fork: returns through `finally`) | [exception_test.dart](test/exception_test.dart), [dart_semantics_test.dart](test/dart_semantics_test.dart) |
| Lists | ✅ | [collection_test.dart](test/collection_test.dart) |
| Iterable | ✅ | [collection_test.dart](test/collection_test.dart) |
| Maps | ✅ | [collection_test.dart](test/collection_test.dart) |
| Sets | ✅ | [set_test.dart](test/set_test.dart) |
| Collection `for` | ✅ | [collection_test.dart](test/collection_test.dart) |
| Collection `if` | ✅ | [collection_test.dart](test/collection_test.dart) |
| Spreads | Partial | [collection_test.dart](test/collection_test.dart) |
| Classes | ✅ | [class_test.dart](test/class_test.dart) |
| Class static methods | ✅ | [class_test.dart](test/class_test.dart) |
| Getters and setters | ✅ | [class_test.dart](test/class_test.dart) |
| Static fields | ✅ (this fork: bare-identifier assignment) | [class_test.dart](test/class_test.dart), [dart_semantics_test.dart](test/dart_semantics_test.dart) |
| Operator methods | ✅ | [operator_test.dart](test/operator_test.dart) |
| Factory constructors | ✅ | [class_test.dart](test/class_test.dart) |
| Redirecting constructors | ✅ | [class_test.dart](test/class_test.dart) |
| `new` keyword | ✅ | [class_test.dart](test/class_test.dart) |
| Class inheritance | ✅ | [class_test.dart](test/class_test.dart), [functional1_test.dart](test/functional1_test.dart) |
| Abstract and `implements` | Partial | [hlc_test.dart](test/packages/hlc_test.dart) |
| `this` keyword | ✅ | [class_test.dart](test/class_test.dart) |
| `super` keyword | ✅ | [class_test.dart](test/class_test.dart) |
| Super constructor params | ✅ | [class_test.dart](test/class_test.dart) |
| Mixins | ❌ | N/A |
| Futures | Partial | [async_test.dart](test/async_test.dart) |
| Async/await | ✅ | [async_test.dart](test/async_test.dart) |
| Streams | Partial | [stdlib_test.dart](test/stdlib_test.dart) |
| String interpolation | ✅ | [stdlib_test.dart](test/stdlib_test.dart), [string_test.dart](test/string_test.dart) |
| Enums | Partial (extended in this fork) | [enum_test.dart](test/enum_test.dart) |
| Generic function types | Partial | [function_test.dart](test/function_test.dart) |
| Typedefs | ❌ | N/A |
| Generic classes | Partial | ❌ |
| Type tests (`is`) | ✅ | [expression_test.dart](test/expression_test.dart) |
| Casting (`as`) | ✅ | [expression_test.dart](test/expression_test.dart) |
| `assert` | ✅ | [exception_test.dart](test/exception_test.dart) |
| Null safety | Partial | [dart_semantics_test.dart](test/dart_semantics_test.dart) |
| Late initialization | Partial (this fork: `late`/`late final` fields assignable; once-only check not enforced) | [field_test.dart](test/field_test.dart) |
| Cascades | ✅ | [expression_test.dart](test/expression_test.dart), [dart_semantics_test.dart](test/dart_semantics_test.dart) |
| Ternary expressions | ✅ | [expression_test.dart](test/expression_test.dart) |
| Null coalescing expressions | ✅ (this fork: lazy `??=`) | [expression_test.dart](test/expression_test.dart), [dart_semantics_test.dart](test/dart_semantics_test.dart) |
| Extension methods | Partial (this fork) | [extension_test.dart](test/extension_test.dart) |
| Const expressions | Partial | N/A |
| Isolates | ❌ | N/A |
| Record types | Partial | [records_test.dart](test/records_test.dart) |
| Patterns | Partial (extended in this fork: logical patterns, guards, map/object patterns) | [pattern_test.dart](test/pattern_test.dart), [switch_test.dart](test/switch_test.dart), [dart_semantics_test.dart](test/dart_semantics_test.dart) |

## Features and bugs

Please file feature requests and bugs at the [issue tracker][tracker]. If you need help,
use the [discussion board][discussion].

[tracker]: https://github.com/ethanblake4/dart_eval/issues
[discussion]: https://github.com/ethanblake4/dart_eval/discussions
