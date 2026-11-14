# Authoring a Cuebox adventure

## Host contract

Set `adventure/content_provider="res://content.gd"` in `project.godot`. That
script implements `static func options() -> Dictionary`. Use
`res://engine/bootstrap.gd` as the main scene's script, or construct Screen,
Game and Menus yourself. `Game.setup(options)` merges explicit options over
the host provider. Test or developer runs should always supply an isolated
`user_root`; ordinary saves use the Godot project's own user directory.

Required data: `rooms` (IDs to folders), `crew` (character records), and
`roster` (playable IDs). The example's `examples/last_signal/content.gd` is a minimal complete
provider. `initial_crew` optionally starts a subset of the roster. A crew
record supplies a name, colour, four-by-four sprite sheet, portrait, height,
start room/position, abilities, fallback quips and poke response.
HUD portraits are 16×16 pixels and item icons 12×12 pixels. Keep the example's
nearest-neighbour and pixel-snapping project settings when using this renderer.

Room folders contain `geometry.gd` with `DATA` and `<room_id>.gd` extending
`engine/room_script.gd`. Geometry supplies a background, walk boxes, hotspots,
props and named door entries. `use_<hotspot>(who, item)` handles an interaction;
an empty item means a bare-hand action. `say`, `walk`, `go`, `pick_up`, `take`,
`has`, `flag`, `set_flag` and conversation helpers are inherited from
`script_base.gd`. Saved progress belongs in state, not script instance fields.
NPC and world scripts are optional. `game.end_game("complete")` shows the
configured ending card after the current action finishes.

Optional host configuration:

- `presentation`: `title` (array of lines), `demo_end`/`prologue_end` (two
  lines), `title_stars` (and `title_starfield: "warp"` to fly through them; Reduced
  Effects keeps them still), `website_url`/`website_label`, `privacy_url`,
  `palette` (16 colours), and `display_modes` (name, 16 colours, optional
  entitlement ID). Empty entitlement IDs are free. No external link appears
  without a supplied URL. Display modes are cosmetic and optional.
  `recovery_progress` optionally supplies the save-recovery label with a `%s`
  placeholder; the default is `PROGRESS: %s`.
- `audio_root` and `sounds`: audio directory and per-cue resource overrides.
  Empty or absent resources are silent. WAV music loops; other stream types
  retain their imported loop settings. `title_music` names a cue.
- `common_strings`: a translation table basename. Room catalogs are discovered
  by convention. `localization` supplies `languages` pairs, `debug_locales`,
  and additional `tables` records with `table` and `catalog` paths.
  `I18n.mark()` marks untranslated configuration literals for extraction;
  the menu translates them after catalogs and the player locale are selected.
- `items`, `items_script`, `npcs`, `world`, `room_scripts`: content registries.
- `interaction_policy`, `foreground`, `foreground_handlers`, `entry_flow`,
  `story_clock`, `reference`, `completion`, `save_store`, `save_validator`,
  `crew_dialogue`: optional script adapters. Their interfaces are called from
  the engine runtime; start with the example, then implement the interfaces you
  need. `foreground_handlers` is an ordered list of action IDs with
  `requires_handler`; these IDs are supplied by the host.
- `telemetry` and `telemetry_enabled`: an explicit host-owned service, disabled
  by default. No collector or analytics provider is part of the engine package.

The basic store supports three slots, autosave and settings using temporary-file
replacement. The checkpoint codec accepts host-chosen namespaces containing
lowercase letters, digits, underscores and hyphens (1–64 characters), and still
rejects a different expected namespace. Specialized storage, migration rules and
platform packaging are host responsibilities.
No native save extension is bundled with Cuebox.

## Current limits

The runtime is a pixel-art adventure framework for code-authored games. It retains
its 180-pixel logical height, 152-pixel room/28-pixel HUD,
4×4 character sprite layout, bitmap font, movement style, and one active game
per process (translation registration is shared). Those are documented format
constraints, not promises of arbitrary presentation support. Arbitrary fonts,
resolutions, sprite rigs and a portable production-grade native save plugin
are separate work. Puzzle analysis, art generators, translation extraction and
platform-specific release tools are outside this runtime. Cuebox and its sample assets use the MIT
license in the repository root.
