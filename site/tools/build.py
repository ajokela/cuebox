#!/usr/bin/env python3
"""Build only public website files and an isolated, original Cuebox sample.

Requires Python 3 and Godot 4.7.2 with its Web export templates installed.
Never exports from a host game's directory, nor uploads source/infrastructure.
"""
import gzip
import html
import json
from pathlib import Path
import shutil
import subprocess

SITE = Path(__file__).resolve().parents[1]
ROOT = SITE.parent
BUILD = ROOT / 'build' / 'website'
DIST = BUILD / 'dist'
SAMPLE = BUILD / 'sample-source'
BUILD.mkdir(parents=True, exist_ok=True)
for folder in (DIST, SAMPLE):
    if folder.exists(): shutil.rmtree(folder)
    folder.mkdir()
for filename in ('index.html', 'style.css', 'app.js', '404.html', 'robots.txt', 'sitemap.xml'):
    shutil.copy2(SITE / filename, DIST / filename)
shutil.copytree(SITE / 'assets', DIST / 'assets')
shutil.copy2(ROOT / 'examples/last_signal/rooms/roof/bg.svg', DIST / 'assets/sample-roof.svg')

# Explicit source allowlist keeps private host content and website files out.
for folder in ('engine', 'examples'):
    shutil.copytree(ROOT / folder, SAMPLE / folder, ignore=shutil.ignore_patterns('*.import', '.DS_Store'))
for filename in ('project.godot', 'export_presets.cfg', 'LICENSE', 'NOTICE.md'):
    shutil.copy2(ROOT / filename, SAMPLE / filename)

def godot(*args):
    subprocess.run(['godot', '--headless', '--path', str(SAMPLE), *args], check=True)

godot('--editor', '--import')
# Get the license texts from the installed engine, not a guessed online release.
dump = SAMPLE / 'license_dump.gd'
dump.write_text('''extends SceneTree
func _init() -> void:
    var data = {"godot": Engine.get_license_text(), "components": Engine.get_copyright_info(), "licenses": Engine.get_license_info(), "version": Engine.get_version_info()}
    var file = FileAccess.open("res://godot-notices.json", FileAccess.WRITE)
    file.store_string(JSON.stringify(data, "  "))
    file.close()
    quit()
''')
godot('--script', 'res://license_dump.gd')
notices = json.loads((SAMPLE / 'godot-notices.json').read_text())
dump.unlink()
(SAMPLE / 'godot-notices.json').unlink()
(DIST / 'play').mkdir()
godot('--export-release', 'Web', str(DIST / 'play/index.html'))

# Keep Godot in its own correctly sized viewport; never stretch its canvas.
# The home page embeds game.html directly; /play/ supplies a full-page wrapper.
play = DIST / 'play/index.html'
page = play.read_text().replace('<link rel="icon" href="data:,">', '<link rel="icon" href="/assets/icon.svg">')
(DIST / 'play/game.html').write_text(page)
play.write_text((SITE / 'play.html').read_text())

licenses = DIST / 'licenses'
licenses.mkdir()
shutil.copy2(ROOT / 'LICENSE', licenses / 'cuebox-MIT.txt')
(licenses / 'godot-MIT.txt').write_text(notices['godot'])
(licenses / 'godot-third-party.json').write_text(json.dumps(notices, indent=2))
third_party = []
for component in notices['components']:
    third_party.append(component['name'])
    for part in component['parts']:
        third_party.extend(part['copyright'])
        third_party.append('License: ' + part['license'])
        third_party.extend(part['files'])
    third_party.append('')
for name, text in notices['licenses'].items():
    third_party.extend([name, text, ''])
(licenses / 'godot-third-party.txt').write_text('\n'.join(third_party))
(licenses / 'index.html').write_text('''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Licenses &amp; local storage — Cuebox</title><link rel="icon" href="/assets/icon.svg"><link rel="stylesheet" href="/style.css"></head><body><header class="header wrap"><a class="brand" href="/">cuebox<span class="brand-dot">.</span></a><a href="/">Back to the adventure ↗</a></header><main class="wrap simple-page"><p class="eyebrow">The fine print, in readable pixels</p><h1>Made to be shared.</h1><p class="lead">Cuebox, its documentation, the website illustration and The Last Signal example are MIT licensed.</p><h2>Cuebox</h2><pre>''' + html.escape((ROOT / 'LICENSE').read_text()) + '''</pre><h2>Godot and its components</h2><p>The playable sample runs on Godot. Its engine and third-party components have their own notices, supplied here with the exported game.</p><ul><li><a href="godot-MIT.txt">Godot MIT license</a></li><li><a href="godot-third-party.txt">Bundled third-party copyright and license notices</a></li></ul><h2>Website fonts</h2><p>Space Grotesk and IBM Plex Mono are served from this site under the SIL Open Font License.</p><ul><li><a href="/assets/space-grotesk-LICENSE.txt">Space Grotesk license</a></li><li><a href="/assets/ibm-plex-mono-LICENSE.txt">IBM Plex Mono license</a></li></ul><h2>Local storage</h2><p>The sample stores progress and settings in this browser’s local storage system (IndexedDB). Clearing this site’s data removes them. There is no account or analytics script on this website. The game downloads only when you choose to play.</p><p><a href="/">← Back to Cuebox</a></p></main></body></html>''')

# Upload script serves these compressed, preserving the ordinary URL and MIME.
for ext in ('wasm', 'pck'):
    source = DIST / 'play' / f'index.{ext}'
    with gzip.GzipFile(filename='', mode='wb', fileobj=(source.with_suffix(source.suffix+'.gz')).open('wb'), mtime=0) as compressed:
        compressed.write(source.read_bytes())
print(f'Website built: {DIST}')
