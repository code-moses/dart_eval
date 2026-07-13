import 'package:analyzer/dart/ast/ast.dart';
import 'package:dart_eval/src/eval/compiler/context.dart';
import 'package:dart_eval/src/eval/compiler/expression/expression.dart';
import 'package:dart_eval/src/eval/compiler/expression/method_invocation.dart';
import 'package:dart_eval/src/eval/compiler/variable.dart';

Variable compileCascadeExpression(CascadeExpression e, CompilerContext ctx) {
  // Box the target once up front: sections dispatch methods and property
  // sets on it (which box the runtime slot in place), so compiling each
  // section against an unboxed compile-time view of the same slot would
  // drift from the runtime representation.
  final target = compileExpression(e.target, ctx).boxIfNeeded(ctx);
  for (final s in e.cascadeSections) {
    if (s is MethodInvocation) {
      compileMethodInvocation(ctx, s, cascadeTarget: target);
    } else {
      compileExpressionAndDiscardResult(s, ctx, cascadeTarget: target);
    }
  }
  return target;
}
