import 'package:dart_eval/src/eval/compiler/context.dart';
import 'package:dart_eval/src/eval/compiler/offset_tracker.dart';
import 'package:dart_eval/src/eval/compiler/type.dart';
import 'package:dart_eval/src/eval/runtime/runtime.dart';

/// How a callable value must be invoked: [static] targets a known program
/// offset with a plain [Call]; [dynamic] goes through the closure convention
/// (boxed args plus runtime type lists). Derived once at [Variable]
/// construction — see the constructor doc there.
enum CallingConvention { static, dynamic }

/// Compile-time only data describing how to perform a static-dispatch function call (e.g. when the exact function
/// to be called is known at compile time)
class StaticDispatch {
  const StaticDispatch(this.offset, this.returnType);

  final DeferredOrOffset offset;
  final ReturnType returnType;
}

/// Emits a static [Call] to [offset], deferring resolution to the
/// [OffsetTracker] when the target's program offset isn't known yet.
void pushCall(CompilerContext ctx, DeferredOrOffset offset) {
  final loc = ctx.pushOp(Call.make(offset.offset ?? -1), Call.length);
  if (offset.offset == null) {
    ctx.offsetTracker.setOffset(loc, offset);
  }
}
