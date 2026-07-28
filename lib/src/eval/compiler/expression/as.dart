import 'package:analyzer/dart/ast/ast.dart';
import 'package:dart_eval/dart_eval_bridge.dart';
import 'package:dart_eval/src/eval/compiler/builtins.dart';
import 'package:dart_eval/src/eval/compiler/context.dart';
import 'package:dart_eval/src/eval/compiler/expression/expression.dart';
import 'package:dart_eval/src/eval/compiler/helpers/invoke.dart';
import 'package:dart_eval/src/eval/compiler/helpers/null_check.dart';
import 'package:dart_eval/src/eval/compiler/macros/branch.dart';
import 'package:dart_eval/src/eval/compiler/statement/statement.dart';
import 'package:dart_eval/src/eval/compiler/type.dart';
import 'package:dart_eval/src/eval/compiler/variable.dart';
import 'package:dart_eval/src/eval/runtime/runtime.dart';
import 'package:dart_eval/src/eval/shared/types.dart';

Variable compileAsExpression(AsExpression e, CompilerContext ctx) {
  var V = compileExpression(e.expression, ctx);
  final slot = TypeRef.fromAnnotation(ctx, ctx.library, e.type);

  // If the value's type already fits the slot including nullability, we can
  // just return. TypeRef == ignores nullability, so a nullable value cast to
  // a non-nullable type must fall through to the runtime null test.
  if (V.type == slot && (!V.type.nullable || slot.nullable)) {
    return V;
  }

  // Special case: if casting null to a nullable type, allow it
  if (V.type == CoreTypes.nullType.ref(ctx) && slot.nullable) {
    return V.copyWithUpdate(ctx, type: slot);
  }

  if (ctx.softNumericCasts) {
    final soft = _compileSoftNumericCast(ctx, V, slot, e);
    if (soft != null) {
      return soft;
    }
  }

  // If the value is statically known to fit the slot, the cast can never
  // fail and no runtime test is needed. A nullable static type may still
  // hold null at runtime, so this requires the slot to accept null too.
  final staticallyFits =
      (!V.type.nullable || slot.nullable) &&
      V.type.isAssignableTo(ctx, slot, forceAllowDynamic: false);

  if (!staticallyFits) {
    // The IsType op requires a boxed value
    V = V.boxIfNeeded(ctx);

    if (slot.nullable) {
      if (ctx.softNullableCasts) {
        return _compileSoftCast(ctx, V, slot, e);
      }

      // A nullable cast accepts null, so only run the type test when the
      // runtime value is non-null.
      macroBranch(
        ctx,
        null,
        condition: (ctx) => compileNotNullCheck(ctx, V),
        thenBranch: (ctx, rt) {
          _typeTestAndAssert(ctx, V, slot);
          return StatementInfo(-1);
        },
      );
      return V.copyWithUpdate(ctx, type: slot.copyWith(boxed: true));
    }

    // Otherwise type-test and assert
    _typeTestAndAssert(ctx, V, slot);
  }

  // If the type changes between num and int/double, unbox/box
  if (slot == CoreTypes.num.ref(ctx)) {
    V = V.boxIfNeeded(ctx);
  } else if (slot == CoreTypes.int.ref(ctx) ||
      slot == CoreTypes.double.ref(ctx)) {
    V = V.unboxIfNeeded(ctx);
  }

  // For all other types, just inform the compiler
  // (todo) Mixins may need different behavior
  return V.copyWithUpdate(ctx, type: slot.copyWith(boxed: V.type.boxed));
}

/// Compiles a soft numeric cast (see [Compiler.softNumericCasts]): casting a
/// numeric value to `int` or `double` converts it with toInt()/toDouble()
/// instead of throwing. Returns null if the cast is not numeric-convertible
/// (leaving the standard cast logic to handle it): the target must be
/// int/double, and the value must be statically numeric, `dynamic`, `Object`,
/// or a nullable numeric. Null and non-num runtime values keep standard cast
/// semantics.
Variable? _compileSoftNumericCast(
  CompilerContext ctx,
  Variable V,
  TypeRef slot,
  AsExpression e,
) {
  final intType = CoreTypes.int.ref(ctx);
  final doubleType = CoreTypes.double.ref(ctx);
  final numType = CoreTypes.num.ref(ctx);

  // Only int and double targets need conversion; a numeric value already is
  // a num, so `as num` works natively. (TypeRef == ignores nullability.)
  if (slot != intType && slot != doubleType) {
    return null;
  }
  final method = slot == intType ? 'toInt' : 'toDouble';

  // A literal null must keep failing on non-nullable targets
  if (V.type == CoreTypes.nullType.ref(ctx)) {
    return null;
  }

  // A statically-known, non-nullable numeric value can be converted directly.
  // (An exact type match was already returned by the caller.)
  if (!V.type.nullable &&
      V.type.isAssignableTo(ctx, numType, forceAllowDynamic: false)) {
    var conv = V.invoke(ctx, method, []).result;
    if (!slot.nullable) {
      conv = conv.unboxIfNeeded(ctx);
    }
    return conv.copyWith(
      type: slot.copyWith(boxed: conv.type.boxed),
      concreteTypes: [],
    );
  }

  // Otherwise the value must at least possibly hold a num at runtime
  final couldBeNum =
      V.type == CoreTypes.dynamic.ref(ctx) ||
      V.type == CoreTypes.object.ref(ctx) ||
      V.type
          .copyWith(nullable: false)
          .isAssignableTo(ctx, numType, forceAllowDynamic: false);
  if (!couldBeNum) {
    return null;
  }

  // out = V is num ? V.toInt()/toDouble() : <standard cast semantics>
  V = V.boxIfNeeded(ctx);
  final out = BuiltinValue().push(ctx).boxIfNeeded(ctx);
  ctx.pushOp(
    IsType.make(V.scopeFrameOffset, ctx.typeRefIndexMap[numType]!, false),
    IsType.length,
  );
  final vIsNum = Variable.alloc(ctx, CoreTypes.bool.ref(ctx), boxed: false);
  macroBranch(
    ctx,
    null,
    condition: (ctx) => vIsNum,
    thenBranch: (ctx, rt) {
      final conv = V.invoke(ctx, method, []).result.boxIfNeeded(ctx);
      ctx.pushOp(
        CopyValue.make(out.scopeFrameOffset, conv.scopeFrameOffset),
        CopyValue.LEN,
      );
      return StatementInfo(-1);
    },
    elseBranch: (ctx, rt) {
      // Not a num: standard cast semantics. A non-num value can never satisfy
      // an int/double test, so the only passing case is null to a nullable
      // target — where [out] already holds null.
      if (slot.nullable) {
        if (!ctx.softNullableCasts) {
          macroBranch(
            ctx,
            null,
            condition: (ctx) => compileNotNullCheck(ctx, V),
            thenBranch: (ctx, rt) {
              _typeTestAndAssert(ctx, V, slot);
              return StatementInfo(-1);
            },
          );
        }
      } else {
        _typeTestAndAssert(ctx, V, slot);
      }
      return StatementInfo(-1);
    },
    source: e,
  );
  // Clear the null concreteTypes inherited from the null initializer (see
  // _compileSoftCast)
  return out.copyWith(type: slot.copyWith(boxed: true), concreteTypes: []);
}

/// Compiles a soft cast to a nullable type (see [Compiler.softNullableCasts]):
/// evaluates to the value if it matches the type, and to null otherwise,
/// similar to the C# 'as' operator. [V] must be boxed.
Variable _compileSoftCast(
  CompilerContext ctx,
  Variable V,
  TypeRef slot,
  AsExpression e,
) {
  // out = (V != null && V is T) ? V : null
  final out = BuiltinValue().push(ctx).boxIfNeeded(ctx);
  macroBranch(
    ctx,
    null,
    condition: (ctx) => compileNotNullCheck(ctx, V),
    thenBranch: (ctx, rt) {
      ctx.pushOp(
        IsType.make(V.scopeFrameOffset, ctx.typeRefIndexMap[slot]!, false),
        IsType.length,
      );
      final vIs = Variable.alloc(ctx, CoreTypes.bool.ref(ctx), boxed: false);
      macroBranch(
        ctx,
        null,
        condition: (ctx) => vIs,
        thenBranch: (ctx, rt) {
          ctx.pushOp(
            CopyValue.make(out.scopeFrameOffset, V.scopeFrameOffset),
            CopyValue.LEN,
          );
          return StatementInfo(-1);
        },
        source: e,
      );
      return StatementInfo(-1);
    },
    source: e,
  );
  // Clear the null concreteTypes inherited from the null initializer, or
  // downstream null-aware operators would short-circuit unconditionally
  return out.copyWith(type: slot.copyWith(boxed: true), concreteTypes: []);
}

void _typeTestAndAssert(CompilerContext ctx, Variable V, TypeRef slot) {
  ctx.pushOp(
    IsType.make(V.scopeFrameOffset, ctx.typeRefIndexMap[slot]!, false),
    IsType.length,
  );
  final vIs = Variable.alloc(ctx, CoreTypes.bool.ref(ctx), boxed: false);

  final errMsg = BuiltinValue(
    stringval: "TypeError: Not a subtype of type ${slot.name}",
  ).push(ctx);
  ctx.pushOp(
    Assert.make(vIs.scopeFrameOffset, errMsg.scopeFrameOffset),
    Assert.LEN,
  );
}
