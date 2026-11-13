# Cuebox

[Website and playable sample](https://cuebox.gd/)

A pixel-art adventure game framework for Godot. Cuebox handles characters,
walkable rooms, object interactions, inventory, dialogue, menus, audio and saves.
Games supply their own cast, rooms, puzzles and presentation through a content
provider and ordinary GDScript.

The repository opens directly into **The Last Signal**, a small two-room example:
repair a valley radio, then send a signal from the rooftop beacon.

## Try it

Use Godot **4.7.2**, the version verified for this initial release. Other versions
have not been verified.

```sh
git clone https://github.com/ajokela/cuebox.git
cd cuebox
godot --editor --path .
```

Run the project with F5 in the editor, or use `godot --path .`. Click a room object to use it. To use an inventory item,
select the item and then its target. MENU opens saves and reading preferences.

## Build your own adventure

Copy `engine/` into your Godot project, retaining the `res://engine/` path. Set
`adventure/content_provider` to a script with `static func options() -> Dictionary`.
Use `engine/bootstrap.gd` as your main scene's script, then provide your content.

Start with [the example provider](examples/last_signal/content.gd) and
[the authoring guide](docs/authoring.md). The example contains its own original
SVG assets and no required external services.

Cuebox includes:

- Multiple playable characters, independent inventories, room transitions and
  walk-box routing.
- Room and item interactions, conversations, cutscenes and optional world controllers.
- Pixel rendering, speech, paged menus, reading preferences, music and sound effects.
- Local save slots, autosave, translation hooks and configurable presentation.
- Extension interfaces for story clocks, persistent actions and specialized storage.

The current format has a 180-pixel logical height, a 152-pixel room plus 28-pixel
HUD, four-by-four actor sheets and an embedded bitmap font. Content is authored in
code. The default save store is a basic local store; specialized migrations and
platform integrations belong to the game. See the guide for the boundaries.

## Verify it

Python 3 and Godot are the only requirements:

```sh
python3 tools/check.py
```

The check imports the project, verifies engine dependency boundaries, then uses
two separate processes to play, save, cold-continue and finish the example. It
uses a fresh isolated test save directory each run. This is an automated action
check, not a blind human playtest.

## Export the example for the web

Install the export templates matching your Godot version, then:

```sh
mkdir -p build/web
godot --headless --path . --export-release Web build/web/index.html
python3 -m http.server 8766 --bind 127.0.0.1 --directory build/web
```

Open `http://127.0.0.1:8766/`. The Web preset uses a single-threaded template.

## License

Cuebox, its documentation, inline font data and example assets are available
under the [MIT License](LICENSE). See [NOTICE.md](NOTICE.md) for the separate
Godot dependency and exported-game notices.
