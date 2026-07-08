import 'package:analyzer/dart/ast/ast.dart';
import 'package:dart_eval/src/eval/compiler/context.dart';
import 'package:dart_eval/src/eval/compiler/expression/expression.dart';
import 'package:dart_eval/src/eval/compiler/helpers/pattern.dart';
import 'package:dart_eval/src/eval/compiler/macros/branch.dart';
import 'package:dart_eval/src/eval/compiler/statement/statement.dart';
import 'package:dart_eval/src/eval/compiler/type.dart';

StatementInfo compileIfStatement(
  IfStatement s,
  CompilerContext ctx,
  AlwaysReturnType? expectedReturnType,
) {
  final elseStatement = s.elseStatement;
  final caseClause = s.caseClause;
  return macroBranch(
    ctx,
    expectedReturnType,
    condition: (ctx) {
      if (caseClause == null) {
        return compileExpression(s.expression, ctx);
      }
      // if (value case pattern when guard): match the pattern, binding any
      // pattern variables as locals visible in the then-branch
      final value = compileExpression(s.expression, ctx).boxIfNeeded(ctx);
      return patternMatchAndBindGuarded(ctx, caseClause.guardedPattern, value);
    },
    thenBranch: (ctx, expectedReturnType) =>
        compileStatement(s.thenStatement, expectedReturnType, ctx),
    elseBranch: elseStatement == null
        ? null
        : (ctx, expectedReturnType) =>
              compileStatement(elseStatement, expectedReturnType, ctx),
    source: s,
  );
}
