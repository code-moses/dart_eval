import 'package:analyzer/dart/ast/ast.dart';
import 'package:dart_eval/src/eval/compiler/builtins.dart';
import 'package:dart_eval/src/eval/compiler/context.dart';
import 'package:dart_eval/src/eval/compiler/expression/expression.dart';
import 'package:dart_eval/src/eval/compiler/helpers/null_check.dart';
import 'package:dart_eval/src/eval/compiler/macros/branch.dart';
import 'package:dart_eval/src/eval/compiler/statement/statement.dart';
import 'package:dart_eval/src/eval/compiler/type.dart';
import 'package:dart_eval/src/eval/compiler/variable.dart';
import 'package:dart_eval/src/eval/runtime/runtime.dart';
import 'package:dart_eval/src/eval/shared/types.dart';

Variable compileIsExpression(IsExpression e, CompilerContext ctx) {
  var V = compileExpression(e.expression, ctx);
  final slot = TypeRef.fromAnnotation(ctx, ctx.library, e.type);
  final not = e.notOperator != null;

  V.inferType(ctx, slot);

  /// If the type is definitely a subtype of the slot, we can just return true.
  /// A nullable static type may still hold null at runtime, so unless the slot
  /// accepts null too the test must be performed at runtime.
  if ((!V.type.nullable || slot.nullable) &&
      V.type.isAssignableTo(ctx, slot, forceAllowDynamic: false)) {
    return BuiltinValue(boolval: !not).push(ctx);
  }

  V = V.boxIfNeeded(ctx);

  if (slot.nullable) {
    // `null is T?` evaluates to true, but the IsType op has no nullability
    // awareness, so only run the type test when the value is non-null.
    final outVar = BuiltinValue(boolval: !not).push(ctx);
    final boxedV = V;
    macroBranch(
      ctx,
      null,
      condition: (ctx) => compileNotNullCheck(ctx, boxedV),
      thenBranch: (ctx, rt) {
        ctx.pushOp(
          IsType.make(boxedV.scopeFrameOffset, ctx.typeRefIndexMap[slot]!, not),
          IsType.length,
        );
        final vIs = Variable.alloc(ctx, CoreTypes.bool.ref(ctx), boxed: false);
        ctx.pushOp(
          CopyValue.make(outVar.scopeFrameOffset, vIs.scopeFrameOffset),
          CopyValue.LEN,
        );
        return StatementInfo(-1);
      },
    );
    return outVar;
  }

  /// Otherwise do a runtime test
  ctx.pushOp(
    IsType.make(V.scopeFrameOffset, ctx.typeRefIndexMap[slot]!, not),
    IsType.length,
  );
  return Variable.alloc(ctx, CoreTypes.bool.ref(ctx), boxed: false);
}
