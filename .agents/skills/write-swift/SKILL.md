---
name: write-swift
description: Write and review Swift value models, errors, protocols and generics, API design, performance, ARC, macros, logging, and C interop. Use for general Swift language work; use swift-concurrency for isolation and migration, and swift-testing-expert for test APIs.
---

# Write Swift

Use this skill for language modeling, protocols, API design, memory, performance, and interop. For concurrency and Swift 6 migration, load `../swift-concurrency/SKILL.md`. For test APIs, load `../swift-testing-expert/SKILL.md`; for the test-first process, load `../tdd/SKILL.md`. Read the project build settings and installed toolchain before adopting version-specific syntax.

The through-line: **Swift is a progressive-disclosure language. Start with the simplest, most static, most single-threaded thing that works, and buy dynamism - concurrency, reference semantics, existentials, unsafe pointers - only where you can point at the reason.** Every rule below is an application of that.

Model this hierarchy of defaults. Move down a level only with a reason you can state:

| Need         | Reach for               | Move down only when                                        |
| ------------ | ----------------------- | ---------------------------------------------------------- |
| Data         | `struct` / `enum`       | you need identity, sharing, or inheritance                 |
| Abstraction  | concrete type           | you have repeated code across types                        |
| Polymorphism | `some P` (generic)      | you need heterogeneous storage → `any P`                   |
| Execution    | project isolation model | consult `swift-concurrency` before changing boundaries |
| Memory       | `Array`, `String`       | profiling shows the cost → `InlineArray`, `Span`           |
| Safety       | safe API                | C interop or a measured hot path → `Unsafe*`               |

---

## 1. Model data with value types

Value types are the default in Swift, not a special case.

- **Default to `struct` and `enum`. Use `class` only for identity, shared mutable state, inheritance, or resource lifetime.** A window, a database connection, an entity stored in a rendering engine - those have identity. A `Point`, a `Drink`, a `Material` does not.
- **`let` by default; `var` only when you mutate.** This is the same discipline as `some` before `any` and value before reference: start narrow, widen with cause.
- **A struct with a mutable reference-type property is neither a value nor a reference.** Copies share the object; mutations leak across copies. Either keep the referenced type immutable, expose only computed properties that forward to it, or make it a `private` stored property behind copy-on-write.
- **Copy-on-write is how you get out-of-line storage _and_ value semantics.** Wrap a final class in a struct and check `isKnownUniquelyReferenced(&storage)` before mutating; copy first if it isn't. This is exactly how `Array`, `String`, and `Dictionary` work.
- **Enums are the tool for "a fixed set of things" and for mutually exclusive state.** Replacing a pile of optional stored properties (`isSharing`, `selectedRows`, `shareTarget`) with one `enum State` makes invalid combinations unrepresentable and makes state change atomic instead of a sequence of property writes you can forget to finish.
- **Composing values yields a value.** A struct whose stored properties are all value types has value semantics for free - which is what makes undo, diffing, and state restoration a single code path instead of one per property.

```swift
struct Material {                       // value semantics preserved
  var roughness: Double
  private var _texture: Texture         // a class

  var color: Color {
    get { _texture.color }
    set {
      if !isKnownUniquelyReferenced(&_texture) { _texture = Texture(copying: _texture) }
      _texture.color = newValue
    }
  }
}
```

**Noncopyable types** (`~Copyable`) express unique ownership: a file descriptor, a bank transfer, an open resource. Suppressing the copy turns "you must not run this twice" from an assertion into a compile error, and makes `deinit` on a struct meaningful. Mark the finishing method `consuming` so the compiler proves it's the last use. Parameter ownership becomes explicit: `borrowing` (read-only, the default), `consuming` (takes it away), `inout`/`mutating` (temporary write access).

---

## 2. Errors and optionals - make the failure paths visible

Swift error handling rests on three points: sources of error are marked so they can't surprise you; errors carry enough context to act on; and **recoverable errors are different from programmer mistakes**.

- **Recoverable → `throw`. Programmer mistake → `precondition`/`fatalError`.** A failed network call keeps the program running. An out-of-bounds index means the code is wrong and must halt before the bug becomes a security issue.
- **Enums with associated values make the best error types.** `case duplicateFriend(String)` beats `case duplicateFriend` - the context is the whole point.
- **`guard` for error conditions**, because it forces the exit path. `if let` for the ordinary unwrap.
- **Typed throws (`throws(MyError)`) are for internal functions, error-forwarding generic code, and constrained environments** where boxing `any Error` is too costly. For public API, untyped `throws` preserves your freedom to change the error type later. Note the unification: `throws` is `throws(any Error)`, and non-throwing is `throws(Never)` - which is what lets `map` abstract over both.
- **Force-unwrap only where you can state the invariant**, and prefer a failing `#require`/`precondition` with a message over a bare `!`.

---

## 3. Protocols and generics

Don't start with a class. **Don't start with a protocol either.**

The workflow: **write concrete types → notice repeated code across them → factor the shared capability into a protocol → write generic code against it.** Overloads with near-identical bodies are the signal that it's time to generalize.

- **A protocol with no per-type customization is a wasted protocol.** If every conformance would use the same default implementation, write a constrained extension on an existing protocol instead. Elaborate protocol hierarchies ("type zoology") cost compile time and binary size and buy nothing.
- **Prefer has-a to is-a.** If only some of a protocol's operations make sense for your type, don't refine it - wrap it in a generic struct and expose exactly the API you mean. (`GeometricVector<Storage: SIMD>` rather than `GeometricVector: SIMD`.)
- **A protocol requirement is a customization point** - it's dynamically dispatched, and a conforming type's implementation wins everywhere. **A method only in an extension is statically dispatched**, so a conformer's version _shadows_ rather than overrides it, and code that only knows `any P` calls the extension's. If a type should be able to customize something, make it a requirement.
- **Composition over inheritance.** Class inheritance is monolithic (one superclass), intrusive (you inherit stored properties and initializer complexity), and leaves unwritten contracts about what may be overridden and when to call super. Compose small values instead.
- **A forced downcast is a code smell** - it usually means a type relationship was lost to a class hierarchy or an existential.

### `some` vs `any`

- **Write `some P` by default. Change to `any P` when you need to store arbitrary types.** Same discipline as `let` before `var`.
- `some P` - one fixed underlying type per scope. You keep every type relationship, including associated types, and the compiler can specialize.
- `any P` - type-erased box, dynamic type varies at runtime. Needed for heterogeneous collections, for optionality of the underlying type, and to hide the abstraction entirely. You pay for it: associated-type relationships are erased to their upper bounds, and calls are opaque to the optimizer.
- **You cannot call a method that takes an associated type on an `any P`.** Erasure works in producing position (the result is erased to its upper bound) but not consuming position. The fix is to pass the existential into a function taking `some P` - the compiler unboxes it, and inside that scope the type is fixed again.
- **Constrained existentials and opaque types** - `some Collection<Element>`, `any Collection<any Animal>` - let you hide `LazyFilterSequence<[Animal]>` while still exposing the element type. Declare primary associated types on your own protocols (`protocol Container<Item>`) for the type callers actually supply, not for implementation details like `Iterator`.
- **Same-type requirements in `where` clauses** are how you pin down relationships across protocols (`where Self.CropType.FeedType == Self`). Without them, "grow then harvest" doesn't typecheck, and wrong conformances compile.

---

## 4. API design - clarity at the point of use

Clarity at the point of use is the goal that outranks every other one here.

- **No type prefixes in Swift-only APIs.** Modules disambiguate. Keep prefixes only where the API mirrors an Objective-C one. But avoid very general names from specific frameworks - they read badly out of context and force manual disambiguation.
- **Drop leading `get`** from async alternatives and from anything that returns its result directly. `persistentPosts`, not `getPersistentPosts`.
- **Access control is documentation.** `private` (file), `internal` (module, and the default), `package`, `public`. Being explicit at the boundary is what forces the sendability and API-evolution decisions above.
- **Design the model so illegal states can't be spelled.** Private setters plus a validating mutating method; enums for closed sets; a strongly typed `UUID` instead of a `String`.
- **Property wrappers** factor out an _access policy_ (`@Argument`, `@Published`, defensive copying, lazy, thread-local) so the declaration site states the policy in one word. Combine with `@dynamicMemberLookup` on a key path to project through a wrapper (that's how `$binding.title` works).
- **Result builders** for declarative DSLs. **Macros** when the boilerplate is code the compiler could have written (see Macros).

---

## 5. Performance - measure, then choose

Low-level Swift performance is dominated by four costs. Know which one you're paying.

1. **Function calls** - argument copies, static vs dynamic dispatch, call-frame allocation, and blocked optimization.
2. **Memory layout** - inline vs out-of-line storage; dynamically sized types.
3. **Allocation** - global (free), stack (cheap: one subtraction), heap (expensive: search plus locking).
4. **Copies** - retains/releases and recursive struct copies.

**But do the algorithmic work first.** Every time you write a loop, try replacing it with a call to an algorithm. The largest wins are almost never micro-optimizations:

- **Know the complexity of what you call.** `Array.remove(at:)` is O(n); calling it in a loop is O(n²). `removeAll(where:)` is O(n) total. Building a `Data` by re-slicing per byte is O(n²); `popFirst()` is O(1). Both of these were 100×+ regressions hiding behind clean-looking code.
- **Chained `map`/`flatMap`/`filter` allocate an array per stage.** Elegant ≠ fast. If a pipeline runs per-pixel or per-element in a hot loop, size the output once and write into it.
- **Then profile.** Instruments' Time Profiler and Allocations, run against a _test_ (secondary-click the test's run button → Profile) so you're measuring exactly the code you care about. `platform_memmove` dominating a flame graph means accidental copying; a million transient allocations means intermediate arrays; `swift_beginAccess` means runtime exclusivity checks; `swift_retain`/`swift_release` means reference-counting traffic.

**Concrete levers, roughly in order of what they buy:**

- **`final` on classes you don't intend to subclass** turns dynamic dispatch static and unlocks inlining. Whole-module optimization lets the compiler prove this for you in many cases - and enables generic specialization, which is where generics stop costing anything.
- **Struct storage is inline; class storage is out-of-line.** Small structs are free; a large struct with three reference-typed fields costs three retains _per copy_, versus one for a class. If you copy it a lot, use copy-on-write.
- **An `any P` existential has a 3-word inline buffer.** Values that fit live inline; larger ones get heap-allocated per copy. Same technique applies: give the large type indirect storage with copy-on-write and it fits in the buffer again.
- **Homogeneous `[MyModel]` beats `[any Model]`** - densely packed, type info passed once, specializable. `[any Model]` is the flexible-but-opaque option; take it when you need it.
- **Constraining a generic parameter to a class** (`T: AnyObject`) gives the compiler a known representation even without specialization.
- **`InlineArray<N, T>`** (Swift 6.2) for fixed-size storage: elements stored inline, size in the type via value generics, no heap allocation, no reference counting, no uniqueness or exclusivity checks. Wrong choice if it gets copied or shared.
- **`Span` / `RawSpan` / `OutputSpan`** (Swift 6.2) replace `withUnsafeBufferPointer` for direct access to contiguous storage. They're non-escapable, so the compiler ties their lifetime to the container - you get pointer performance with no lifetime bugs, and the retains/releases disappear.
- **Moving stored properties out of a nested class into the parent struct** removes runtime exclusivity checks.
- Shipped in Swift 6.3, when you've measured the need: `@inline(always)` (pair with `final` on methods) and `@specialized(where T == ...)` (SE-0460) to pre-specialize a generic for hot concrete types.
- Toolchain-dependent features to verify before use: `borrow`/`mutate` accessors instead of `get`/`set` for large stored values, `UniqueArray`/`UniqueBox`, and `Ref`/`MutableRef` to hoist a repeated lookup out of a loop.

**Async functions** keep their state on a per-task slab allocator rather than the C stack, and split into partial functions at each suspension point. The cost profile is similar to sync functions with slightly higher call overhead - which is another reason not to make something `async` that has nothing to await.

**Hops to and from the main actor cost a real context switch.** Batch: push the loop _into_ `loadArticles`/`updateUI` so they take arrays, rather than hopping twice per iteration.

---

## 6. ARC and object lifetime

- **An object's guaranteed lifetime ends at its last use, not at the closing brace.** Observed lifetimes are an emergent property of the optimizer and _will_ change. Code that depends on when a `deinit` runs is a latent bug.
- **`weak`/`unowned` are for breaking reference cycles - nothing else.** Reading a `weak` reference after the strong owner's last use may legitimately give `nil`. Optional binding there is _worse_ than force-unwrap: it turns a loud crash into a silent wrong answer.
- **Better than `weak`: don't build the cycle.** Factor the shared data into a third type both sides reference, turning the cycle into a tree.
- **Next best: redesign the API** so the object is only reachable through a strong reference. `withExtendedLifetime` works but shifts correctness onto you and spreads through a codebase - treat it as a patch, not a design.
- **Keep `deinit` side effects local.** Publishing metrics or firing a global effect from `deinit` sequences against optimizer decisions. Use `defer` at the call site instead, and leave `deinit` for verification.
- Xcode's **Optimize Object Lifetimes** build setting shortens observed lifetimes toward the guaranteed minimum, and will surface exactly these bugs.

---

## 7. Macros

Reach for a macro when you're writing code the compiler could derive - and only then.

- **Macros are type-checked before expansion.** Arguments are checked against the macro's declared signature, so misuse is a clean error at the call site, not a mess inside generated code.
- **Freestanding (`#foo`)** produce an expression or declaration. **Attached (`@Foo`)** augment a declaration in one of five roles: member, peer, accessor, member-attribute, conformance. Roles compose - `@Observable` is member + member-attribute + conformance.
- **Test macros as pure syntax-tree transforms** with `assertMacroExpansion`. It's the fastest loop, and it's how you avoid bugs in code nobody reads. Set a breakpoint in `expansion` and `po` the syntax node to learn its shape.
- **Emit real diagnostics when the macro doesn't apply.** Throw an error, or use `context.addDiagnostic` for warnings and fix-its at a specific location. Never let a macro silently generate code that won't compile.
- Expanded code is ordinary Swift: inspectable ("Expand Macro"), debuggable, steppable.

---

## 8. Logging and debugging

- **`Logger` from `os`, not `print`.** Create one per subsystem and category. Messages are stored in an optimized form and only rendered when displayed, so logging is cheap enough to leave in.
- **Non-numeric interpolations are redacted by default.** Opt in per value with `privacy: .public` only for data that is genuinely not personal. Use `.private(mask: .hash)` when you need to correlate values without exposing them.
- **Levels control persistence and cost:** `debug` (never persisted, fastest - the message construction is optimized away entirely when not streaming), `info`, `notice` (default), `error`, `fault` (most persistent, slowest). Log at `error`/`fault` for the things you'll want in a bug report.
- **Log a correlation ID** (a task or request UUID) and you can filter a whole failure's history out of a device log archive without reproducing it. `log collect --device --start ...`, then filter by subsystem in Console.
- `format:` and `align:` are free - use them so logs are readable and column-selectable.
- LLDB understands Swift tasks: it steps through `await` across threads, `swift task info` shows priority and children, and named tasks show up in both the debugger and Instruments' Swift Concurrency template.

---

## 9. Unsafe code and interop

- **"Unsafe" means the API cannot fully validate its input, so violating its preconditions is undefined behavior** - not that it crashes. Safe APIs _do_ trap deliberately; a clean fatal error is the safe outcome.
- **Prefer `Span` over `Unsafe*Pointer`.** Since Swift 6.2 there is a safe, non-escaping, equally fast way to get at contiguous storage. Reserve raw pointers for C interop.
- If you must use pointers: keep the unsafe region as small as possible, use **buffer** pointers (address + count) rather than bare pointers so bounds are tracked, never let a pointer escape the closure that vends it, and run the **Address Sanitizer**.
- Enable **strict memory safety** in security-critical modules - it forces every unsafe use to be acknowledged in source, which is what makes an audit possible. Verify availability before using per-declaration diagnostics such as `@diagnose`.
- **Interop is bidirectional and incremental.** C, Objective-C, and C++ types map into Swift directly (including C++ value semantics, containers as Swift collections, and move-only types as `~Copyable`). Swift 6.3's `@c` attribute exposes Swift functions back to C (with `@implementation` when the declaration already exists in a header). Adopt Swift one file at a time; don't rewrite.

---

## 10. Modern syntax you should be using

Agents routinely write the older, longer form of all of these.

Verify language and SDK availability for every proposed replacement against the installed toolchain and the project deployment target. Feature names and release numbers in this reference are not permission to change build settings.

| Instead of                                                            | Write                                                                                                    | Since |
| --------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------- | ----- |
| Nested ternaries; an immediately-called closure to initialize a `let` | `if`/`switch` **expressions**                                                                            | 5.9   |
| Overloads for 1, 2, 3… arguments                                      | **parameter packs** (`each T`), and `for` over a pack                                                    | 5.9   |
| `ObservableObject` + `@Published` on every property                   | **`@Observable`**                                                                                        | 5.9   |
| Polling an object for changes                                         | **`Observations { ... }`** - an `AsyncSequence` of transactional updates                                 | 6.2   |
| `NotificationCenter` with stringly-typed `userInfo`                   | concrete notification types (`MainActorMessage` / `AsyncMessage`)                                        | 6.2   |
| `Process` + pipes for scripting                                       | the **Subprocess** package (`AsyncBufferSequence.strings()` for line-by-line output; verify the available release) | 6.2+  |
| Hand-rolled string index math                                         | **Swift Regex** - literals for brevity, `RegexBuilder` for structure                                     | 5.7   |
| `[String]` of fixed size in a hot path                                | **`InlineArray<N, T>`**                                                                                  | 6.2   |
| `withUnsafeBufferPointer`                                             | **`.span`** / **`.bytes`** (`RawSpan`) / `OutputSpan`                                                    | 6.2   |
| Rebuilding a dictionary by hand to use the key                        | **`mapKeyedValues`**                                                                                     | Verify |
| `@available(iOS ..., macOS ..., tvOS ..., watchOS ..., visionOS ...)` | **`@available(anyAppleOS ...)`**                                                                         | Verify |
| `Rocket.SaturnV` when a type shadows a module                         | **module selector** `Rocket::SaturnV`                                                                    | 6.3   |
| Blanket "warnings as errors"                                          | **`@diagnose`** per declaration / warning group                                                          | Verify |
| Manually parsing binary formats with pointers                         | **Swift Binary Parsing** (`ParserSpan`, overflow-checked parsing initializers)                           | 6.2   |

Also worth knowing: **Swift Regex parsers compose with Foundation's real parsers** (`.date(...)`, `.currency(...)`) - never hand-roll date or number parsing inside a regex. Make the locale explicit rather than inheriting the system's. And use `NegativeLookahead` or `Local` (atomic groups) to stop a pattern backtracking across a whole input.

---

## Quick Reference

| Need                               | Reach for                       | Not                                       |
| ---------------------------------- | ------------------------------- | ----------------------------------------- |
| A data type                        | `struct` / `enum`               | `class` without identity or sharing       |
| Polymorphism                       | `some P`                        | `any P` unless you need storage           |
| Heterogeneous collection           | `[any P]`                       | a class hierarchy                         |
| Shared behavior, no customization  | constrained `extension`         | a new protocol                            |
| A customization point              | protocol **requirement**        | a method only in an extension             |
| Breaking a reference cycle         | restructure to a tree           | `weak` + `withExtendedLifetime`           |
| Removing matching elements         | `removeAll(where:)` - O(n)      | `remove(at:)` in a loop - O(n²)           |
| Direct access to contiguous memory | `.span`                         | `withUnsafeBufferPointer`                 |
| Fixed-size buffer in a hot path    | `InlineArray<N, T>`             | `Array`                                   |
| Diagnostics in shipping code       | `Logger` + a correlation ID     | `print`                                   |
| Deciding to optimize               | Instruments on a profiled test  | intuition                                 |

