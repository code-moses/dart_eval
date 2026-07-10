import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:dart_eval/dart_eval_bridge.dart';
import 'package:dart_eval/src/eval/compiler/builtins.dart';
import 'package:dart_eval/src/eval/compiler/context.dart';
import 'package:dart_eval/src/eval/compiler/errors.dart';
import 'package:dart_eval/src/eval/compiler/expression/binary.dart';
import 'package:dart_eval/src/eval/compiler/expression/expression.dart';
import 'package:dart_eval/src/eval/compiler/helpers/equality.dart';
import 'package:dart_eval/src/eval/compiler/helpers/invoke.dart';
import 'package:dart_eval/src/eval/compiler/macros/branch.dart';
import 'package:dart_eval/src/eval/compiler/reference.dart';
import 'package:dart_eval/src/eval/compiler/statement/statement.dart';
import 'package:dart_eval/src/eval/compiler/type.dart';
import 'package:dart_eval/src/eval/compiler/variable.dart';
import 'package:dart_eval/src/eval/runtime/runtime.dart';

enum PatternBindContext { none, declare, declareFinal, matching }

TypeRef patternTypeBound(
  CompilerContext ctx,
  ListPatternElement pattern, {
  AstNode? source,
  TypeRef? bound,
}) {
  switch (pattern) {
    case ListPattern pat:
      TypeRef? specifiedTypeArg;
      if (pat.typeArguments != null) {
        if (pat.typeArguments!.arguments.length != 1) {
          throw CompileError(
            'List pattern must have exactly one type argument',
            source,
          );
        }
        specifiedTypeArg = TypeRef.fromAnnotation(
          ctx,
          ctx.library,
          pat.typeArguments!.arguments[0],
        );
      }

      for (final element in pat.elements) {
        final elementType = patternTypeBound(
          ctx,
          element,
          source: source,
          bound: specifiedTypeArg,
        );
        if (specifiedTypeArg != null &&
            !elementType.isAssignableTo(ctx, specifiedTypeArg)) {
          throw CompileError(
            'List pattern element type $elementType is not assignable to $specifiedTypeArg',
            source,
          );
        }
      }

      final result = CoreTypes.list
          .ref(ctx)
          .copyWith(specifiedTypeArgs: [?specifiedTypeArg]);
      if (bound != null && !result.isAssignableTo(ctx, bound)) {
        throw CompileError(
          'List pattern type $result is not assignable to bound type $bound',
          source,
        );
      }
      return result;
    case RecordPattern pat:
      final recordFields = <RecordParameterType>[];
      var positionalFields = 0;
      for (final field in pat.fields) {
        recordFields.add(
          RecordParameterType(
            field.name?.name?.lexeme ?? '\$${positionalFields++}',
            patternTypeBound(ctx, field.pattern, source: source),
            field.name != null,
          ),
        );
      }

      final result = CoreTypes.record
          .ref(ctx)
          .copyWith(recordFields: recordFields);

      if (bound != null && !result.isAssignableTo(ctx, bound)) {
        throw CompileError(
          'Record pattern type $result is not assignable to bound type $bound',
          source,
        );
      }
      return result;
    case DeclaredVariablePattern pat:
      return pat.type != null
          ? TypeRef.fromAnnotation(ctx, ctx.library, pat.type!)
          : bound ?? CoreTypes.dynamic.ref(ctx);
    case AssignedVariablePattern pat:
      return IdentifierReference(
        null,
        pat.name.lexeme,
      ).resolveType(ctx, forSet: true, source: source);
    case ParenthesizedPattern pat:
      return patternTypeBound(ctx, pat.pattern, source: source, bound: bound);
    case ObjectPattern pat:
      final type = TypeRef.fromAnnotation(ctx, ctx.library, pat.type);
      if (bound != null && !type.isAssignableTo(ctx, bound)) {
        throw CompileError(
          'Object pattern type $type is not assignable to bound type $bound',
          source,
        );
      }
      return type;
    case MapPattern pat:
      TypeRef? keyType, valueType;
      if (pat.typeArguments != null) {
        if (pat.typeArguments!.arguments.length != 2) {
          throw CompileError(
            'Map pattern must have exactly two type arguments',
            source,
          );
        }
        keyType = TypeRef.fromAnnotation(
          ctx,
          ctx.library,
          pat.typeArguments!.arguments[0],
        );
        valueType = TypeRef.fromAnnotation(
          ctx,
          ctx.library,
          pat.typeArguments!.arguments[1],
        );
      }
      final result = CoreTypes.map
          .ref(ctx)
          .copyWith(
            specifiedTypeArgs: [
              if (keyType != null && valueType != null) ...[keyType, valueType],
            ],
          );
      if (bound != null && !result.isAssignableTo(ctx, bound)) {
        throw CompileError(
          'Map pattern type $result is not assignable to bound type $bound',
          source,
        );
      }
      return result;
    case WildcardPattern pat:
      final typeAnnotation = pat.type;
      if (typeAnnotation == null) {
        return bound ?? CoreTypes.dynamic.ref(ctx);
      }
      final type = TypeRef.fromAnnotation(ctx, ctx.library, typeAnnotation);
      if (bound != null && !type.isAssignableTo(ctx, bound)) {
        throw CompileError(
          'Wildcard pattern type $type is not assignable to bound type $bound',
          source,
        );
      }
      return type;
    default:
      throw CompileError(
        "Refutable patterns can't be used in an irrefutable context."
        "Try using an if-case, a 'switch' statement, or a 'switch' expression instead.",
        source,
      );
  }
}

/// Matches [guardedPattern]'s pattern against [V], binding any pattern
/// variables, and applies the optional `when` guard with proper
/// short-circuiting: the guard is only evaluated when the pattern matched, so
/// pattern-bound variables are never used before the match succeeds (e.g. a
/// promoted `int n` guard is not run against a non-int subject).
Variable patternMatchAndBindGuarded(
  CompilerContext ctx,
  GuardedPattern guardedPattern,
  Variable V, {
  PatternBindContext patternContext = PatternBindContext.none,
}) {
  final matches = patternMatchAndBind(
    ctx,
    guardedPattern.pattern,
    V,
    patternContext: patternContext,
  );
  final guard = guardedPattern.whenClause;
  if (guard == null) {
    return matches;
  }

  // Evaluate the guard only when the pattern matched. Store the outcome in a
  // result variable defaulting to false, so a non-match skips the guard ops.
  final resultName = '#guard${ctx.out.length}';
  ctx.setLocal(resultName, BuiltinValue(boolval: false).push(ctx));
  final vRef = IdentifierReference(null, resultName);
  macroBranch(
    ctx,
    null,
    condition: (ctx) => matches,
    thenBranch: (ctx, rt) {
      final guardResult = compileExpression(guard.expression, ctx);
      vRef.setValue(ctx, guardResult);
      return StatementInfo(-1);
    },
    source: guard,
  );
  return vRef.getValue(ctx).updated(ctx);
}

/// Reads [prop] from [V], evaluating to null when [V] is null instead of
/// throwing. Used so structural pattern matching against a null subject (e.g.
/// an out-of-range element of a shorter list) fails the match cleanly rather
/// than crashing on a property access.
Variable _nullSafeGetProperty(CompilerContext ctx, Variable V, String prop) {
  V = V.boxIfNeeded(ctx);
  var out = BuiltinValue().push(ctx).boxIfNeeded(ctx);
  macroBranch(
    ctx,
    null,
    condition: (ctx) => checkNotNull(ctx, V),
    thenBranch: (ctx, rt) {
      final val = V.getProperty(ctx, prop).boxIfNeeded(ctx);
      out = out.copyWith(
        type: val.type.copyWith(nullable: true),
        concreteTypes: [],
      );
      ctx.pushOp(
        CopyValue.make(out.scopeFrameOffset, val.scopeFrameOffset),
        CopyValue.LEN,
      );
      return StatementInfo(-1);
    },
  );
  return out;
}

/// Returns the length of list [V], or -1 when [V] is null, as an unboxed int.
/// Using -1 for null lets a length comparison (`==` or `>=`) fail the match
/// without a null-comparison crash.
Variable _listLengthOrNeg(CompilerContext ctx, Variable V) {
  V = V.boxIfNeeded(ctx);
  final out = BuiltinValue(intval: -1).push(ctx);
  macroBranch(
    ctx,
    null,
    condition: (ctx) => checkNotNull(ctx, V),
    thenBranch: (ctx, rt) {
      final len = V.getProperty(ctx, 'length').unboxIfNeeded(ctx);
      ctx.pushOp(
        CopyValue.make(out.scopeFrameOffset, len.scopeFrameOffset),
        CopyValue.LEN,
      );
      return StatementInfo(-1);
    },
  );
  return out;
}

Variable patternMatchAndBind(
  CompilerContext ctx,
  ListPatternElement pattern,
  Variable V, {
  PatternBindContext patternContext = PatternBindContext.none,
}) {
  switch (pattern) {
    case ConstantPattern pat:
      final constant = compileExpression(pat.expression, ctx);
      return V.invoke(ctx, '==', [constant]).result;
    case RecordPattern pat:
      var positionalFields = 1;
      Variable? result;
      for (final field in pat.fields) {
        final fieldName = field.effectiveName ?? '\$${positionalFields++}';
        // Null-safe field access so a record pattern matched against a null
        // subject (e.g. an out-of-range list element) fails cleanly
        final fieldResult = patternMatchAndBind(
          ctx,
          field.pattern,
          _nullSafeGetProperty(ctx, V, fieldName),
          patternContext: patternContext,
        );
        if (result == null) {
          result = fieldResult;
        } else {
          result = result.invoke(ctx, '&&', [fieldResult]).result;
        }
      }
      return result ??
          (throw CompileError(
            'Record pattern matching failed, no fields matched',
            pattern,
          ));
    case ListPattern pat:
      // A list pattern with a rest element (`...` / `...rest`) matches lists of
      // length >= (elements before + after the rest); a plain list pattern
      // matches lists of exactly its length. Elements before the rest match
      // from the start, elements after it from the end, and the rest binds the
      // middle sublist. At most one rest element is allowed.
      final elements = pat.elements;
      final restIdx = elements.indexWhere((e) => e is RestPatternElement);
      final hasRest = restIdx != -1;
      if (hasRest &&
          elements.skip(restIdx + 1).any((e) => e is RestPatternElement)) {
        throw CompileError(
          'A list pattern can have at most one rest element',
          pattern,
        );
      }
      final before = hasRest ? elements.sublist(0, restIdx) : elements;
      final after = hasRest
          ? elements.sublist(restIdx + 1)
          : const <ListPatternElement>[];
      final restPattern = hasRest
          ? (elements[restIdx] as RestPatternElement).pattern
          : null;
      final minLen = before.length + after.length;

      // Compute the length safely (-1 when the subject is null) so a null or
      // wrong-length subject fails the match cleanly instead of throwing.
      V = V.boxIfNeeded(ctx);
      final length = _listLengthOrNeg(ctx, V);
      final lengthOk =
          (hasRest
                  ? length.invoke(ctx, '>=', [
                      BuiltinValue(intval: minLen).push(ctx),
                    ])
                  : length.invoke(ctx, '==', [
                      BuiltinValue(intval: minLen).push(ctx),
                    ]))
              .result
              .unboxIfNeeded(ctx);

      // Result slots (default null) that survive to the matching below. The
      // extraction is gated on the length matching, so indices are only read
      // when the subject is non-null and long enough — never out of range.
      final beforeSlots = [
        for (var i = 0; i < before.length; i++)
          BuiltinValue().push(ctx).boxIfNeeded(ctx),
      ];
      final afterSlots = [
        for (var j = 0; j < after.length; j++)
          BuiltinValue().push(ctx).boxIfNeeded(ctx),
      ];
      var restSlot = restPattern != null
          ? BuiltinValue().push(ctx).boxIfNeeded(ctx)
          : null;

      Variable storeElement(Variable slot, Variable el) =>
          _storeInto(ctx, slot, el);

      macroBranch(
        ctx,
        null,
        condition: (ctx) => lengthOk,
        thenBranch: (ctx, rt) {
          // Bind the rest sublist first, while V is still boxed (sublist is a
          // method call and needs a boxed receiver).
          if (restPattern != null) {
            final start = BuiltinValue(intval: before.length).push(ctx);
            final end = after.isEmpty
                ? length
                : length.invoke(ctx, '-', [
                    BuiltinValue(intval: after.length).push(ctx),
                  ]).result;
            final sub = V
                .invoke(ctx, 'sublist', [start, end])
                .result
                .boxIfNeeded(ctx);
            restSlot = storeElement(restSlot!, sub);
          }
          // Unbox once so element access indexes a raw list without re-emitting
          // an Unbox per element (which would double-unbox nested sublists).
          final rawV = V.unboxIfNeeded(ctx);
          for (var i = 0; i < before.length; i++) {
            final el = IndexedReference(
              rawV,
              BuiltinValue(intval: i).push(ctx),
            ).getValue(ctx).boxIfNeeded(ctx);
            beforeSlots[i] = storeElement(beforeSlots[i], el);
          }
          for (var j = 0; j < after.length; j++) {
            // index = length - (after.length - j), counting from the end
            final idx = length.invoke(ctx, '-', [
              BuiltinValue(intval: after.length - j).push(ctx),
            ]).result;
            final el = IndexedReference(
              rawV,
              idx,
            ).getValue(ctx).boxIfNeeded(ctx);
            afterSlots[j] = storeElement(afterSlots[j], el);
          }
          return StatementInfo(-1);
        },
      );

      Variable result = lengthOk;
      for (var i = 0; i < before.length; i++) {
        final m = patternMatchAndBind(
          ctx,
          before[i],
          beforeSlots[i],
          patternContext: patternContext,
        );
        result = result.invoke(ctx, '&&', [m]).result;
      }
      for (var j = 0; j < after.length; j++) {
        final m = patternMatchAndBind(
          ctx,
          after[j],
          afterSlots[j],
          patternContext: patternContext,
        );
        result = result.invoke(ctx, '&&', [m]).result;
      }
      if (restPattern != null) {
        final m = patternMatchAndBind(
          ctx,
          restPattern,
          restSlot!,
          patternContext: patternContext,
        );
        result = result.invoke(ctx, '&&', [m]).result;
      }
      return result;
    case MapPattern pat:
      // A map pattern matches when the subject is a Map that contains every
      // listed key and each value sub-pattern matches the mapped value. A null
      // or non-Map subject, or a missing key, fails the match cleanly. Key and
      // value lookups are gated on the is-Map test so they never run against a
      // non-map subject.
      final entries = <MapPatternEntry>[
        for (final el in pat.elements)
          if (el is MapPatternEntry)
            el
          else
            throw CompileError(
              'Map patterns do not support rest elements',
              pattern,
            ),
      ];
      final mapType = CoreTypes.map.ref(ctx);
      V = V.boxIfNeeded(ctx);
      final isMap = _typeTestRef(ctx, mapType, V);
      final probe = V.copyWith(
        type: mapType.copyWith(boxed: true),
        concreteTypes: const [],
      );

      // Surviving slots: whether each key is present, and the mapped value.
      final presentSlots = [
        for (var i = 0; i < entries.length; i++)
          BuiltinValue(boolval: false).push(ctx),
      ];
      final valueSlots = [
        for (var i = 0; i < entries.length; i++)
          BuiltinValue().push(ctx).boxIfNeeded(ctx),
      ];

      macroBranch(
        ctx,
        null,
        condition: (ctx) => isMap,
        thenBranch: (ctx, rt) {
          for (var i = 0; i < entries.length; i++) {
            // Box the key once so both lookups reuse the same boxed slot; an
            // invoke boxes its args in place, which would otherwise leave the
            // second use double-boxing a stale reference.
            final key = compileExpression(entries[i].key, ctx).boxIfNeeded(ctx);
            final contains = probe
                .invoke(ctx, 'containsKey', [key])
                .result
                .unboxIfNeeded(ctx);
            ctx.pushOp(
              CopyValue.make(
                presentSlots[i].scopeFrameOffset,
                contains.scopeFrameOffset,
              ),
              CopyValue.LEN,
            );
            final val = probe.invoke(ctx, '[]', [key]).result.boxIfNeeded(ctx);
            valueSlots[i] = _storeInto(ctx, valueSlots[i], val);
          }
          return StatementInfo(-1);
        },
      );

      Variable mapResult = isMap;
      for (var i = 0; i < entries.length; i++) {
        mapResult = mapResult.invoke(ctx, '&&', [presentSlots[i]]).result;
        final m = patternMatchAndBind(
          ctx,
          entries[i].value,
          valueSlots[i],
          patternContext: patternContext,
        );
        mapResult = mapResult.invoke(ctx, '&&', [m]).result;
      }
      return mapResult;
    case ObjectPattern pat:
      // An object pattern matches when the subject is an instance of the named
      // type and every field sub-pattern matches the corresponding getter. The
      // getter reads are gated on the type test so they never run against a
      // wrong-typed or null subject.
      final patType = TypeRef.fromAnnotation(ctx, ctx.library, pat.type);
      V = V.boxIfNeeded(ctx);
      final typeMatches = _typeTestRef(ctx, patType, V);
      // Promote the subject to the pattern's type (safe inside the gate) so
      // getters resolve statically rather than through dynamic dispatch.
      final promoted = V.copyWith(
        type: patType.copyWith(boxed: V.boxed),
        concreteTypes: const [],
      );

      final fieldSlots = [
        for (var i = 0; i < pat.fields.length; i++)
          BuiltinValue().push(ctx).boxIfNeeded(ctx),
      ];

      macroBranch(
        ctx,
        null,
        condition: (ctx) => typeMatches,
        thenBranch: (ctx, rt) {
          for (var i = 0; i < pat.fields.length; i++) {
            final getterName =
                pat.fields[i].effectiveName ??
                (throw CompileError(
                  'Object pattern fields must be named',
                  pattern,
                ));
            final val = promoted.getProperty(ctx, getterName).boxIfNeeded(ctx);
            fieldSlots[i] = _storeInto(ctx, fieldSlots[i], val);
          }
          return StatementInfo(-1);
        },
      );

      Variable objResult = typeMatches;
      for (var i = 0; i < pat.fields.length; i++) {
        final m = patternMatchAndBind(
          ctx,
          pat.fields[i].pattern,
          fieldSlots[i],
          patternContext: patternContext,
        );
        objResult = objResult.invoke(ctx, '&&', [m]).result;
      }
      return objResult;
    case VariablePattern pat:
      final variableName = pat.name.lexeme;
      final declare =
          patternContext == PatternBindContext.declare ||
          patternContext == PatternBindContext.declareFinal ||
          (patternContext == PatternBindContext.matching &&
              pat is DeclaredVariablePattern);
      if (declare && ctx.locals.last.containsKey(variableName)) {
        throw CompileError(
          'Cannot declare variable $variableName'
          ' multiple times in the same scope',
        );
      }
      final isFinal =
          patternContext == PatternBindContext.declareFinal ||
          (pat is DeclaredVariablePattern &&
              pat.keyword != null &&
              pat.keyword!.keyword == Keyword.FINAL);
      // A typed variable pattern (e.g. `int n`) binds the variable at the
      // pattern's declared type, promoting it past the subject's static type
      // so that e.g. `if (o case int n) n + 1` works. The runtime type test
      // below guarantees the value matches that type.
      final declaredType = (pat is DeclaredVariablePattern && pat.type != null)
          ? TypeRef.fromAnnotation(ctx, ctx.library, pat.type!)
          : null;
      // If the variable is already in scope, we need to copy it to a new stack slot
      if (V.name != null) {
        if (!(V.type.isUnboxedAcrossFunctionBoundaries)) {
          V = V.boxIfNeeded(ctx);
        }
        final boundType = (declaredType ?? V.type).copyWith(boxed: V.boxed);
        // The new slot is a copy of V, so it shares V's representation.
        var v = Variable.alloc(
          ctx,
          boundType,
          boxed: V.boxed,
          isFinal: isFinal,
        );
        ctx.pushOp(PushNull.make(), PushNull.LEN);
        ctx.pushOp(
          CopyValue.make(v.scopeFrameOffset, V.scopeFrameOffset),
          CopyValue.LEN,
        );
        ctx.setLocal(variableName, v);
      } else {
        ctx.setLocal(
          variableName,
          V.copyWith(
            type: (declaredType ?? V.type).copyWith(boxed: V.boxed),
            isFinal: isFinal,
          ),
        );
      }

      if (pat is DeclaredVariablePattern) {
        return _typeTest(ctx, pat.type, V);
      }

      return BuiltinValue(boolval: true).push(ctx);
    case RelationalPattern pat:
      final operand = compileExpression(pat.operand, ctx);
      final operator =
          binaryOpMap[pat.operator.type] ??
          (throw CompileError(
            'Unknown relational operator ${pat.operator.type}',
          ));
      return V.invoke(ctx, operator, [operand]).result;
    case WildcardPattern pat:
      return _typeTest(ctx, pat.type, V);
    case ParenthesizedPattern pat:
      return patternMatchAndBind(
        ctx,
        pat.pattern,
        V,
        patternContext: patternContext,
      );
    default:
      throw CompileError('Unsupported pattern type: ${pattern.runtimeType}');
  }
}

Variable _typeTest(CompilerContext ctx, TypeAnnotation? patType, Variable V) {
  final slot = patType != null
      ? TypeRef.fromAnnotation(ctx, ctx.library, patType)
      : CoreTypes.dynamic.ref(ctx);
  return _typeTestRef(ctx, slot, V);
}

/// Emits a runtime `is [slot]` test on [V], collapsing to a constant `true`
/// when the static type already guarantees the match. The test is null-safe: a
/// null subject matches only when [slot] is nullable, and the `IsType` op —
/// which requires a `$Value` — is guarded so a raw or boxed null (e.g. an
/// absent map key) yields a clean boolean instead of a cast error.
Variable _typeTestRef(CompilerContext ctx, TypeRef slot, Variable V) {
  V.inferType(ctx, slot);
  if (V.type.isAssignableTo(ctx, slot, forceAllowDynamic: false)) {
    return BuiltinValue(boolval: true).push(ctx);
  }

  V = V.boxIfNeeded(ctx);
  final result = BuiltinValue(boolval: slot.nullable).push(ctx);
  macroBranch(
    ctx,
    null,
    condition: (ctx) => checkNotNull(ctx, V),
    thenBranch: (ctx, rt) {
      ctx.pushOp(
        IsType.make(V.scopeFrameOffset, ctx.typeRefIndexMap[slot]!, false),
        IsType.length,
      );
      final isType = Variable.alloc(ctx, CoreTypes.bool.ref(ctx), boxed: false);
      ctx.pushOp(
        CopyValue.make(result.scopeFrameOffset, isType.scopeFrameOffset),
        CopyValue.LEN,
      );
      return StatementInfo(-1);
    },
  );
  return result;
}

/// Copies [val] into the pre-allocated surviving [slot], preserving val's
/// (nullable) type so a nested sub-pattern keeps a precise element type rather
/// than falling back to a dynamic dispatch. Used to hoist values extracted
/// inside a gated branch out to slots that outlive the branch's alloc scope.
Variable _storeInto(CompilerContext ctx, Variable slot, Variable val) {
  final out = slot.copyWith(
    type: val.type.copyWith(nullable: true),
    concreteTypes: const [],
  );
  ctx.pushOp(
    CopyValue.make(out.scopeFrameOffset, val.scopeFrameOffset),
    CopyValue.LEN,
  );
  return out;
}
