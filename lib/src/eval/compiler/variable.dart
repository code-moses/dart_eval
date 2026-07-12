import 'package:analyzer/dart/ast/ast.dart';
import 'package:dart_eval/dart_eval_bridge.dart';
import 'package:dart_eval/src/eval/compiler/builtins.dart';
import 'package:dart_eval/src/eval/compiler/collection/list.dart';
import 'package:dart_eval/src/eval/compiler/context.dart';
import 'package:dart_eval/src/eval/compiler/declaration/extension.dart';
import 'package:dart_eval/src/eval/compiler/dispatch.dart';
import 'package:dart_eval/src/eval/compiler/reference.dart';
import 'package:dart_eval/src/eval/compiler/type.dart';

import 'package:dart_eval/src/eval/runtime/runtime.dart';
import 'errors.dart';
import 'offset_tracker.dart';

/// Tracks a variable on the runtime frame.
///
/// Contains methods to manipulate context frame and operators,
/// simplifying tracking variable properties in the context dictionaries
/// and generating opcodes to use this variable.
///
/// Usually instantiated with [Variable.alloc] to automate [ScopeContext] updates.
/// Expression parser in [compileExpression] returns an instance of this class.
class Variable {
  /// [boxed] states the runtime representation the caller expects this
  /// variable's slot to hold (`$Value` wrapper vs raw value). It is stamped
  /// onto [type], so `type.boxed` always reflects the caller's stated intent
  /// and cannot silently diverge from an incidentally-flagged type.
  ///
  /// [callingConvention] is derived here as the single source of truth — call
  /// sites switch on it alone rather than re-deriving it. A `Function`- or
  /// `dynamic`-typed value with no known method offset can only be invoked
  /// through [CallingConvention.dynamic]; there is nothing to statically
  /// dispatch to, so that combination is forced dynamic even if a stale
  /// convention is carried in (e.g. via [copyWith] retyping a variable).
  /// Otherwise the stated convention is respected, defaulting to static.
  Variable(
    this.scopeFrameOffset,
    TypeRef type, {
    required bool boxed,
    this.methodOffset,
    this.methodReturnType,
    this.isFinal = false,
    this.concreteTypes = const [],
    CallingConvention? callingConvention,
    this.frameRef,
  }) : type = type.boxed == boxed ? type : type.copyWith(boxed: boxed),
       callingConvention =
           ((type == TypeRef(dartCoreFile, 'Function') ||
                    type == TypeRef(dartCoreFile, 'dynamic')) &&
               methodOffset == null)
           ? CallingConvention.dynamic
           : (callingConvention ?? CallingConvention.static) /*,
        todo: assert(!type.nullable || type.boxed)*/;

  /// Allocates a variable of the given [type] on the scope frame.
  /// Automatically increases the frame offset and [ScopeContext.allocNest].
  ///
  /// [boxed] is the caller's explicit statement of the slot's runtime
  /// representation; it is stamped onto [type] (see [Variable.new]).
  factory Variable.alloc(
    ScopeContext ctx,
    TypeRef type, {
    required bool boxed,
    DeferredOrOffset? methodOffset,
    ReturnType? methodReturnType,
    bool isFinal = false,
    List<TypeRef> concreteTypes = const [],
    CallingConvention? callingConvention,
  }) {
    ctx.allocNest.last++;
    return Variable(
      ctx.scopeFrameOffset++,
      type,
      boxed: boxed,
      methodOffset: methodOffset,
      methodReturnType: methodReturnType,
      isFinal: isFinal,
      concreteTypes: concreteTypes,
      callingConvention: callingConvention,
    );
  }

  final int scopeFrameOffset;
  final TypeRef type;
  final List<TypeRef> concreteTypes;
  final DeferredOrOffset? methodOffset;
  final ReturnType? methodReturnType;
  final bool isFinal;
  final CallingConvention callingConvention;

  // If this variable is a reference to a variable in a previous stack frame,
  // this holds the reference to the list and the index of the variable in that list.
  final IndexedReference? frameRef;

  bool get boxed => type.boxed;

  String? name;
  int? frameIndex;

  /// When [CompilerContext.verifyBoxing] is on, emits a runtime assertion that
  /// this variable's slot actually holds the given [boxed] representation.
  /// A no-op for the -1 sentinel offset (unmaterialized values) and when the
  /// flag is off.
  void _assertBoxState(ScopeContext ctx, bool boxed) {
    if (ctx is! CompilerContext || !ctx.verifyBoxing || scopeFrameOffset < 0) {
      return;
    }
    // `dynamic` and `Object` are representation-polymorphic: the compiler
    // treats them as logically boxed but never materializes a box op, so a slot
    // of that static type may legitimately hold a raw value. Only concrete
    // types have a deterministic representation tied to the boxed flag, so
    // restrict verification to them (which is where box/unbox drift actually
    // causes crashes).
    if (type == CoreTypes.dynamic.ref(ctx) ||
        type == CoreTypes.object.ref(ctx)) {
      return;
    }
    ctx.pushOp(
      AssertBoxState.make(scopeFrameOffset, boxed),
      AssertBoxState.LEN,
    );
  }

  /// Boxes the variable, if it isn't yet. Does nothing with a dynamic
  /// type. Pushes a proper operator to box this value on the frame, and
  /// returns this instance with the type marked as boxed.
  Variable boxIfNeeded(ScopeContext ctx, [AstNode? source]) {
    if (boxed) {
      _assertBoxState(ctx, true);
      return this;
    }

    ctx as CompilerContext;

    if (type == CoreTypes.dynamic.ref(ctx) ||
        type == CoreTypes.object.ref(ctx)) {
      _assertBoxState(ctx, true);
      return copyWith(type: type.copyWith(boxed: true));
    }

    Variable v2 = this;

    if (type == CoreTypes.int.ref(ctx)) {
      ctx.pushOp(BoxInt.make(scopeFrameOffset), BoxInt.LEN);
    } else if (type == CoreTypes.num.ref(ctx)) {
      ctx.pushOp(BoxNum.make(scopeFrameOffset), BoxNum.LEN);
    } else if (type == CoreTypes.double.ref(ctx)) {
      ctx.pushOp(BoxDouble.make(scopeFrameOffset), BoxDouble.LEN);
    } else if (type == CoreTypes.bool.ref(ctx)) {
      ctx.pushOp(BoxBool.make(scopeFrameOffset), BoxBool.LEN);
    } else if (type == CoreTypes.list.ref(ctx)) {
      if (!type.specifiedTypeArgs[0].boxed) {
        v2 = boxListContents(ctx, this);
      }
      ctx.pushOp(BoxList.make(v2.scopeFrameOffset), BoxList.LEN);
    } else if (type == CoreTypes.map.ref(ctx)) {
      ctx.pushOp(BoxMap.make(scopeFrameOffset), BoxMap.LEN);
    } else if (type == CoreTypes.set.ref(ctx)) {
      ctx.pushOp(BoxSet.make(scopeFrameOffset), BoxSet.LEN);
    } else if (type == CoreTypes.string.ref(ctx)) {
      ctx.pushOp(BoxString.make(scopeFrameOffset), BoxString.LEN);
    } else if (type == CoreTypes.nullType.ref(ctx)) {
      ctx.pushOp(BoxNull.make(scopeFrameOffset), BoxNull.LEN);
    } else {
      throw CompileError('Cannot box $type', source);
    }

    _assertBoxState(ctx, true);
    return copyWithUpdate(ctx, type: type.copyWith(boxed: true));
  }

  /// Unboxes this variable, if it isn't yet. Unlike [boxIfNeeded],
  /// pushes the [Unbox] operator also for dynamic variables.
  ///
  /// By default updates the variable in the context locals.
  /// Set [update] to false if that's not desired.
  Variable unboxIfNeeded(ScopeContext ctx, [bool update = true]) {
    if (!boxed) {
      _assertBoxState(ctx, false);
      return this;
    }
    ctx.pushOp(Unbox.make(scopeFrameOffset), Unbox.LEN);
    _assertBoxState(ctx, false);
    if (!update) {
      return copyWith(type: type.copyWith(boxed: false));
    }
    return copyWithUpdate(ctx, type: type.copyWith(boxed: false));
  }

  /// Returns a variable with the same name from the context locals.
  /// Iterates over all frames and returns the first found one.
  /// If not found, returns this instance.
  Variable updated(ScopeContext ctx) {
    if (name == null) {
      return this;
    }
    return ctx.lookupLocal(name!) ?? this;
  }

  void pushArg(CompilerContext ctx) =>
      ctx.pushOp(PushArg.make(scopeFrameOffset), PushArg.LEN);

  /// Makes a copy of the variable with some fields updated.
  Variable copyWith({
    int? scopeFrameOffset,
    TypeRef? type,
    DeferredOrOffset? methodOffset,
    ReturnType? methodReturnType,
    bool? isFinal,
    String? name,
    int? frameIndex,
    List<TypeRef>? concreteTypes,
    IndexedReference? frameRef,
    CallingConvention? callingConvention,
  }) {
    return Variable(
        scopeFrameOffset ?? this.scopeFrameOffset,
        type ?? this.type,
        // copyWith legitimately carries box-state forward on the type itself.
        boxed: (type ?? this.type).boxed,
        methodOffset: methodOffset ?? this.methodOffset,
        isFinal: isFinal ?? this.isFinal,
        methodReturnType: methodReturnType ?? this.methodReturnType,
        concreteTypes: concreteTypes ?? this.concreteTypes,
        frameRef: frameRef ?? this.frameRef,
        callingConvention: callingConvention ?? this.callingConvention,
      )
      ..name = name ?? this.name
      ..frameIndex = frameIndex ?? this.frameIndex;
  }

  /// Makes a copy of the variable with some fields updated, and also
  /// updates the reference on the context frame.
  Variable copyWithUpdate(
    ScopeContext? ctx, {
    int? scopeFrameOffset,
    TypeRef? type,
    DeferredOrOffset? methodOffset,
    ReturnType? methodReturnType,
    String? name,
    int? frameIndex,
    List<TypeRef>? concreteTypes,
    IndexedReference? frameRef,
  }) {
    var uV = copyWith(
      scopeFrameOffset: scopeFrameOffset,
      type: type,
      methodOffset: methodOffset,
      methodReturnType: methodReturnType,
      name: name,
      frameIndex: frameIndex,
      concreteTypes: concreteTypes,
      frameRef: frameRef,
    );

    if (uV.name != null && ctx != null) {
      ctx.locals[uV.frameIndex!][uV.name!] = uV;
    }

    return uV;
  }

  void inferType(CompilerContext ctx, TypeRef type) {
    if (name != null && ctx.typeInferenceSaveStates.isNotEmpty) {
      final locals = ctx.typeInferenceSaveStates.last.locals;
      locals[frameIndex!][name!] = locals[frameIndex!][name!]!.copyWith(
        type: type,
      );
    }
  }

  Variable getProperty(CompilerContext ctx, String name, {AstNode? source}) {
    if (name == 'runtimeType') {
      if (concreteTypes.isNotEmpty) {
        final concrete = concreteTypes[0];
        ctx.pushOp(
          PushConstantType.make(concrete.toRuntimeType(ctx).type),
          PushConstantType.LEN,
        );
        return Variable.alloc(ctx, CoreTypes.type.ref(ctx), boxed: true);
      }
      ctx.pushOp(PushRuntimeType.make(scopeFrameOffset), PushRuntimeType.LEN);
      return Variable.alloc(ctx, CoreTypes.type.ref(ctx), boxed: true);
    }
    final rawFieldType = TypeRef.lookupFieldType(
      ctx,
      type,
      name,
      source: source,
    );
    if (rawFieldType == null &&
        type != CoreTypes.dynamic.ref(ctx) &&
        ctx.extensions.isNotEmpty) {
      // The property isn't declared on the receiver's type; if an extension
      // provides a getter for it, dispatch to that instead of emitting a
      // dynamic property access that would fail at runtime.
      final ext = resolveExtensionMember(ctx, type, name, 0);
      if (ext != null) {
        return invokeExtensionGetter(ctx, this, ext);
      }
    }
    final fieldType =
        rawFieldType?.resolveTypeChain(ctx) ?? CoreTypes.dynamic.ref(ctx);
    if (concreteTypes.length == 1) {
      // If the concrete type is known we can access the field directly by
      // its index
      final actualType = concreteTypes[0];
      final declaration =
          ctx.topLevelDeclarationsMap[actualType.file]?[actualType.name];
      final fieldDeclaration =
          ctx.instanceDeclarationsMap[actualType.file]?[actualType.name]?[name];
      final isBridge = declaration?.isBridge ?? true;
      if (!isBridge && fieldDeclaration != null) {
        final offset = DeferredOrOffset(
          file: actualType.file,
          className: actualType.name,
          name: name,
        );
        final op = PushObjectPropertyImpl.make(
          scopeFrameOffset,
          offset.offset ?? -1,
        );
        final loc = ctx.pushOp(op, PushObjectPropertyImpl.length);
        ctx.offsetTracker.setOffset(loc, offset);
        // Representation follows the resolved field type (resolveTypeChain
        // stamps box-state per function-boundary rules).
        return Variable.alloc(ctx, fieldType, boxed: fieldType.boxed);
      }
    }
    final op = PushObjectProperty.make(
      scopeFrameOffset,
      ctx.constantPool.addOrGet(name),
    );
    ctx.pushOp(op, PushObjectProperty.len(op));

    ctx.pushOp(PushReturnValue.make(), PushReturnValue.LEN);
    return Variable.alloc(ctx, fieldType, boxed: fieldType.boxed);
  }

  static List<Variable> boxUnboxMultiple(
    CompilerContext ctx,
    List<Variable> variables,
    bool boxed,
  ) {
    final vlist = [...variables];
    final out = <Variable>[];

    for (var i = 0; i < vlist.length; i++) {
      final v = vlist[i];
      final set = boxed ? v.boxIfNeeded(ctx) : v.unboxIfNeeded(ctx);
      out.add(set);
      for (var j = i + 1; j < vlist.length; j++) {
        final v2 = vlist[j];
        // not great for large variable lists, but since most variable lists are small...
        if (v2.scopeFrameOffset == v.scopeFrameOffset) {
          vlist[j] = set;
        }
      }
    }

    return out;
  }

  @override
  String toString() {
    final varName = name == null ? 'unnamed' : '"$name"';
    return 'Variable{$varName at L$scopeFrameOffset, $type, '
        '${methodOffset == null ? '' : 'method: $methodReturnType $methodOffset, '}'
        '${boxed ? 'boxed' : 'unboxed'}, F[$frameIndex]}';
  }
}

class InvokeResult {
  const InvokeResult(
    this.target,
    this.result,
    this.args, {
    this.namedArgs = const {},
  });

  final Variable? target;
  final Variable result;
  final List<Variable> args;
  final Map<String, Variable> namedArgs;
}

class PossiblyValuedParameter {
  PossiblyValuedParameter(this.parameter, this.V);

  FormalParameter parameter;
  Variable? V;
}
