import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:dart_eval/dart_eval_bridge.dart';
import 'package:dart_eval/src/eval/compiler/builtins.dart';
import 'package:dart_eval/src/eval/compiler/helpers/equality.dart';
import 'package:dart_eval/src/eval/compiler/macros/branch.dart';
import 'package:dart_eval/src/eval/compiler/reference.dart';
import 'package:dart_eval/src/eval/compiler/context.dart';
import 'package:dart_eval/src/eval/compiler/expression/expression.dart';
import 'package:dart_eval/src/eval/compiler/statement/statement.dart';
import 'package:dart_eval/src/eval/compiler/variable.dart';
import 'package:dart_eval/src/eval/compiler/type.dart';

import 'package:dart_eval/src/eval/runtime/runtime.dart';

Variable compilePropertyAccess(
  PropertyAccess pa,
  CompilerContext ctx, {
  Variable? cascadeTarget,
}) {
  final L = cascadeTarget ?? compileExpression(pa.realTarget, ctx);

  if (pa.operator.type == TokenType.QUESTION_PERIOD) {
    var out = BuiltinValue().push(ctx).boxIfNeeded(ctx);
    if (L.concreteTypes.length == 1 &&
        L.concreteTypes[0] == CoreTypes.nullType.ref(ctx)) {
      return out;
    }
    // Box the target so a runtime null is represented as $null for the null
    // check, and so the property access works on the boxed value.
    final boxedL = L.boxIfNeeded(ctx);
    macroBranch(
      ctx,
      null,
      condition: (ctx) {
        return checkNotEqual(ctx, boxedL, out);
      },
      thenBranch: (ctx, rt) {
        final V = boxedL
            .getProperty(ctx, pa.propertyName.name)
            .boxIfNeeded(ctx);
        // Clear the null concreteTypes inherited from the null initializer,
        // or chained null-aware operators would short-circuit unconditionally
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
      source: pa,
    );
    return out;
  }

  return L.getProperty(ctx, pa.propertyName.name);
}

Reference compilePropertyAccessAsReference(
  PropertyAccess pa,
  CompilerContext ctx, {
  Variable? cascadeTarget,
}) {
  final L = cascadeTarget ?? compileExpression(pa.realTarget, ctx);
  return IdentifierReference(L, pa.propertyName.name);
}
