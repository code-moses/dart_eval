# HANDOFF — Refactor Task #2 (scoped): make box-state first-class in `Variable`

This document is a self-contained brief for a **fresh session** to implement
task #2 of the boxing/dispatch refactor. Read it in full before touching code.

---

## 0. Where things stand

- **Branch:** `refactor/boxing-dispatch-unification` (base your work here; do not
  branch off `master`).
- **Base commit:** `c4d0bfd add box-state verification to make box/unbox drift
  self-diagnosing`.
- Full suite is green: `dart test` → 495 passing. `dart analyze` clean.
- The overall refactor has three parts, agreed with the user:
  - **#1 — box/unbox verification.** ✅ DONE (commit `c4d0bfd`). See §2.
  - **#2 — first-class boxed-ness in `Variable` (SCOPED).** ⬅️ THIS TASK.
  - **#3 — unify static-vs-dynamic dispatch.** Not started; separate session.

Do **not** attempt #3 here. Keep this session focused on #2.

---

## 1. The one decision that defines this task

The user explicitly chose the **scoped** form of #2 over the "full divorce"
form. This is binding — do not drift back toward the full version.

- ❌ **Do NOT** remove `TypeRef.boxed` or move boxed-ness off the type into a
  standalone `Variable` field. That's a ~230-site lateral rewrite that
  relocates coupling without fixing the actual defect, and touches
  `isAssignableTo` / `copyWith` / return-boxing everywhere. Rejected.
- ✅ **DO** keep `TypeRef.boxed` as the representation source of truth, but make
  box-state an **explicit, non-defaultable decision at `Variable` construction**,
  and route every box/unbox transition through a single audited path. Goal:
  make it *impossible to silently forget or mis-state* box-state, with ~1/5 the
  churn and zero type-identity fallout.

### Why this is the right call (context for judgement during the work)
Every boxing bug this project hits is the same defect: the compile-time belief
(`type.boxed`) silently diverges from the runtime slot's real representation
(`$Value` vs raw). Three such bugs were fixed while building the recent
pattern/extension features (see §5). Relocating the flag doesn't prevent
divergence; **enforcement** does. #1 gives runtime enforcement; #2 (scoped)
gives construction-time enforcement. Together they close the loop.

---

## 2. The safety net you MUST use: `verifyBoxing` (from #1)

This is the single most important tool for doing #2 safely. It already exists.

- `Compiler.verifyBoxing` (bool, default `false`) → flows to
  `CompilerContext.verifyBoxing`.
- When on, every **concrete-typed** box/unbox transition emits an
  `AssertBoxState` op (opcode 74, bytecode version 83) that throws at runtime if
  a slot's real representation (`$Value` vs raw) disagrees with what the compiler
  believes. Implementation: `Variable._assertBoxState` in
  `lib/src/eval/compiler/variable.dart`; op in
  `lib/src/eval/runtime/ops/primitives.dart` (`class AssertBoxState`).
- `dynamic`/`Object` are representation-polymorphic and intentionally NOT
  verified (a raw value in a `dynamic` slot is legal, not drift). Keep it that way.

### Use it as your regression oracle throughout #2
The strongest validation available: temporarily flip the default to `true` and
run the whole suite.

```bash
# In lib/src/eval/compiler/compiler.dart, temporarily set: var verifyBoxing = true;
dart test            # expect: all pass. A failure = you introduced box-state drift.
# Revert the default to false before committing.
```

Baseline on `c4d0bfd`: with the flag globally on, **all 495 tests pass** (only
`dynamic`-slot cases ever tripped it, and those are correctly excluded). So any
new `AssertBoxState` failure you see during #2 is a real regression *you* caused
— fix it, don't relax the assert.

`test/box_verify_test.dart` exercises both the flag (concrete-type programs run
clean) and the op directly (proves it catches drift both directions, tolerates
null). Keep these passing.

---

## 3. The target design (recommended)

Make box-state an explicit argument at construction, keep it synced to the type,
and assert consistency in debug.

### 3a. `Variable` / `Variable.alloc`
Files: `lib/src/eval/compiler/variable.dart`.

Currently box-state is implicit: `Variable(offset, type)` and
`Variable.alloc(ctx, type)` derive `boxed` from `type.boxed` (`bool get boxed =>
type.boxed;`). A caller that passes a type whose `.boxed` is wrong gets silent
drift (this is exactly the `enum .values` list bug — alloc'd with a
`copyWith`-boxed type while the runtime value was a raw list).

**Change:** give the primary constructor and `alloc` a **required** `bool boxed`
(name it explicitly; do not default it). It must be stamped onto the type so the
type stays the source of truth:

```dart
factory Variable.alloc(ScopeContext ctx, TypeRef type, {
  required bool boxed,          // NEW: caller must state intent
  ... existing named args ...
}) {
  assert(type.boxed == boxed,   // debug: catches a type whose flag disagrees
    'Variable.alloc box-state mismatch: type says ${type.boxed}, caller says $boxed');
  ...
  return Variable(ctx.scopeFrameOffset++, type.copyWith(boxed: boxed), ...);
}
```

Decide (and document in the commit) whether `boxed` **overrides** `type.boxed`
(stamp via `copyWith`) or **must match** it (assert only). Recommendation:
**stamp** — it removes the whole class of "type's flag was stale" bugs, which is
the point. The assert then becomes a soft consistency check you can keep or drop.

There are **101 `Variable.alloc(` sites + 31 raw `Variable(` sites** in `lib/`
(counts as of `c4d0bfd`). This is the bulk of the mechanical churn. At each site
the correct `boxed:` value is almost always locally obvious (the type you're
passing already carries the intended flag; you're just making it explicit). Work
file-by-file, compile after each, and lean on `verifyBoxing` + the suite.

> Tip: consider a transitional overload/default to stage the migration (e.g.
> keep an internal unchecked constructor for `copyWith`, make the *public* alloc
> require `boxed`). Don't let `copyWith` (which legitimately carries box-state
> forward) fight the required param — `copyWith` should keep deriving from the
> resulting type, not require the arg.

### 3b. Single audited mutation path
Files: `variable.dart` (`boxIfNeeded`, `unboxIfNeeded`, `boxUnboxMultiple`).

These are already the de-facto chokepoints (137 call sites go through them) and
already call `_assertBoxState` after transitions (from #1). Confirm **every**
box/unbox transition in the codebase goes through them — grep for direct
`BoxInt.make`/`Unbox.make`/`BoxList.make` etc. emitted *outside* `variable.dart`
and route them through `boxIfNeeded`/`unboxIfNeeded` (or, if genuinely
special-cased, add an explicit `_assertBoxState` call there). Do not add new
raw box/unbox op emissions that bypass the audited path.

### 3c. Leave these ALONE
- `TypeRef.boxed`, `isAssignableTo`, `isUnboxedAcrossFunctionBoundaries`,
  `type.copyWith(boxed:)` (19 sites), the 84 `copyWith(boxed:)` calls — these
  stay. Relocating/removing them is the rejected full-divorce path.

---

## 4. Suggested step order (each step compiles + tests green before the next)

1. Add the required `boxed` param to `Variable.alloc` **with a temporary
   default** (`bool? boxed`) so the tree still compiles; stamp it when provided.
   Commit nothing yet.
2. Sweep the 101 `alloc` sites file-by-file, filling in explicit `boxed:`. After
   each file: `dart analyze` + run the nearest test file.
3. Sweep the 31 raw `Variable(` sites similarly.
4. Remove the temporary default → make `boxed` truly required. Fix stragglers.
5. Turn on `verifyBoxing` globally, `dart test`, fix any drift the asserts catch
   (these are real wins — sites where the old implicit default was wrong).
   Revert the default.
6. Full `dart test` (flag off) + `dart analyze` + `dart format`.
7. Commit as one or a few semantically-grouped commits (see §7).

---

## 5. Gotchas learned this session (will bite you again)

- **`dynamic`/`Object` are representation-polymorphic.** `boxIfNeeded` on them is
  a no-op that just flips the type flag; a slot may hold a raw value legally.
  Never assert a fixed box-state for them. (Already handled in `_assertBoxState`;
  preserve that when you touch construction.)
- **The `-1` sentinel offset.** Method tearoffs / unmaterialized values use
  `Variable(-1, ...)`. They have no real slot — `_assertBoxState` skips
  `scopeFrameOffset < 0`. Any construction-time logic must tolerate `-1`.
- **`invoke()` mutates its argument variables in place** (boxes args on the
  frame), so a `Variable` reference you hold can go stale (its `type.boxed`
  no longer matches the slot). This caused the map-pattern double-box bug. Making
  box-state explicit at construction won't fix staleness of *held* references —
  be aware when reusing a variable across an `invoke`.
- **Map `[]` on an absent key returns a raw Dart `null`, not `$null`.** Only
  `IsType` chokes on raw null; most ops tolerate it. Not a #2 concern directly,
  but explains why `dynamic` slots hold raw values.
- **Return boxing depends on `isUnboxedAcrossFunctionBoundaries`** (int, double,
  bool, list come back unboxed from a call; other types boxed). Getter/method
  call-result `Variable`s must be constructed with the matching `boxed:`. This
  bit the extension-getter work. When you make `alloc` explicit, call sites that
  build call-results must pass the correct `boxed:` derived the same way.

---

## 6. Verification checklist (definition of done)

- [ ] `Variable.alloc` and the raw `Variable(` constructor require explicit
      box-state; no implicit defaulting from an incidental `type.boxed`.
- [ ] All box/unbox transitions go through the audited `boxIfNeeded` /
      `unboxIfNeeded` path.
- [ ] `dart analyze lib/ test/` → no issues.
- [ ] `dart format` → clean.
- [ ] `dart test` (flag off) → all green (495+).
- [ ] `dart test` with `verifyBoxing` default flipped ON → all green (then
      revert the default). This is the real proof #2 tightened the invariant.
- [ ] `test/box_verify_test.dart` still passes.
- [ ] Add a short regression test if the sweep uncovers a previously-wrong
      implicit default (there may be a couple — those are the payoff).

---

## 7. Working conventions for this repo (the user cares about these)

- Split changes into **semantically correlated commits**; lowercase imperative
  subject + explanatory body. **No AI attribution / co-author footer.**
- Always add regression tests for behavior changes.
- Before committing: `dart test` (full suite) + `dart analyze` + `dart format`.
- Temp probe scripts go in the scratchpad dir; run with
  `dart --packages=.dart_tool/package_config.json <script>`.
- Update the "About this fork" section of `README.md` only if #2 changes
  user-visible behavior (it likely shouldn't — this is internal hardening — so
  a README change may not be warranted; use judgement).
- When #2 is done and committed, **delete this HANDOFF.md** as part of the final
  commit (or leave a fresh one for #3 if you're handing that off too).

---

## 8. Key files map

| File | Role in #2 |
|---|---|
| `lib/src/eval/compiler/variable.dart` | `Variable`, `alloc`, `boxIfNeeded`/`unboxIfNeeded`, `_assertBoxState`. Primary. |
| `lib/src/eval/compiler/type.dart` | `TypeRef.boxed`, `copyWith(boxed:)`, `isUnboxedAcrossFunctionBoundaries`. Leave semantics; read to understand. |
| `lib/src/eval/compiler/context.dart` | `verifyBoxing` flag lives here. |
| `lib/src/eval/compiler/compiler.dart` | `Compiler.verifyBoxing` (flip default here to validate). |
| `lib/src/eval/runtime/ops/primitives.dart` | `AssertBoxState` op (#1). |
| `test/box_verify_test.dart` | Regression oracle for the boxing invariant. |
| everything calling `Variable.alloc(` / `Variable(` | The mechanical sweep surface (~132 sites). |
