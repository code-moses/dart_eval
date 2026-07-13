import 'package:analyzer/dart/ast/ast.dart';
import 'package:dart_eval/dart_eval_bridge.dart';
import 'package:dart_eval/src/eval/compiler/builtins.dart';
import 'package:dart_eval/src/eval/compiler/context.dart';
import 'package:dart_eval/src/eval/compiler/declaration/constructor.dart';
import 'package:dart_eval/src/eval/compiler/declaration/declaration.dart';
import 'package:dart_eval/src/eval/compiler/dispatch.dart';
import 'package:dart_eval/src/eval/compiler/errors.dart';
import 'package:dart_eval/src/eval/compiler/helpers/argument_list.dart';
import 'package:dart_eval/src/eval/compiler/helpers/invoke.dart';
import 'package:dart_eval/src/eval/compiler/reference.dart';
import 'package:dart_eval/src/eval/compiler/scope.dart';
import 'package:dart_eval/src/eval/compiler/type.dart';
import 'package:dart_eval/src/eval/compiler/variable.dart';
import 'package:dart_eval/src/eval/runtime/runtime.dart';

void compileEnumDeclaration(
  CompilerContext ctx,
  EnumDeclaration d, {
  bool statics = false,
}) {
  final type = TypeRef.lookupDeclaration(ctx, ctx.library, d);
  final $runtimeType = ctx.typeRefIndexMap[type];
  final clsName = d.namePart.toString();
  ctx.instanceDeclarationPositions[ctx.library]![clsName] = [
    {},
    {},
    {},
    $runtimeType,
  ];
  ctx.instanceGetterIndices[ctx.library]![clsName] = {};
  final constructors = <ConstructorDeclaration>[];
  final fields = <FieldDeclaration>[];
  final methods = <MethodDeclaration>[];
  for (final m in d.body.members) {
    if (m is ConstructorDeclaration) {
      constructors.add(m);
    } else if (m is FieldDeclaration) {
      if (!m.isStatic) {
        fields.add(m);
      }
    } else {
      m as MethodDeclaration;
      methods.add(m);
    }
  }
  var i = 0;
  if (constructors.isEmpty) {
    ctx.resetStack(position: 0);
    ctx.currentClass = d;
    compileDefaultConstructor(ctx, d, fields);
  }

  ctx.resetStack(position: 0);
  final pos = beginMethod(ctx, d, d.offset, '$clsName.index (get)');
  ctx.pushOp(PushObjectPropertyImpl.make(0, 0), PushObjectPropertyImpl.length);
  ctx.pushOp(Return.make(1), Return.LEN);
  ctx.instanceDeclarationPositions[ctx.library]![clsName]![0]['index'] = pos;
  i++;

  // The enum's constant name is stored at field index 1 by the generated
  // constructor; expose it through the `name` getter (EnumName.name).
  ctx.resetStack(position: 0);
  final namePos = beginMethod(ctx, d, d.offset, '$clsName.name (get)');
  ctx.pushOp(PushObjectPropertyImpl.make(0, 1), PushObjectPropertyImpl.length);
  ctx.pushOp(Return.make(1), Return.LEN);
  ctx.instanceDeclarationPositions[ctx.library]![clsName]![0]['name'] = namePos;
  i++;

  for (final m in <ClassMember>[...fields, ...methods, ...constructors]) {
    ctx.resetStack(
      position:
          m is ConstructorDeclaration || (m is MethodDeclaration && m.isStatic)
          ? 0
          : 1,
    );
    ctx.currentClass = d;
    compileDeclaration(m, ctx, parent: d, fieldIndex: i, fields: fields);
    if (m is FieldDeclaration) {
      i += m.fields.variables.length;
    }
  }

  var idx = 0;
  for (final constant in d.body.constants) {
    final cName = constant.name.lexeme;
    ctx.resetStack(position: 0);
    final pos = beginMethod(ctx, constant, constant.offset, '$cName*i');
    final cstrName = constant.arguments?.constructorSelector?.name.name ?? '';
    final method = IdentifierReference(
      null,
      d.namePart.toString(),
    ).getValue(ctx);
    final offset =
        method.methodOffset ??
        (throw CompileError(
          'Cannot instantiate enum $clsName (no valid constructor $cstrName)',
        ));

    final cstr =
        ctx.topLevelDeclarationsMap[offset.file]![offset.name ?? '$clsName.'];

    final vIndex = BuiltinValue(intval: idx).push(ctx).boxIfNeeded(ctx);
    final vName = BuiltinValue(stringval: cName).push(ctx).boxIfNeeded(ctx);

    ctx.pushOp(PushArg.make(vIndex.scopeFrameOffset), PushArg.LEN);
    ctx.pushOp(PushArg.make(vName.scopeFrameOffset), PushArg.LEN);

    final dec = cstr?.declaration;
    if (constant.arguments != null && dec != null) {
      final fpl = (dec as ConstructorDeclaration).parameters.parameters;
      compileArgumentList(
        ctx,
        constant.arguments!.argumentList,
        ctx.library,
        fpl,
        dec,
        source: constant,
      );
    }

    pushCall(ctx, offset);
    ctx.pushOp(PushReturnValue.make(), PushReturnValue.LEN);
    // The constructor returns a boxed enum instance.
    final V = Variable.alloc(ctx, type, boxed: true);
    final name = '$clsName.$cName';
    final index = ctx.topLevelGlobalIndices[ctx.library]![name]!;
    ctx.pushOp(SetGlobal.make(index, V.scopeFrameOffset), SetGlobal.LEN);
    ctx.topLevelVariableInferredTypes[ctx.library]![name] = type;
    ctx.topLevelGlobalInitializers[ctx.library]![name] = pos;
    ctx.runtimeGlobalInitializerMap[index] = pos;
    ctx.pushOp(Return.make(V.scopeFrameOffset), Return.LEN);
    idx++;
  }

  // Generate the implicit static `values` list ([const0, const1, ...]) as a
  // lazily-initialized global.
  final valuesName = '$clsName.values';
  final listType = CoreTypes.list
      .ref(ctx)
      .copyWith(specifiedTypeArgs: [type.copyWith(boxed: true)]);
  ctx.resetStack(position: 0);
  final valuesPos = beginMethod(ctx, d, d.offset, '$clsName.values*i');
  ctx.pushOp(PushList.make(), PushList.LEN);
  // PushList creates a raw list, so track it unboxed; it is boxed below.
  final listVar = Variable.alloc(ctx, listType, boxed: false);
  for (final constant in d.body.constants) {
    final cIndex =
        ctx.topLevelGlobalIndices[ctx
            .library]!['$clsName.${constant.name.lexeme}']!;
    ctx.pushOp(LoadGlobal.make(cIndex), LoadGlobal.LEN);
    ctx.pushOp(PushReturnValue.make(), PushReturnValue.LEN);
    // Enum constant globals hold boxed instances.
    final elem = Variable.alloc(ctx, type, boxed: true);
    ctx.pushOp(
      ListAppend.make(listVar.scopeFrameOffset, elem.scopeFrameOffset),
      ListAppend.LEN,
    );
  }
  // Box the list so the stored global is a $List and property/method access
  // (length, map, ...) works when the values getter is used.
  final boxedList = listVar.boxIfNeeded(ctx);
  final valuesIndex = ctx.topLevelGlobalIndices[ctx.library]![valuesName]!;
  ctx.pushOp(
    SetGlobal.make(valuesIndex, boxedList.scopeFrameOffset),
    SetGlobal.LEN,
  );
  // The stored global is a boxed $List, so register the getter's type as
  // boxed to match.
  ctx.topLevelVariableInferredTypes[ctx.library]![valuesName] = listType
      .copyWith(boxed: true);
  ctx.topLevelGlobalInitializers[ctx.library]![valuesName] = valuesPos;
  ctx.runtimeGlobalInitializerMap[valuesIndex] = valuesPos;
  ctx.pushOp(Return.make(boxedList.scopeFrameOffset), Return.LEN);

  // Generate a default toString returning "EnumName.constantName", unless the
  // enum declares its own.
  final hasUserToString = methods.any((m) => m.name.lexeme == 'toString');
  if (!hasUserToString) {
    ctx.resetStack(position: 1);
    final toStringPos = beginMethod(ctx, d, d.offset, '$clsName.toString()');
    final thisVar = Variable(0, type, boxed: true);
    final nameVal = thisVar.getProperty(ctx, 'name');
    final prefix = BuiltinValue(stringval: '$clsName.').push(ctx);
    final str = prefix.invoke(ctx, '+', [nameVal]).result;
    ctx.pushOp(Return.make(str.scopeFrameOffset), Return.LEN);
    ctx.instanceDeclarationPositions[ctx.library]![clsName]![2]['toString'] =
        toStringPos;
  }

  ctx.currentClass = null;
  ctx.resetStack();
}
