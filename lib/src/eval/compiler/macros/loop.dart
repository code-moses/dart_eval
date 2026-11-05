import 'package:dart_eval/src/eval/compiler/context.dart';
import 'package:dart_eval/src/eval/compiler/macros/macro.dart';
import 'package:dart_eval/src/eval/compiler/model/label.dart';
import 'package:dart_eval/src/eval/compiler/statement/statement.dart';
import 'package:dart_eval/src/eval/compiler/type.dart';
import 'package:dart_eval/src/eval/compiler/variable.dart';
import 'package:dart_eval/src/eval/runtime/runtime.dart';

StatementInfo macroLoop(
  CompilerContext ctx,
  AlwaysReturnType? expectedReturnType, {
  required MacroStatementClosure body,
  MacroClosure? initialization,
  MacroVariableClosure? condition,
  MacroClosure? update,
  MacroClosure? after,
  bool alwaysLoopOnce = false,
  bool updateBeforeBody = false,
}) {
  ctx.beginAllocScope();

  if (initialization != null) {
    initialization(ctx);
  }

  /// Make a save-state of the box/unbox status of all locals
  final save = ctx.saveState();

  JumpIfFalse? rewriteCond;
  int? rewritePos;
  Variable? conditionResult;
  ContextSaveState? conditionSaveState;
  var loopStart = ctx.out.length;

  ctx.beginAllocScope();

  if (!alwaysLoopOnce && condition != null) {
    conditionResult = condition(ctx).unboxIfNeeded(ctx);
    conditionSaveState = ctx.saveState();
    rewriteCond = JumpIfFalse.make(conditionResult.scopeFrameOffset, -1);
    rewritePos = ctx.pushOp(rewriteCond, JumpIfFalse.LEN);
  }

  var pops = ctx.peekAllocPops();

  if (update != null && updateBeforeBody) {
    update(ctx);
  }

  final label = CompilerLabel(LabelType.loop, loopStart, (ctx) {
    ctx.endAllocScopeQuiet();

    /// Box/unbox variables that were declared outside the loop and changed in
    /// the loop body to match the save state
    ctx.resolveBranchStateDiscontinuity(save);

    if (conditionSaveState != null) {
      ctx.restoreBoxingState(conditionSaveState);
      ctx.resolveBranchStateDiscontinuity(save);
    }

    ctx.endAllocScopeQuiet();
    final result = ctx.pushOp(JumpConstant.make(-1), JumpConstant.LEN);
    return result;
  });

  ctx.labels.add(label);
  ctx.continueStates[label] = save;
  final statementResult = body(ctx, expectedReturnType);
  ctx.labels.removeLast();

  final bodyFallsThrough =
      !(statementResult.willAlwaysThrow || statementResult.willAlwaysReturn);
  final hasContinues = ctx.continueReferences[label]?.isNotEmpty ?? false;

  // Bring the fall-through path to the same boxing state that `continue`
  // statements reconcile to, as both paths meet at the continue target.
  if (bodyFallsThrough) {
    ctx.resolveBranchStateDiscontinuity(save);
  } else if (hasContinues) {
    // Only reachable through `continue`, which already reconciled to `save`.
    ctx.restoreBoxingState(save);
  }

  // `continue` jumps here: past the body, into the update (for-loops) or
  // trailing condition (do-while) before looping back around.
  ctx.resolveContinueReferences(label);

  // A body that always returns or throws still loops if it contains `continue`
  if (bodyFallsThrough || hasContinues) {
    if (update != null && !updateBeforeBody) {
      update(ctx);
    }

    /// For do-while type loops, execute the condition check after the body
    if (alwaysLoopOnce && condition != null) {
      conditionResult = condition(ctx).unboxIfNeeded(ctx);
      rewriteCond = JumpIfFalse.make(conditionResult.scopeFrameOffset, -1);
      rewritePos = ctx.pushOp(rewriteCond, JumpIfFalse.LEN);
      // On exit (condition false) the jump skips this scope's Pop below,
      // leaving the final iteration's allocations on the frame. Pop them at
      // the loop exit landing point (endAllocScope popAdjust) instead.
      pops = ctx.peekAllocPops();
    }

    ctx.endAllocScope();

    /// Box/unbox variables that were declared outside the loop and changed in
    /// the loop body to match the save state
    ctx.resolveBranchStateDiscontinuity(save);

    ctx.pushOp(JumpConstant.make(loopStart), JumpConstant.LEN);
  } else {
    // Nothing falls through to the end of the iteration scope, so it is only
    // closed at compile time. The loop can still be left through its
    // condition, whose allocations are popped at the exit landing.
    ctx.endAllocScope(popValues: false);
    if (condition == null || alwaysLoopOnce) pops = 0;
  }

  if (rewritePos != null) {
    ctx.rewriteOp(
      rewritePos,
      JumpIfFalse.make(conditionResult!.scopeFrameOffset, ctx.out.length),
      0,
    );
  }

  if (conditionSaveState != null) {
    ctx.restoreBoxingState(conditionSaveState);
    ctx.resolveBranchStateDiscontinuity(save);
  }

  if (after != null) {
    after(ctx);
  }

  ctx.endAllocScope(popAdjust: pops);
  ctx.resolveLabel(label);

  // The loop itself may run zero times or leave through its condition or a
  // `break`, so it only always returns/throws if it can never be left.
  final neverLeaves =
      !bodyFallsThrough &&
      !hasContinues &&
      (alwaysLoopOnce || condition == null) &&
      !ctx.labelReferences.containsKey(label);
  return neverLeaves
      ? statementResult
      : StatementInfo(statementResult.position);
}
