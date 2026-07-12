import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:dart_eval/src/eval/compiler/builtins.dart';
import 'package:dart_eval/src/eval/compiler/context.dart';
import 'package:dart_eval/src/eval/compiler/expression/expression.dart';
import 'package:dart_eval/src/eval/compiler/helpers/invoke.dart';
import 'package:dart_eval/src/eval/compiler/macros/branch.dart';
import 'package:dart_eval/src/eval/compiler/statement/statement.dart';
import 'package:dart_eval/src/eval/compiler/variable.dart';

Variable compileAssignmentExpression(
  AssignmentExpression e,
  CompilerContext ctx,
) {
  final L = compileExpressionAsReference(e.leftHandSide, ctx);

  if (e.operator.type == TokenType.EQ) {
    final R = compileExpression(
      e.rightHandSide,
      ctx,
      L.resolveType(ctx, forSet: true),
    );
    final set = R.type != L.resolveType(ctx, forSet: true)
        ? R.boxIfNeeded(ctx)
        : R;
    return L.setValue(ctx, set);
  } else if (e.operator.type.binaryOperatorOfCompoundAssignment ==
      TokenType.QUESTION_QUESTION) {
    macroBranch(
      ctx,
      null,
      condition: (ctx) {
        return L.getValue(ctx).invoke(ctx, '==', [
          BuiltinValue().push(ctx),
        ]).result;
      },
      thenBranch: (ctx, rt) {
        // The right-hand side of ??= must only be evaluated (including its
        // side effects) when the target is actually null, so compile it
        // inside the branch.
        final R = compileExpression(
          e.rightHandSide,
          ctx,
          L.resolveType(ctx, forSet: true),
        );
        L.setValue(ctx, R.boxIfNeeded(ctx));
        return StatementInfo(-1);
      },
    );
    // The value of `a ??= b` is a's final value: b if a was null, otherwise
    // the preexisting value. A result captured inside the branch would hold
    // garbage whenever the branch is skipped, so re-read the target instead.
    return L.getValue(ctx);
  } else {
    final method = e.operator.type.binaryOperatorOfCompoundAssignment!.lexeme;
    final R = compileExpression(
      e.rightHandSide,
      ctx,
      L.resolveType(ctx, forSet: true),
    );
    final V = L.getValue(ctx);
    final res = V.invoke(ctx, method, [R]).result;
    final set = res.type != L.resolveType(ctx, forSet: true)
        ? res.boxIfNeeded(ctx)
        : res;
    return L.setValue(ctx, set);
  }
}
