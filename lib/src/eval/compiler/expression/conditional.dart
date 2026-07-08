import 'package:analyzer/dart/ast/ast.dart';
import 'package:dart_eval/dart_eval_bridge.dart';
import 'package:dart_eval/src/eval/compiler/builtins.dart';
import 'package:dart_eval/src/eval/compiler/context.dart';
import 'package:dart_eval/src/eval/compiler/macros/branch.dart';
import 'package:dart_eval/src/eval/compiler/reference.dart';
import 'package:dart_eval/src/eval/compiler/statement/statement.dart';
import 'package:dart_eval/src/eval/compiler/type.dart';
import 'package:dart_eval/src/eval/compiler/variable.dart';

import '../errors.dart';
import 'expression.dart';

/// Compile a [ConditionalExpression] to EVC bytecode
Variable compileConditionalExpression(
  CompilerContext ctx,
  ConditionalExpression e, [
  TypeRef? boundType,
]) {
  // The name must be unique so that nested conditional expressions don't
  // shadow each other's result variable. Initialize it as a *boxed* null:
  // both branches store a boxed value, so a boxed placeholder keeps the
  // result variable's boxing state continuous across the branch merge.
  final resultName = '#conditional${ctx.out.length}';
  ctx.setLocal(resultName, BuiltinValue().push(ctx).boxIfNeeded(ctx));
  final vRef = IdentifierReference(null, resultName);
  final types = <TypeRef>{?boundType};

  macroBranch(
    ctx,
    boundType == null ? null : AlwaysReturnType(boundType, false),
    condition: (ctx) {
      var c = compileExpression(e.condition, ctx);
      if (!c.type.isAssignableTo(ctx, CoreTypes.bool.ref(ctx))) {
        throw CompileError('Condition must be a boolean');
      }

      return c;
    },
    thenBranch: (ctx, rt) {
      // Box so both branches store the same representation regardless of
      // which one executes at runtime
      final v = compileExpression(
        e.thenExpression,
        ctx,
        boundType,
      ).boxIfNeeded(ctx);
      types.add(v.type);
      vRef.setValue(ctx, v);
      return StatementInfo(-1);
    },
    elseBranch: (ctx, rt) {
      final v = compileExpression(
        e.elseExpression,
        ctx,
        boundType,
      ).boxIfNeeded(ctx);
      types.add(v.type);
      vRef.setValue(ctx, v);
      return StatementInfo(-1);
    },
    source: e,
  );

  final val = vRef.getValue(ctx).updated(ctx);
  return val.copyWith(
    type: TypeRef.commonBaseType(ctx, types).copyWith(boxed: val.boxed),
  );
}
