#!/usr/bin/env node
// Checks the Try Cuebox editor's GDScript coloring (site/gdscript.js): node site/tools/test_gdscript.mjs
// The colored copy sits under the editor's own text, so it must reproduce that text exactly.
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
await import(join(ROOT, "site", "gdscript.js"));
const { tokens, html } = globalThis.cueboxGDScript;
const problems = [];
const check = (ok, label) => { if (!ok) problems.push(label); };
const kinds = (src) => tokens(src).filter((t) => t.type !== "plain" && t.type !== "id").map((t) => `${t.type}:${t.text}`);

// 1. Lossless: the tokens put back together are the text, for the sample, edge cases and noise.
const samples = ["content.gd", "rooms/shack/geometry.gd", "rooms/shack/shack.gd", "rooms/roof/geometry.gd", "rooms/roof/roof.gd"]
  .map((p) => readFileSync(join(ROOT, "examples", "last_signal", p), "utf8"));
const edges = ['', '"', '"""', "'unclosed\nnext", '"""never\nclosed', "a\\", "#", "r\"raw \\\" end", "0x", "1.", ".5", "@", "\t\n\n", "&\"name\"", "^\"path\""];
let seed = 7;
const rand = () => (seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648;
const alphabet = ['"', "'", "#", "\\", "\n", "\t", " ", "a", "Z", "_", "0", "9", ".", "e", "x", "(", ")", ":", "@", "&", "^", "r", "f", "u", "n", "c", "<", ">"];
const noise = Array.from({ length: 2000 }, () => Array.from({ length: Math.floor(rand() * 40) }, () => alphabet[Math.floor(rand() * alphabet.length)]).join(""));
for (const src of [...samples, ...edges, ...noise]) {
  const back = tokens(src).map((t) => t.text).join("");
  if (back !== src) { problems.push(`not lossless: ${JSON.stringify(src)} -> ${JSON.stringify(back)}`); break; }
}

// 2. What each piece is called.
const expect = (src, want) => {
  const got = kinds(src);
  check(JSON.stringify(got) === JSON.stringify(want), `${JSON.stringify(src)}\n  got  ${JSON.stringify(got)}\n  want ${JSON.stringify(want)}`);
};
expect("func use_radio(who: String, item: String) -> void:", ["kw:func", "def:use_radio", "type:String", "type:String", "type:void"]);
expect('\tif flag("radio_ready"):', ["kw:if", "fn:flag", 'str:"radio_ready"']);
expect('# a "comment" with if', ['com:# a "comment" with if']);
expect('say(who, "a # not a comment") # but this is', ["fn:say", 'str:"a # not a comment"', "com:# but this is"]);
expect('"escaped \\" quote" + x', ['str:"escaped \\" quote"']);
expect('var s = """two\nlines""" + y', ["kw:var", 'str:"""two\nlines"""']);
expect("var n := 0x1F + 1.5e3 + 2 + .5 + 1_000", ["kw:var", "num:0x1F", "num:1.5e3", "num:2", "num:.5", "num:1_000"]);
expect("@export var speed: float = 1.0", ["ann:@export", "kw:var", "type:float", "num:1.0"]);
expect("return true and not false or null == self", ["kw:return", "const:true", "kw:and", "kw:not", "const:false", "kw:or", "const:null", "const:self"]);
expect('"rect":Rect2(28,75,55,36), "color":Color("e4c458")', ['str:"rect"', "type:Rect2", "num:28", "num:75", "num:55", "num:36", 'str:"color"', "type:Color", 'str:"e4c458"']);
expect("const DATA={}", ["kw:const", "const:DATA"]);
expect("x2 = item_3 + v1", []);
expect('await go("roof","stairs")', ["kw:await", "fn:go", 'str:"roof"', 'str:"stairs"']);
expect('extends "res://engine/room_script.gd"', ["kw:extends", 'str:"res://engine/room_script.gd"']);
expect("static func options() -> Dictionary:", ["kw:static", "kw:func", "def:options", "type:Dictionary"]);
expect("for i: int in range(3):", ["kw:for", "type:int", "kw:in", "fn:range", "num:3"]);
expect("&\"name\" + ^\"Path\"", ['str:&"name"', 'str:^"Path"']);

// 3. The copy is HTML, so markup in the code stays text.
const h = html('if a < b && c > "<i>":');
check(h.includes("&lt;") && h.includes("&amp;&amp;") && !h.includes("<i>"), "html escapes <, > and &: " + h);
check(html("a\n").endsWith("\n "), "a last empty line still has height in the copy");

console.log(problems.length ? "PROBLEMS:\n" + problems.join("\n") : "gdscript coloring ok");
process.exit(problems.length ? 1 : 0);
