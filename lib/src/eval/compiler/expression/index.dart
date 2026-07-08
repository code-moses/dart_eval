import 'package:analyzer/dart/ast/ast.dart';
import 'package:dart_eval/src/eval/compiler/builtins.dart';
import 'package:dart_eval/src/eval/compiler/context.dart';
import 'package:dart_eval/src/eval/compiler/expression/expression.dart';
import 'package:dart_eval/src/eval/compiler/helpers/equality.dart';
import 'package:dart_eval/src/eval/compiler/macros/branch.dart';
import 'package:dart_eval/src/eval/compiler/reference.dart';
import 'package:dart_eval/src/eval/compiler/statement/statement.dart';
import 'package:dart_eval/src/eval/compiler/type.dart';
import 'package:dart_eval/src/eval/runtime/runtime.dart';
import 'package:dart_eval/dart_eval_bridge.dart';

import '../variable.dart';

Reference compileIndexExpressionAsReference(
  IndexExpression e,
  CompilerContext ctx, {
  Variable? cascadeTarget,
}) {
  final value = cascadeTarget ?? compileExpression(e.realTarget, ctx);
  final index = compileExpression(e.index, ctx);
  return IndexedReference(value, index);
}

Variable compileIndexExpression(
  IndexExpression e,
  CompilerContext ctx, {
  Variable? cascadeTarget,
}) {
  if (e.isNullAware) {
    return _compileNullAwareIndex(e, ctx, cascadeTarget: cascadeTarget);
  }
  return compileIndexExpressionAsReference(
    e,
    ctx,
    cascadeTarget: cascadeTarget,
  ).getValue(ctx);
}

/// Compiles a null-aware index access (`target?[index]`): evaluates to null
/// when the target is null, otherwise to `target[index]`.
Variable _compileNullAwareIndex(
  IndexExpression e,
  CompilerContext ctx, {
  Variable? cascadeTarget,
}) {
  final target = (cascadeTarget ?? compileExpression(e.realTarget, ctx))
      .boxIfNeeded(ctx);

  var out = BuiltinValue().push(ctx).boxIfNeeded(ctx);
  // If the target is statically known to be null, the access is always null
  if (target.concreteTypes.length == 1 &&
      target.concreteTypes[0] == CoreTypes.nullType.ref(ctx)) {
    return out;
  }

  macroBranch(
    ctx,
    null,
    condition: (ctx) => checkNotEqual(ctx, target, out),
    thenBranch: (ctx, rt) {
      final index = compileExpression(e.index, ctx);
      final V = IndexedReference(target, index).getValue(ctx).boxIfNeeded(ctx);
      out = out.copyWith(
        type: V.type.copyWith(nullable: true),
        concreteTypes: [],
      );
      ctx.pushOp(
        CopyValue.make(out.scopeFrameOffset, V.scopeFrameOffset),
        CopyValue.LEN,
      );
      return StatementInfo(-1);
    },
    source: e,
  );

  return out;
}
