import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:dart_eval/dart_eval_bridge.dart';
import 'package:dart_eval/src/eval/compiler/builtins.dart';
import 'package:dart_eval/src/eval/compiler/context.dart';
import 'package:dart_eval/src/eval/compiler/expression/expression.dart';
import 'package:dart_eval/src/eval/compiler/helpers/equality.dart';
import 'package:dart_eval/src/eval/compiler/macros/branch.dart';
import 'package:dart_eval/src/eval/compiler/statement/statement.dart';
import 'package:dart_eval/src/eval/compiler/type.dart';
import 'package:dart_eval/src/eval/compiler/variable.dart';
import 'package:dart_eval/src/eval/runtime/runtime.dart';

// Dart's null-shorting: in `a?.b().c()`, a null `a` makes the whole chain
// null, so `.c()` never runs on null. Each `?.`/`?[` link only guards itself;
// a plain link further out in the same chain is guarded here instead: the
// receiver of the first unguarded null-aware link is evaluated once, and the
// whole chain runs only when it is non-null, with that link compiled as a
// plain access on the evaluated receiver.

/// The next element in to the left of [e] in a selector chain, or null where
/// the chain starts (a cascade target or a parenthesized expression ends it).
Expression? chainReceiver(Expression e) => switch (e) {
  MethodInvocation(:final target) when !e.isCascaded => target,
  PropertyAccess() when !e.isCascaded => e.target,
  IndexExpression() when !e.isCascaded => e.target,
  _ => null,
};

/// Whether [e] is a `?.` or `?[` link that still has to test its receiver.
bool isUnguardedNullAware(CompilerContext ctx, Expression e) {
  final nullAware = switch (e) {
    MethodInvocation() => e.operator?.type == TokenType.QUESTION_PERIOD,
    PropertyAccess() => e.operator.type == TokenType.QUESTION_PERIOD,
    IndexExpression() => e.isNullAware,
    _ => false,
  };
  return nullAware && !ctx.nullShortedLinks.contains(e);
}

/// The leftmost unguarded null-aware link in the receivers of [e], if [e]
/// itself is a plain link that would otherwise run on its null result.
Expression? nullShortingLink(CompilerContext ctx, Expression e) {
  if (chainReceiver(e) == null || isUnguardedNullAware(ctx, e)) return null;
  Expression? found;
  for (var link = chainReceiver(e); link != null; link = chainReceiver(link)) {
    if (isUnguardedNullAware(ctx, link)) found = link;
  }
  return found;
}

/// Compiles the chain ending in [e] so that it is null when the receiver of
/// [link] is null.
Variable compileNullShorted(
  CompilerContext ctx,
  Expression e,
  Expression link,
  TypeRef? bound,
) {
  final receiverNode = chainReceiver(link)!;
  final receiver = compileExpression(receiverNode, ctx).boxIfNeeded(ctx);

  var out = BuiltinValue().push(ctx).boxIfNeeded(ctx);
  if (receiver.concreteTypes.length == 1 &&
      receiver.concreteTypes[0] == CoreTypes.nullType.ref(ctx)) {
    return out;
  }

  macroBranch(
    ctx,
    null,
    condition: (ctx) => checkNotEqual(ctx, receiver, out),
    thenBranch: (ctx, rt) {
      ctx.nullShortedLinks.add(link);
      ctx.nullShortedReceivers[receiverNode] = receiver;
      try {
        final V = compileExpression(e, ctx, bound).boxIfNeeded(ctx);
        out = out.copyWith(
          type: V.type.copyWith(nullable: true),
          concreteTypes: [],
        );
        ctx.pushOp(
          CopyValue.make(out.scopeFrameOffset, V.scopeFrameOffset),
          CopyValue.LEN,
        );
      } finally {
        ctx.nullShortedLinks.remove(link);
        ctx.nullShortedReceivers.remove(receiverNode);
      }
      return StatementInfo(-1);
    },
    source: e,
  );
  return out;
}
