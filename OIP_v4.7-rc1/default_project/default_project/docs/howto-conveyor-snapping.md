# How to Use Conveyor Snapping

> [!WARNING]
> **DEPRECATED.** Conveyor snapping (Ctrl+Shift+C) is a feature of the deprecated
> **runtime editor** (code in `deprecated/runtime/`), which is no longer the
> active component and is not maintained. This guide is kept for historical
> reference only.

Align and connect conveyors end-to-end or side-to-side with the built-in snapping system.

## Prerequisites

- Two or more conveyors placed in the scene (belt, roller, curved, or spur variants)

## Steps

### 1. Select conveyors

1. Select the **target conveyor** (the one others will snap to) — click it last so it's the "active" selection.
2. Shift+click additional conveyors to add them to the selection.

### 2. Trigger the snap

Press `Ctrl+Shift+C`. The selected conveyors snap to align with the active conveyor.

### 3. What snapping does

The snapping system handles these connection types:

| Connection | Result |
|---|---|
| Straight-to-straight | Ends align, same Z position |
| Straight-to-curved | Tangent alignment at the curve entrance |
| Straight-to-spur | Side-by-side alignment |
| Curved-to-curved | Radius alignment |
| Diverter connection | Arm aligns with conveyor edge |
| Chain transfer | Chains align across conveyors |
| Blade stop | Stop aligns with conveyor width |

### 4. Side guard openings

When conveyors connect at a T-junction, the snapping system automatically:

- Trims the frame rails at the junction
- Creates side guard openings so products can transfer between conveyors
- Adjusts guard anchoring flags to track future resize operations

### 5. Undo snapping

`Ctrl+Z` reverts the snap operation. The undo system captures frame rail state and guard positions.

## Tips

- **Select order matters**: The last-selected (active) conveyor is the snap target.
- **Curved conveyors**: Snapping handles the tangent angle automatically.
- **Multiple connections**: Select 3+ conveyors and snap them all at once.
- **Spur conveyors**: The system detects `angle_downstream`/`angle_upstream` on spur types.

## See also

- [Parts Catalog](reference-parts-catalog.md) — Conveyor variants and properties
- [Keyboard Shortcuts](reference-shortcuts.md) — All editor shortcuts
