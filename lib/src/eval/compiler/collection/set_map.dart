import 'package:analyzer/dart/ast/ast.dart';
import 'package:dart_eval/dart_eval_bridge.dart';
import 'package:dart_eval/src/eval/compiler/builtins.dart';
import 'package:dart_eval/src/eval/compiler/context.dart';
import 'package:dart_eval/src/eval/compiler/errors.dart';
import 'package:dart_eval/src/eval/compiler/expression/expression.dart';
import 'package:dart_eval/src/eval/compiler/helpers/invoke.dart';
import 'package:dart_eval/src/eval/compiler/helpers/null_check.dart';
import 'package:dart_eval/src/eval/compiler/macros/branch.dart';
import 'package:dart_eval/src/eval/compiler/macros/loop.dart';
import 'package:dart_eval/src/eval/compiler/reference.dart';
import 'package:dart_eval/src/eval/compiler/statement/statement.dart';
import 'package:dart_eval/src/eval/compiler/statement/variable_declaration.dart';
import 'package:dart_eval/src/eval/compiler/type.dart';
import 'package:dart_eval/src/eval/compiler/util.dart';
import 'package:dart_eval/src/eval/compiler/variable.dart';
import 'package:dart_eval/src/eval/runtime/runtime.dart';

const _boxSetOrMapElements = true;

Variable compileSetOrMapLiteral(SetOrMapLiteral l, CompilerContext ctx) {
  TypeRef? specifiedKeyType, specifiedValueType;
  final typeArgs = l.typeArguments;
  if (typeArgs != null) {
    specifiedKeyType = TypeRef.fromAnnotation(
      ctx,
      ctx.library,
      typeArgs.arguments[0],
    );
    if (typeArgs.arguments.length > 1) {
      specifiedValueType = TypeRef.fromAnnotation(
        ctx,
        ctx.library,
        typeArgs.arguments[1],
      );
    }
  }

  final elements = l.elements;

  // Determine whether this literal is a Set or a Map: explicit type arguments
  // win, otherwise scan the elements for an entry or expression. If only
  // spreads exist at the top level, infer from the static type of the first
  // spread's expression (compiled once here and reused when its element is
  // reached).
  bool? isMap;
  if (typeArgs != null) {
    isMap = typeArgs.arguments.length > 1;
  } else {
    isMap = _staticKindOf(elements);
  }

  final precompiledSpreads = <SpreadElement, Variable>{};
  if (isMap == null) {
    final firstSpread = elements.whereType<SpreadElement>().firstOrNull;
    if (firstSpread != null) {
      final src = compileExpression(firstSpread.expression, ctx);
      precompiledSpreads[firstSpread] = src;
      isMap = src.type
          .resolveTypeChain(ctx)
          .isAssignableTo(
            ctx,
            CoreTypes.map.ref(ctx),
            forceAllowDynamic: false,
          );
    }
  }
  // An empty untyped literal is a Map in Dart
  isMap ??= true;

  final collectionKeyType =
      (_boxSetOrMapElements
          ? specifiedKeyType?.copyWith(boxed: true)
          : specifiedKeyType) ??
      CoreTypes.dynamic.ref(ctx);

  final collectionValueType =
      (_boxSetOrMapElements
          ? specifiedValueType?.copyWith(boxed: true)
          : specifiedValueType) ??
      CoreTypes.dynamic.ref(ctx);

  final Variable collection;
  if (isMap) {
    ctx.pushOp(PushMap.make(), PushMap.LEN);
    collection = Variable.alloc(
      ctx,
      CoreTypes.map
          .ref(ctx)
          .copyWith(
            specifiedTypeArgs: [collectionKeyType, collectionValueType],
          ),
      boxed: false,
    );
  } else {
    ctx.pushOp(PushSet.make(), PushSet.LEN);
    collection = Variable.alloc(
      ctx,
      CoreTypes.set.ref(ctx).copyWith(specifiedTypeArgs: [collectionKeyType]),
      boxed: false,
    );
  }

  ctx.beginAllocScope();
  final keyResultTypes = <TypeRef>[];
  final valueResultTypes = <TypeRef>[];
  for (final e in elements) {
    // Free each element's temporaries immediately so large literals don't
    // exhaust the fixed-size runtime frame
    ctx.beginAllocScope();
    final result = compileSetOrMapElement(
      e,
      collection,
      isMap,
      ctx,
      specifiedKeyType,
      specifiedValueType,
      _boxSetOrMapElements,
      precompiledSpreads,
    );
    keyResultTypes.addAll(result.map((e) => e.first));
    valueResultTypes.addAll(result.map((e) => e.second));
    ctx.endAllocScope();
  }
  ctx.endAllocScope();

  if (specifiedValueType == null && keyResultTypes.isNotEmpty) {
    return Variable(
      collection.scopeFrameOffset,
      collection.type.copyWith(
        specifiedTypeArgs: [
          TypeRef.commonBaseType(ctx, keyResultTypes.toSet()),
          TypeRef.commonBaseType(ctx, valueResultTypes.toSet()),
        ],
      ),
      boxed: false,
    );
  }

  return collection;
}

/// Structurally determine whether the literal is a Map (true), a Set (false)
/// or unknown (null, e.g. only spreads at the top level)
bool? _staticKindOf(Iterable<CollectionElement> elements) {
  for (final e in elements) {
    final kind = _staticKindOfElement(e);
    if (kind != null) {
      return kind;
    }
  }
  return null;
}

bool? _staticKindOfElement(CollectionElement e) {
  if (e is MapLiteralEntry) {
    return true;
  } else if (e is Expression) {
    return false;
  } else if (e is IfElement) {
    final elseElement = e.elseElement;
    return _staticKindOfElement(e.thenElement) ??
        (elseElement == null ? null : _staticKindOfElement(elseElement));
  } else if (e is ForElement) {
    return _staticKindOfElement(e.body);
  }
  return null;
}

List<Pair<TypeRef, TypeRef>> compileSetOrMapElement(
  CollectionElement e,
  Variable setOrMap,
  bool isMap,
  CompilerContext ctx,
  TypeRef? specifiedKeyType,
  TypeRef? specifiedValueType,
  bool box,
  Map<SpreadElement, Variable> precompiledSpreads,
) {
  if (e is Expression) {
    if (isMap) {
      throw CompileError(
        'Cannot use an expression element in a map literal',
        e,
        ctx.library,
        ctx,
      );
    }
    var value = compileExpression(e, ctx, specifiedKeyType);

    if (specifiedKeyType != null &&
        !value.type.isAssignableTo(ctx, specifiedKeyType)) {
      throw CompileError(
        'Cannot use value of type ${value.type} in set of type <$specifiedKeyType>',
      );
    }

    if (box) {
      value = value.boxIfNeeded(ctx);
    }

    ctx.pushOp(
      SetAdd.make(setOrMap.scopeFrameOffset, value.scopeFrameOffset),
      SetAdd.LEN,
    );

    return [Pair(value.type, CoreTypes.nullType.ref(ctx))];
  } else if (e is MapLiteralEntry) {
    if (!isMap) {
      throw CompileError(
        'Cannot use a map entry in a set literal',
        e,
        ctx.library,
        ctx,
      );
    }
    var key = compileExpression(e.key, ctx, specifiedKeyType);

    if (specifiedKeyType != null &&
        !key.type.isAssignableTo(ctx, specifiedKeyType)) {
      throw CompileError(
        'Cannot use key of type ${key.type} in map of type <$specifiedKeyType, $specifiedValueType>',
      );
    }

    var value = compileExpression(e.value, ctx, specifiedValueType);

    if (specifiedValueType != null &&
        !value.type.isAssignableTo(ctx, specifiedValueType)) {
      throw CompileError(
        'Cannot use value of type ${value.type} in map of type <$specifiedKeyType, $specifiedValueType>',
      );
    }

    if (box) {
      key = key.boxIfNeeded(ctx);
      value = value.boxIfNeeded(ctx);
    }

    ctx.pushOp(
      MapSet.make(
        setOrMap.scopeFrameOffset,
        key.scopeFrameOffset,
        value.scopeFrameOffset,
      ),
      MapSet.LEN,
    );

    return [Pair(key.type, value.type)];
  } else if (e is IfElement) {
    final resultTypes = <Pair<TypeRef, TypeRef>>[];
    final elseElement = e.elseElement;
    macroBranch(
      ctx,
      null,
      condition: (ctx) => compileExpression(e.expression, ctx),
      thenBranch: (ctx, _) {
        resultTypes.addAll(
          compileSetOrMapElement(
            e.thenElement,
            setOrMap,
            isMap,
            ctx,
            specifiedKeyType,
            specifiedValueType,
            box,
            precompiledSpreads,
          ),
        );
        return StatementInfo(-1);
      },
      elseBranch: elseElement == null
          ? null
          : (ctx, _) {
              resultTypes.addAll(
                compileSetOrMapElement(
                  elseElement,
                  setOrMap,
                  isMap,
                  ctx,
                  specifiedKeyType,
                  specifiedValueType,
                  box,
                  precompiledSpreads,
                ),
              );
              return StatementInfo(-1);
            },
    );
    return resultTypes;
  } else if (e is ForElement) {
    return _compileForElement(
      e,
      setOrMap,
      isMap,
      ctx,
      specifiedKeyType,
      specifiedValueType,
      box,
      precompiledSpreads,
    );
  } else if (e is SpreadElement) {
    return _compileSpreadElement(
      e,
      setOrMap,
      isMap,
      ctx,
      box,
      precompiledSpreads,
    );
  }

  throw CompileError('Unknown set or map collection element ${e.runtimeType}');
}

List<Pair<TypeRef, TypeRef>> _compileForElement(
  ForElement e,
  Variable setOrMap,
  bool isMap,
  CompilerContext ctx,
  TypeRef? specifiedKeyType,
  TypeRef? specifiedValueType,
  bool box,
  Map<SpreadElement, Variable> precompiledSpreads,
) {
  final resultTypes = <Pair<TypeRef, TypeRef>>[];
  final parts = e.forLoopParts;

  StatementInfo compileBody(CompilerContext ctx) {
    resultTypes.addAll(
      compileSetOrMapElement(
        e.body,
        setOrMap,
        isMap,
        ctx,
        specifiedKeyType,
        specifiedValueType,
        box,
        precompiledSpreads,
      ),
    );
    return StatementInfo(-1);
  }

  if (parts is ForEachParts) {
    final iterable = compileExpression(parts.iterable, ctx).boxIfNeeded(ctx);
    final itype = iterable.type;
    if (!itype.isAssignableTo(ctx, CoreTypes.iterable.ref(ctx))) {
      throw CompileError(
        'Cannot iterate over ${iterable.type}',
        parts,
        ctx.library,
        ctx,
      );
    }

    final elementType = itype.specifiedTypeArgs.isEmpty
        ? CoreTypes.dynamic.ref(ctx)
        : itype.specifiedTypeArgs[0];

    final iterator = iterable.getProperty(ctx, 'iterator');
    late Reference loopVariable;

    macroLoop(
      ctx,
      null,
      initialization: (ctx) {
        if (parts is ForEachPartsWithDeclaration) {
          if (parts.loopVariable.type != null &&
              !elementType.isAssignableTo(
                ctx,
                TypeRef.fromAnnotation(
                  ctx,
                  ctx.library,
                  parts.loopVariable.type!,
                ),
              )) {
            throw CompileError(
              'Cannot assign $elementType to ${parts.loopVariable.type}',
              parts,
              ctx.library,
              ctx,
            );
          }
          final name = parts.loopVariable.name.lexeme;
          ctx.setLocal(
            name,
            BuiltinValue().push(ctx).copyWith(type: elementType),
          );
          loopVariable = IdentifierReference(null, name);
        } else if (parts is ForEachPartsWithIdentifier) {
          loopVariable = compileExpressionAsReference(parts.identifier, ctx);
          final type = loopVariable.resolveType(ctx);
          if (!elementType.isAssignableTo(ctx, type)) {
            throw CompileError(
              'Cannot assign $elementType to $type',
              parts,
              ctx.library,
              ctx,
            );
          }
        }
      },
      condition: (ctx) => iterator.invoke(ctx, 'moveNext', []).result,
      body: (ctx, ert) => compileBody(ctx),
      update: (ctx) =>
          loopVariable.setValue(ctx, iterator.getProperty(ctx, 'current')),
      updateBeforeBody: true,
    );
  } else if (parts is ForParts) {
    macroLoop(
      ctx,
      null,
      initialization: (ctx) {
        if (parts is ForPartsWithDeclarations) {
          compileVariableDeclarationList(parts.variables, ctx);
        } else if (parts is ForPartsWithExpression) {
          if (parts.initialization != null) {
            compileExpressionAndDiscardResult(parts.initialization!, ctx);
          }
        }
      },
      condition: parts.condition == null
          ? null
          : (ctx) => compileExpression(parts.condition!, ctx),
      body: (ctx, ert) => compileBody(ctx),
      update: (ctx) {
        for (final u in parts.updaters) {
          compileExpressionAndDiscardResult(u, ctx);
        }
      },
    );
  }

  return resultTypes;
}

List<Pair<TypeRef, TypeRef>> _compileSpreadElement(
  SpreadElement e,
  Variable setOrMap,
  bool isMap,
  CompilerContext ctx,
  bool box,
  Map<SpreadElement, Variable> precompiledSpreads,
) {
  var src =
      precompiledSpreads[e]?.updated(ctx) ??
      compileExpression(e.expression, ctx);

  final srcType = src.type.resolveTypeChain(ctx);
  TypeRef keyType, valueType;
  if (isMap) {
    if (!srcType.isAssignableTo(ctx, CoreTypes.map.ref(ctx))) {
      throw CompileError(
        'Cannot spread non-Map type ${src.type} in map literal',
        e,
        ctx.library,
        ctx,
      );
    }
    keyType = srcType.specifiedTypeArgs.length > 1
        ? srcType.specifiedTypeArgs[0]
        : CoreTypes.dynamic.ref(ctx);
    valueType = srcType.specifiedTypeArgs.length > 1
        ? srcType.specifiedTypeArgs[1]
        : CoreTypes.dynamic.ref(ctx);
  } else {
    if (!srcType.isAssignableTo(ctx, CoreTypes.iterable.ref(ctx))) {
      throw CompileError(
        'Cannot spread non-Iterable type ${src.type} in set literal',
        e,
        ctx.library,
        ctx,
      );
    }
    keyType = srcType.specifiedTypeArgs.isNotEmpty
        ? srcType.specifiedTypeArgs[0]
        : CoreTypes.dynamic.ref(ctx);
    valueType = CoreTypes.nullType.ref(ctx);
  }

  // Iterate the boxed source through the iterator protocol and add each
  // entry to the collection under construction with raw MapSet/SetAdd ops,
  // since the destination must stay unboxed in its slot (boxing a collection
  // copies it)
  void compileSpreadLoop(CompilerContext ctx, Variable boxedSrc) {
    final dynSrc = boxedSrc.copyWith(type: CoreTypes.dynamic.ref(ctx));
    final iterator = isMap
        ? dynSrc.getProperty(ctx, 'keys').getProperty(ctx, 'iterator')
        : dynSrc.getProperty(ctx, 'iterator');
    macroLoop(
      ctx,
      null,
      condition: (ctx) => iterator.invoke(ctx, 'moveNext', []).result,
      body: (ctx, _) {
        final key = iterator.getProperty(ctx, 'current').boxIfNeeded(ctx);
        if (isMap) {
          final value = dynSrc.invoke(ctx, '[]', [key]).result.boxIfNeeded(ctx);
          ctx.pushOp(
            MapSet.make(
              setOrMap.scopeFrameOffset,
              key.scopeFrameOffset,
              value.scopeFrameOffset,
            ),
            MapSet.LEN,
          );
        } else {
          ctx.pushOp(
            SetAdd.make(setOrMap.scopeFrameOffset, key.scopeFrameOffset),
            SetAdd.LEN,
          );
        }
        return StatementInfo(-1);
      },
    );
  }

  final boxedSrc = src.boxIfNeeded(ctx);
  if (e.isNullAware) {
    macroBranch(
      ctx,
      null,
      condition: (ctx) => compileNotNullCheck(ctx, boxedSrc),
      thenBranch: (ctx, rt) {
        compileSpreadLoop(ctx, boxedSrc);
        return StatementInfo(-1);
      },
      source: e,
    );
  } else {
    compileSpreadLoop(ctx, boxedSrc);
  }

  return [Pair(keyType, valueType)];
}
