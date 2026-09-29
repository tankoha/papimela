# Diagrams

Japanese version: [`README_jp.md`](README_jp.md)

Class diagrams for papimela, written in Mermaid so GitHub renders them inline.

| Diagram | Subject | Design section |
|---|---|---|
| [`backend-abstraction.md`](backend-abstraction.md) | how SDL's 98-function-pointer god object was split; video and IME axes | §3.2, §3.3 |
| [`ownership-graph.md`](ownership-graph.md) | what `TPMLContext` owns, and destruction order | §2.4 |
| [`base-classes.md`](base-classes.md) | `TPMLObject` / `TPMLSystemObject` / `TPMLOwnedObject`, i.e. who may call `Free` | §4.1 |
| [`event-model.md`](event-model.md) | `TPMLEvent`, the queue, pump sources and watches | §6 |
| [`ime-model.md`](ime-model.md) | composition and clause value types | §7.3 |

## Rules

1. **English is canonical.** The Japanese version carries the `_jp` suffix and translates prose only.
2. **The Mermaid blocks are byte-identical between the two languages.** Labels are English because
   the identifiers are. `tools/check-diagrams.sh` enforces this in CI.
3. **Only implemented types are drawn.** Planned-but-unbuilt types are named in prose, never in a
   diagram. `tools/check-diagrams.sh` verifies every drawn type exists in `src/`.
4. **Generated protocol types are excluded** (45 listener classes, 80 opaque proxy types). They are
   mechanical bindings; `Twl_registry_listener` stands in for the whole set.
5. **Structure goes in the diagram; reasoning goes in the prose around it.** Prose crammed into
   Mermaid boxes makes both unreadable.
6. Stick to conservative Mermaid syntax — methods with parentheses, single-token attributes, no
   `namespace` or `direction`. There is no local Mermaid validator, so the only check is GitHub's
   renderer.

## Checking

```sh
./tools/check-diagrams.sh
```

Runs in CI on every push. It catches diagrams that fell behind the implementation; it does not
catch implementation that has no diagram, which is fine — a diagram is allowed to be a subset.
