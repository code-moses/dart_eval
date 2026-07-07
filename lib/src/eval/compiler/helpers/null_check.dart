import 'package:dart_eval/src/eval/compiler/builtins.dart';
import 'package:dart_eval/src/eval/compiler/context.dart';
import 'package:dart_eval/src/eval/compiler/type.dart';
import 'package:dart_eval/src/eval/compiler/variable.dart';
import 'package:dart_eval/src/eval/runtime/runtime.dart';
import 'package:dart_eval/src/eval/shared/types.dart';

/// Compiles a runtime check that the boxed variable [V] is not null,
/// returning an unboxed bool [Variable].
Variable compileNotNullCheck(CompilerContext ctx, Variable V) {
  final $null = BuiltinValue().push(ctx).boxIfNeeded(ctx);
  ctx.pushOp(
    CheckEq.make(V.scopeFrameOffset, $null.scopeFrameOffset),
    CheckEq.LEN,
  );
  ctx.pushOp(PushReturnValue.make(), PushReturnValue.LEN);
  final isNull = Variable.alloc(
    ctx,
    CoreTypes.bool.ref(ctx).copyWith(boxed: false),
  );
  ctx.pushOp(LogicalNot.make(isNull.scopeFrameOffset), LogicalNot.LEN);
  return Variable.alloc(ctx, CoreTypes.bool.ref(ctx).copyWith(boxed: false));
}
