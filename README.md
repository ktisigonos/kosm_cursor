# kosm_cursor

Cursors for kosm: a cursor theme in the kosmos' colors, or a theme installed on the system,
picked by name. GTK, Hyprland and X apps pick it by `App.themeName`; `kosm_base` passes that on.

- **Bibata** (the default, ful1e5's Material cursors, GPL-3.0, fetched as a pinned dependency):
  drawn in the theme's colors and written whole to `~/.local/share/icons/kosm_cursor`, as
  XCursor files (X apps, GTK, Qt) and as a hyprcursor theme (Hyprland, which draws its SVGs at
  any size).
- **Your own SVGs** (`.own = .{ .directory = "~/cursors" }`): the same, from your drawings,
  recolored or as drawn.
- **A system theme** (`.system = .{ .name = "Bibata-Modern-Ice" }`): used as is, nothing written.

A diff shows the theme as one line. After an apply with `size` set, `hyprctl setcursor` makes
a running Hyprland load the new cursors; a failure is a warning. Other running programs keep the old
cursors until restarted.

## Colors

Bibata draws every cursor in three stand-in colors, which become `base`, `outline` and `watch`.
Every other color (the wait and progress spinners' four segments, a few cursors' marks) follows
`rest`, a `kosm_icons.Recolor`, with the same colors and modes as the icons:

```zig
cursor.cursors.?.bibata.rest = null; // Bibata's own colors
cursor.cursors.?.bibata.rest = .{ .theme = theme, .colors = .{ .roles = &.{.accent} }, .mode = .nearest }; // one color
cursor.cursors.?.bibata.rest = .{ .theme = theme, .colors = .all, .mode = .hue }; // the palette's hues, Bibata's shading
```

## Fields

| Field | Default |
|---|---|
| `cursors` | `from`: `.bibata`; null writes nothing and picks no theme |
| `directory` | `~/.local/share/icons/kosm_cursor`; its last folder is the theme's name. Files an earlier apply wrote there and this one doesn't are left |
| `name` | the theme's `name`, or the name kosm applies the kosmos under: `Name` in index.theme |
| `sizes` | the XCursor sizes in pixels, Bibata's 16 to 96; hyprcursor draws any size |
| `size` | null: Hyprland is not told to reload; `kosm_base` sets the shared cursor size |

`Bibata`:

| Field | Default |
|---|---|
| `style` | `.modern` (rounded); `.original` is sharp |
| `hand` | `.left`; `.right` leans the other way |
| `base` | the theme's foreground: each cursor's body |
| `outline` | the theme's background, opaque |
| `watch` | the foreground: the disc behind the wait spinner |
| `rest` | `from`: each color becomes the palette hue it looks nearest; null keeps Bibata's |

`base`, `outline` and `watch` must be opaque.

`Own`: `directory` holds `<name>.svg` per cursor, or `<name>/<name>-01.svg`, `-02.svg` and on
for an animated one; `cursors` (default Bibata's names, hotspots on a 256 unit canvas, aliases
and frame counts, in `bibata_cursors`); `recolor` (null: as drawn).

`Cursor`: `name`, `x_hotspot` and `y_hotspot` in the SVG's units, `aliases` (XCursor links and
hyprcursor overrides), `frames` (1), `frame_delay` (40 ms).

## Dependencies

- `resvg` (Arch package `resvg`), a library that draws the SVGs into XCursor's pixels. A
  config holding this package does not build without it.
