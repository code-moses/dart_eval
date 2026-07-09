import 'package:analyzer/dart/ast/ast.dart';
import 'package:dart_eval/dart_eval_bridge.dart';
import 'package:dart_eval/src/eval/compiler/context.dart';
import 'package:dart_eval/src/eval/compiler/errors.dart';
import 'package:dart_eval/src/eval/compiler/offset_tracker.dart';
import 'package:dart_eval/src/eval/compiler/expression/expression.dart';
import 'package:dart_eval/src/eval/compiler/helpers/fpl.dart';
import 'package:dart_eval/src/eval/compiler/helpers/return.dart';
import 'package:dart_eval/src/eval/compiler/scope.dart';
import 'package:dart_eval/src/eval/compiler/statement/block.dart';
import 'package:dart_eval/src/eval/compiler/statement/statement.dart';
import 'package:dart_eval/src/eval/compiler/type.dart';
import 'package:dart_eval/src/eval/compiler/util.dart';
import 'package:dart_eval/src/eval/compiler/variable.dart';
import 'package:dart_eval/src/eval/runtime/runtime.dart';

/// The mangled top-level key an extension member compiles to, e.g.
/// `StringExt.shout`, `StringExt.twice*g`, `StringExt.foo*s`.
String extensionMemberKey(String extName, MethodDeclaration m) {
  var key = '$extName.${m.name.lexeme}';
  if (m.isGetter) {
    key += '*g';
  } else if (m.isSetter) {
    key += '*s';
  }
  return key;
}

/// The resolved `on` type of [ext], cached on the record.
TypeRef extensionOnType(CompilerContext ctx, CompiledExtension ext) {
  return ext.onType ??= TypeRef.fromAnnotation(
    ctx,
    ext.library,
    ext.declaration.onClause!.extendedType,
  );
}

/// A resolved extension member reachable on a given receiver.
class ResolvedExtensionMember {
  ResolvedExtensionMember(this.extension, this.member, this.key);
  final CompiledExtension extension;
  final MethodDeclaration member;
  final String key;
}

/// Finds an extension member named [name] applicable to a receiver of
/// [receiverType]. [kind] is 2 for methods, 0 for getters, 1 for setters. When
/// several extensions apply, the one whose `on` type is the most specific
/// (nearest supertype of the receiver) wins, matching Dart's resolution.
ResolvedExtensionMember? resolveExtensionMember(
  CompilerContext ctx,
  TypeRef receiverType,
  String name,
  int kind,
) {
  ResolvedExtensionMember? best;
  TypeRef? bestOn;
  for (final ext in ctx.extensions) {
    MethodDeclaration? found;
    for (final m in ext.declaration.body.members) {
      if (m is! MethodDeclaration || m.isStatic) {
        continue;
      }
      final mKind = m.isGetter
          ? 0
          : m.isSetter
          ? 1
          : 2;
      if (mKind == kind && m.name.lexeme == name) {
        found = m;
        break;
      }
    }
    if (found == null) {
      continue;
    }
    final onType = extensionOnType(ctx, ext);
    if (!receiverType.isAssignableTo(ctx, onType, forceAllowDynamic: false)) {
      continue;
    }
    // Prefer the most specific `on` type: if the current best's `on` type is
    // assignable to this one, this one is more general, so keep the best.
    if (best != null && bestOn!.isAssignableTo(ctx, onType)) {
      continue;
    }
    best = ResolvedExtensionMember(
      ext,
      found,
      extensionMemberKey(ext.name, found),
    );
    bestOn = onType;
  }
  return best;
}

/// Dispatches a resolved extension getter [ext] on [receiver], returning its
/// value. The receiver is passed (boxed) as the getter's `#this` argument.
Variable invokeExtensionGetter(
  CompilerContext ctx,
  Variable receiver,
  ResolvedExtensionMember ext,
) {
  final r = receiver.boxIfNeeded(ctx);
  ctx.pushOp(PushArg.make(r.scopeFrameOffset), PushArg.LEN);
  final offset = DeferredOrOffset(file: ext.extension.library, name: ext.key);
  final loc = ctx.pushOp(Call.make(-1), Call.length);
  ctx.offsetTracker.setOffset(loc, offset);
  ctx.pushOp(PushReturnValue.make(), PushReturnValue.LEN);
  return Variable.alloc(ctx, extensionReturnType(ctx, ext));
}

/// The type a call to extension member [ext] evaluates to, with boxing that
/// matches how the compiled member actually returns its value (types that are
/// unboxed across function boundaries come back unboxed).
TypeRef extensionReturnType(CompilerContext ctx, ResolvedExtensionMember ext) {
  final declared = ext.member.returnType != null
      ? TypeRef.fromAnnotation(
          ctx,
          ext.extension.library,
          ext.member.returnType!,
        )
      : CoreTypes.dynamic.ref(ctx);
  return declared.copyWith(boxed: !declared.isUnboxedAcrossFunctionBoundaries);
}

/// Compiles all instance members of an extension as top-level functions whose
/// first parameter (`#this`) is the receiver of the extension's `on` type.
void compileExtensionDeclaration(CompilerContext ctx, ExtensionDeclaration d) {
  final extName = extensionName(ctx, d);
  final onType = TypeRef.fromAnnotation(
    ctx,
    ctx.library,
    d.onClause!.extendedType,
  );
  for (final m in d.body.members) {
    if (m is! MethodDeclaration || m.isStatic) {
      continue;
    }
    ctx.resetStack(position: 1);
    compileExtensionMethod(ctx, m, extName, onType);
  }
}

/// The name used to key an extension's members. Unnamed extensions get a
/// synthetic, collision-free name based on their source offset.
String extensionName(CompilerContext ctx, ExtensionDeclaration d) =>
    d.name?.lexeme ?? '#ext${d.offset}';

/// Compiles a single extension member. Mirrors [compileMethodDeclaration] but
/// binds `#this` to the receiver of the extension's `on` type and records the
/// member under a mangled top-level name, so a resolved `receiver.member` call
/// dispatches to it with the receiver passed as the first argument.
int compileExtensionMethod(
  CompilerContext ctx,
  MethodDeclaration d,
  String extName,
  TypeRef onType,
) {
  final b = d.body;
  final key = extensionMemberKey(extName, d);
  final pos = beginMethod(ctx, d, d.offset, '$extName.${d.name.lexeme}()');

  ctx.beginAllocScope(existingAllocLen: (d.parameters?.parameters.length ?? 0));
  ctx.scopeFrameOffset += d.parameters?.parameters.length ?? 0;
  // `#this` is the receiver, at slot 0. Inside the body `this` and bare member
  // access resolve against it (see reference.dart's extension-this fallback).
  ctx.setLocal('#this', Variable(0, onType.copyWith(boxed: true)));
  final savedExtensionThis = ctx.currentExtensionThis;
  ctx.currentExtensionThis = onType.copyWith(boxed: true);

  final resolvedParams = d.parameters == null
      ? <PossiblyValuedParameter>[]
      : resolveFPLDefaults(ctx, d.parameters!, true, allowUnboxed: false);

  if (b.isAsynchronous) {
    setupAsyncFunction(ctx);
  }

  var i = 1;
  for (final param in resolvedParams) {
    final p = param.parameter;
    var type = CoreTypes.dynamic.ref(ctx);
    if (p.type != null) {
      type = TypeRef.fromAnnotation(
        ctx,
        ctx.library,
        p.type!,
      ).copyWith(boxed: true);
    }
    ctx.setLocal(p.name!.lexeme, Variable(i, type));
    i++;
  }

  StatementInfo? stInfo;
  if (b is BlockFunctionBody) {
    stInfo = compileBlock(
      b.block,
      AlwaysReturnType.fromAnnotation(
        ctx,
        ctx.library,
        d.returnType,
        CoreTypes.dynamic.ref(ctx),
      ),
      ctx,
      name: '${d.name.lexeme}()',
    );
  } else if (b is ExpressionFunctionBody) {
    ctx.beginAllocScope();
    final V = compileExpression(b.expression, ctx);
    stInfo = doReturn(
      ctx,
      AlwaysReturnType.fromAnnotation(
        ctx,
        ctx.library,
        d.returnType,
        CoreTypes.dynamic.ref(ctx),
      ),
      V,
      isAsync: b.isAsynchronous,
    );
    ctx.endAllocScope();
  } else if (b is EmptyFunctionBody) {
    ctx.endAllocScope();
    ctx.currentExtensionThis = savedExtensionThis;
    return -1;
  } else {
    throw CompileError('Unknown function body type ${b.runtimeType}');
  }

  if (!(stInfo.willAlwaysReturn || stInfo.willAlwaysThrow)) {
    if (b.isAsynchronous) {
      asyncComplete(ctx, -1);
    } else {
      ctx.pushOp(Return.make(-1), Return.LEN);
    }
  }

  ctx.endAllocScope();
  ctx.currentExtensionThis = savedExtensionThis;
  ctx.topLevelDeclarationPositions[ctx.library]![key] = pos;
  return pos;
}
