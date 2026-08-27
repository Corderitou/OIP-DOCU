# Explanation: Why Custom Scene Format

Why OIP uses `.oip_scene.json` instead of Godot's native `.tscn` format.

## The Problem

Godot's `.tscn` format is optimized for the editor, not for simulation data. It includes editor-specific metadata, resource UIDs, and engine-version-specific syntax that create several problems for OIP:

1. **Version coupling**: `.tscn` format changes between Godot versions. A scene saved in Godot 4.5 may not parse cleanly in 4.7. OIP targets long-lived simulation projects that need to survive engine upgrades.

2. **Noise in diffs**: `.tscn` files contain auto-generated IDs, resource paths, and editor state that produce large, meaningless diffs in version control. A single moved node can show hundreds of changed lines.

3. **No programmatic generation**: Creating `.tscn` files from external tools requires understanding Godot's internal resource serialization format, which is undocumented and version-dependent.

4. **No clean property isolation**: `.tscn` mixes node hierarchy, resource definitions, and property values in a single format. Extracting "what properties does this node have" requires parsing the entire file.

## The Approach

OIP uses a custom JSON format that separates concerns:

```
.oip_scene.json
├── version (format versioning)
├── metadata (name, description, timestamps)
└── nodes[] (hierarchical, one entry per part)
    ├── type (maps to SceneRegistry)
    ├── name (user-visible, auto-generated)
    ├── transform (origin + basis matrix)
    ├── properties (only exported values)
    └── children[] (recursive)
```

The `SceneRegistry` maps type names to `.tscn` resource paths. On load, the registry looks up the type, instantiates the Godot scene, and applies the saved properties. This means:

- The JSON file only stores **what changed** from defaults
- The `.tscn` files store **how things look** (meshes, materials, collision shapes)
- External tools only need to understand JSON, not Godot internals

## Trade-offs

### What we gain

| Benefit | Impact |
|---|---|
| Clean version control diffs | Only meaningful property changes show in `git diff` |
| Cross-version stability | JSON schema is stable across Godot upgrades |
| External tool support | Any language can read/write scenes |
| Property isolation | Easy to query "what speed did this conveyor have?" |
| Minimal file size | Only stores non-default values |

### What we give up

| Cost | Mitigation |
|---|---|
| No Godot editor open/load | OIP has its own editor (runtime_editor.gd) *(DEPRECATED — the runtime editor and its `.oip_scene.json` format are no longer maintained)* |
| Manual property serialization | `SceneManager._serialize_node()` handles this automatically |
| No resource embedding | Resources (meshes, materials) stay in `.tscn` files |
| Custom format learning curve | Documented in [Scene File Format](reference-scene-format.md) |

### Why not both?

OIP could support both formats, but the dual-format maintenance cost (keeping two serializers in sync, testing both paths) outweighs the benefit. The custom format is the primary format; `.tscn` files are only used as resource containers for the part library.

## Serialization Details

The serialization in `scene_manager.gd` works by:

1. **Discovery**: `get_property_list()` returns all script-exported properties with their types.
2. **Filtering**: Non-serializable types (Object, RID) and internal properties are excluded.
3. **Conversion**: Godot types are converted to JSON-compatible primitives (Vector3 → float[3], Color → float[4], etc.).
4. **Special cases**: `Building` node has custom serialization for its width/length/height sections. `FlowDirectionArrow` children are skipped.

Deserialization reverses the process: the type string looks up the `.tscn` path, instantiates it, and applies properties via `node.set()`.

## Performance

JSON parsing is fast for OIP's typical scene sizes (10-100 nodes). The format is not optimized for streaming or real-time synchronization — that would require a binary format like MessagePack. For the current use case (save/load/layout), JSON's readability and tool support outweigh the parsing overhead.

## See also

- [Scene File Format](reference-scene-format.md) — Complete schema reference
- [Architecture Overview](explanation-architecture.md) — Where scene management fits
- [Runtime Editor Architecture](RUNTIME_EDITOR.md) — SceneManager implementation details *(DEPRECATED)*
