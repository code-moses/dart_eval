# HANDOFF — Refactor Task #3: unify static-vs-dynamic dispatch

Brief for a fresh session. Tasks #1 and #2 of the boxing/dispatch refactor are
**done**; this documents where things stand and what #3 is about. Task #3 was
agreed with the user only at the one-line level ("unify static-vs-dynamic
dispatch") — **start by proposing a concrete scope and getting it confirmed**
before writing code.

## Where things stand

- **Branch:** `refactor/boxing-dispatch-unification`.
- **#1 — box/unbox verification.** ✅ commit `c4d0bfd`. `Compiler.verifyBoxing`
  (default false) emits `AssertBoxState` ops at every concrete-typed box/unbox
  transition; a slot whose representation disagrees with the compiler's belief
  throws at that op. `dynamic`/`Object` are representation-polymorphic and
  intentionally not verified.
- **#2 — explicit box-state at `Variable` construction.** ✅ commit `b107d67`.
  `Variable` / `Variable.alloc` take a **required** `boxed:` argument, stamped
  onto the type via `copyWith`, so `type.boxed` always reflects stated intent.
  `Variable.copyWith` derives box-state from the resulting type. `TypeRef.boxed`
  remains the representation source of truth (the "full divorce" — moving
  boxed-ness off the type — was explicitly rejected by the user; don't revisit).

## Validation harness (use it)

- Full suite: `dart test` → 496 passing (495 + one regression test added in #2).
- The strongest oracle: flip `var verifyBoxing = false;` to `true` in
  `lib/src/eval/compiler/compiler.dart` (line ~94), run `dart test`, expect all
  green, then revert. Baseline after #2: green with the flag on.
- `test/box_verify_test.dart` exercises the flag end-to-end and the
  `AssertBoxState` op directly.

## #3 raw material (pointers, not a design)

- `CallingConvention` (static/dynamic) lives on `Variable`
  (`lib/src/eval/compiler/variable.dart`); chosen in the constructor default and
  at construction sites.
- Static dispatch: `Call` op + `DeferredOrOffset` (see
  `helpers/invoke.dart` `_invokeAsFunction`, `reference.dart`
  `getStaticDispatch` / `_declarationToStaticDispatch`).
- Dynamic dispatch: `InvokeDynamic` (by method name via constant pool) and
  `invokeClosure` (`helpers/closure.dart`) with its RTTI arg-type lists.
- Known asymmetries: closures always box args (`allowUnboxed: false`) while
  static calls follow `isUnboxedAcrossFunctionBoundaries`; tearoffs
  (`helpers/tearoff.dart`) generate shim functions to bridge conventions;
  `method_invocation.dart` picks conventions in several places.

## Working conventions (the user cares)

- Semantically correlated commits; lowercase imperative subject + body; **no AI
  attribution/co-author footer**.
- Regression tests for behavior changes. Before committing: `dart test`,
  `dart analyze`, `dart format`.
- Temp probes in the scratchpad dir, run with
  `dart --packages=.dart_tool/package_config.json <script>`.
- Delete/replace this HANDOFF.md when #3 lands.
