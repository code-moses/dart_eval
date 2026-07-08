import 'package:analyzer/dart/ast/ast.dart';
import 'package:dart_eval/dart_eval_bridge.dart';
import 'package:dart_eval/src/eval/compiler/builtins.dart';
import 'package:dart_eval/src/eval/compiler/context.dart';
import 'package:dart_eval/src/eval/compiler/expression/expression.dart';
import 'package:dart_eval/src/eval/compiler/helpers/invoke.dart';
import 'package:dart_eval/src/eval/compiler/helpers/pattern.dart';
import 'package:dart_eval/src/eval/compiler/macros/branch.dart';
import 'package:dart_eval/src/eval/compiler/reference.dart';
import 'package:dart_eval/src/eval/compiler/statement/statement.dart';
import 'package:dart_eval/src/eval/compiler/type.dart';
import 'package:dart_eval/src/eval/compiler/variable.dart';

/// Compile a [SwitchExpression] (e.g. `switch (x) { 1 => 'a', _ => 'b' }`) to
/// EVC bytecode. Each case is compiled as a pattern-matched branch that stores
/// its expression's result into a shared result variable, mirroring the
/// conditional expression implementation.
Variable compileSwitchExpression(
  CompilerContext ctx,
  SwitchExpression e, [
  TypeRef? boundType,
]) {
  final switchValue = compileExpression(e.expression, ctx).boxIfNeeded(ctx);

  // The name must be unique so that nested switch expressions don't shadow
  // each other's result variable. Initialize it as a *boxed* null so its
  // boxing state stays continuous across the branch merges.
  final resultName = '#switch${ctx.out.length}';
  ctx.setLocal(resultName, BuiltinValue().push(ctx).boxIfNeeded(ctx));
  final vRef = IdentifierReference(null, resultName);
  final types = <TypeRef>{?boundType};

  _compileCase(ctx, e, switchValue, vRef, types, 0, boundType);

  final val = vRef.getValue(ctx).updated(ctx);
  return val.copyWith(
    type:
        (types.isEmpty
                ? CoreTypes.dynamic.ref(ctx)
                : TypeRef.commonBaseType(ctx, types))
            .copyWith(boxed: val.boxed),
  );
}

void _compileCase(
  CompilerContext ctx,
  SwitchExpression e,
  Variable switchValue,
  IdentifierReference vRef,
  Set<TypeRef> types,
  int index,
  TypeRef? boundType,
) {
  if (index >= e.cases.length) {
    return;
  }

  final currentCase = e.cases[index];

  macroBranch(
    ctx,
    null,
    condition: (ctx) {
      final matches = patternMatchAndBind(
        ctx,
        currentCase.guardedPattern.pattern,
        switchValue,
      );
      final guard = currentCase.guardedPattern.whenClause;
      if (guard != null) {
        final guardExpr = compileExpression(guard.expression, ctx);
        return matches.invoke(ctx, '&&', [guardExpr]).result;
      }
      return matches;
    },
    thenBranch: (ctx, rt) {
      final v = compileExpression(
        currentCase.expression,
        ctx,
        boundType,
      ).boxIfNeeded(ctx);
      types.add(v.type);
      vRef.setValue(ctx, v);
      return StatementInfo(-1);
    },
    elseBranch: (ctx, rt) {
      _compileCase(ctx, e, switchValue, vRef, types, index + 1, boundType);
      return StatementInfo(-1);
    },
    source: currentCase,
  );
}
