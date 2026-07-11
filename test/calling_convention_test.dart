import 'package:dart_eval/src/eval/compiler/builtins.dart';
import 'package:dart_eval/src/eval/compiler/expression/function.dart';
import 'package:dart_eval/src/eval/compiler/offset_tracker.dart';
import 'package:dart_eval/src/eval/compiler/type.dart';
import 'package:dart_eval/src/eval/compiler/variable.dart';
import 'package:test/test.dart';

void main() {
  group('Variable calling convention derivation', () {
    // The Variable constructor is the single source of truth for the calling
    // convention: a Function-typed value with no method offset can only be a
    // closure, so it is forced dynamic even when a stale convention is
    // carried in. Call sites switch on callingConvention alone.
    final functionType = TypeRef(dartCoreFile, 'Function');
    final intType = TypeRef(dartCoreFile, 'int');

    test('Function type without method offset is dynamic', () {
      final v = Variable(0, functionType, boxed: true);
      expect(v.callingConvention, CallingConvention.dynamic);
    });

    test('stale static convention on an offset-less Function is corrected', () {
      // Regression: the for-in loop variable is created as a null placeholder
      // (inferred static) and retyped via copyWith, which used to carry the
      // stale static convention onto a closure and break invoking it.
      final v = Variable(
        0,
        functionType,
        boxed: true,
        callingConvention: CallingConvention.static,
      );
      expect(v.callingConvention, CallingConvention.dynamic);
    });

    test('copyWith retyping to Function re-derives the convention', () {
      final placeholder = Variable(0, intType, boxed: true);
      expect(placeholder.callingConvention, CallingConvention.static);
      final retyped = placeholder.copyWith(type: functionType);
      expect(retyped.callingConvention, CallingConvention.dynamic);
    });

    test('Function type with a method offset defaults to static', () {
      final v = Variable(
        0,
        functionType,
        boxed: true,
        methodOffset: DeferredOrOffset(offset: 1),
      );
      expect(v.callingConvention, CallingConvention.static);
    });

    test('explicit dynamic convention with a method offset is respected', () {
      // Closures and tearoffs know their code offset but still take the
      // dynamic convention (boxed args + RTTI lists).
      final v = Variable(
        0,
        functionType,
        boxed: true,
        methodOffset: DeferredOrOffset(offset: 1),
        callingConvention: CallingConvention.dynamic,
      );
      expect(v.callingConvention, CallingConvention.dynamic);
    });

    test('non-Function type defaults to static', () {
      final v = Variable(0, intType, boxed: false);
      expect(v.callingConvention, CallingConvention.static);
    });
  });
}
