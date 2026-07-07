import 'package:analyzer/dart/ast/ast.dart';
import 'package:dart_eval/dart_eval_bridge.dart';
import 'package:dart_eval/src/eval/compiler/builtins.dart';
import 'package:dart_eval/src/eval/compiler/context.dart';
import 'package:dart_eval/src/eval/compiler/errors.dart';
import 'package:dart_eval/src/eval/compiler/expression/expression.dart';
import 'package:dart_eval/src/eval/compiler/helpers/null_check.dart';
import 'package:dart_eval/src/eval/compiler/macros/branch.dart';
import 'package:dart_eval/src/eval/compiler/macros/loop.dart';
import 'package:dart_eval/src/eval/compiler/statement/statement.dart';
import 'package:dart_eval/src/eval/compiler/type.dart';
import 'package:dart_eval/src/eval/compiler/variable.dart';
import 'package:dart_eval/src/eval/runtime/runtime.dart';

/// Compiles a spread element in a list literal.
List<TypeRef> compileSpreadElementForList(
  SpreadElement e,
  Variable list,
  CompilerContext ctx,
  bool box,
) {
  final listType = list.type.specifiedTypeArgs[0];
  final expression = e.expression;
  final isNullAware = e.isNullAware;

  // Compile the expression to get the spreaded collection
  var collection = compileExpression(expression, ctx, list.type);

  // Check if the collection is iterable
  final iterableType = CoreTypes.iterable.ref(ctx);
  if (!collection.type
      .resolveTypeChain(ctx)
      .isAssignableTo(ctx, iterableType)) {
    throw CompileError(
      'Cannot spread non-iterable type ${collection.type} in list literal',
    );
  }

  // Get the element type of the collection
  var collectionElementType = CoreTypes.dynamic.ref(ctx);
  if (collection.type.specifiedTypeArgs.isNotEmpty) {
    collectionElementType = collection.type.specifiedTypeArgs[0];
  }

  // Check if the collection elements are compatible with the list type
  if (!collectionElementType
      .resolveTypeChain(ctx)
      .isAssignableTo(ctx, listType)) {
    throw CompileError(
      'Cannot spread collection of type $collectionElementType in list of type $listType',
    );
  }

  if (isNullAware) {
    // For a null-aware spread, only append the elements if the collection
    // is non-null at runtime
    final boxedCollection = collection.boxIfNeeded(ctx);
    macroBranch(
      ctx,
      null,
      condition: (ctx) => compileNotNullCheck(ctx, boxedCollection),
      thenBranch: (ctx, rt) {
        // The spread loop ops require an unboxed collection. Unbox happens
        // in place, so this is safe to skip when the branch is not taken.
        final unboxed = boxedCollection.unboxIfNeeded(ctx, false);
        _compileSpreadLoop(ctx, unboxed, list, collectionElementType, box);
        return StatementInfo(-1);
      },
      source: e,
    );
    return [collectionElementType];
  }

  _compileSpreadLoop(
    ctx,
    collection.unboxIfNeeded(ctx),
    list,
    collectionElementType,
    box,
  );

  return [collectionElementType];
}

/// Compiles a loop that appends each element of [collection] to [list],
/// similar to boxListContents.
void _compileSpreadLoop(
  CompilerContext ctx,
  Variable collection,
  Variable list,
  TypeRef collectionElementType,
  bool box,
) {
  // Initialize loop variables
  final $i = BuiltinValue(intval: 0).push(ctx);
  final $1 = BuiltinValue(intval: 1).push(ctx);

  // Get the length of the collection
  final len = Variable.alloc(
    ctx,
    CoreTypes.int.ref(ctx).copyWith(boxed: false),
  );
  ctx.pushOp(
    PushIterableLength.make(collection.scopeFrameOffset),
    PushIterableLength.LEN,
  );

  // Loop to add each element
  macroLoop(
    ctx,
    AlwaysReturnType(CoreTypes.dynamic.ref(ctx), true),
    initialization: (ctx) {
      // We have already initialized the variables above
    },
    condition: (ctx) {
      // i < len
      final v = Variable.alloc(
        ctx,
        CoreTypes.bool.ref(ctx).copyWith(boxed: false),
      );
      ctx.pushOp(
        NumLt.make($i.scopeFrameOffset, len.scopeFrameOffset),
        NumLt.LEN,
      );
      return v;
    },
    body: (ctx, rt) {
      // Get the element at index i
      final element = Variable.alloc(ctx, collectionElementType);
      ctx.pushOp(
        IndexList.make(collection.scopeFrameOffset, $i.scopeFrameOffset),
        IndexList.LEN,
      );

      // Boxing if needed
      final elementToAdd = box ? element.boxIfNeeded(ctx) : element;

      // Add the element to the list
      ctx.pushOp(
        ListAppend.make(list.scopeFrameOffset, elementToAdd.scopeFrameOffset),
        ListAppend.LEN,
      );

      return StatementInfo(-1);
    },
    update: (ctx) {
      // i++
      final ip1 = Variable.alloc(
        ctx,
        CoreTypes.int.ref(ctx).copyWith(boxed: false),
      );
      ctx.pushOp(
        NumAdd.make($i.scopeFrameOffset, $1.scopeFrameOffset),
        NumAdd.LEN,
      );
      ctx.pushOp(
        CopyValue.make($i.scopeFrameOffset, ip1.scopeFrameOffset),
        CopyValue.LEN,
      );
    },
    after: (ctx) {
      // Nothing additional needed after the loop
    },
  );
}
