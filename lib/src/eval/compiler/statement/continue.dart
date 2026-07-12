import 'package:analyzer/dart/ast/ast.dart';
import 'package:dart_eval/src/eval/compiler/context.dart';
import 'package:dart_eval/src/eval/compiler/errors.dart';
import 'package:dart_eval/src/eval/compiler/model/label.dart';
import 'package:dart_eval/src/eval/compiler/statement/statement.dart';
import 'package:dart_eval/src/eval/runtime/runtime.dart';

/// Compiles a `continue` statement: cleans up scopes nested inside the loop
/// body and jumps to the loop's update/condition section (resolved by
/// [macroLoop] via [CompilerContext.resolveContinueReferences]).
StatementInfo compileContinueStatement(ContinueStatement s, CompilerContext ctx) {
  if (s.label != null) {
    throw CompileError('Continue labels are not currently supported', s);
  }

  final currentState = ctx.saveState();

  final index = ctx.labels.lastIndexWhere(
    (label) => label.type == LabelType.loop,
  );
  if (index == -1) {
    throw CompileError("Cannot use 'continue' outside of a loop context", s);
  }

  // Clean up scopes of blocks nested inside the loop body, like break does,
  // but do not run the loop label's own cleanup: continue stays in the loop.
  for (var i = ctx.labels.length - 1; i > index; i--) {
    ctx.labels[i].cleanup(ctx);
  }
  final label = ctx.labels[index];
  final offset = ctx.pushOp(JumpConstant.make(-1), JumpConstant.LEN);
  (ctx.continueReferences[label] ??= {}).add(offset);
  ctx.restoreState(currentState);
  return StatementInfo(-1);
}
