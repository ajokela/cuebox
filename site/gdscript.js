'use strict';
// GDScript coloring for the Try Cuebox editor. A colored copy of the code sits under the editor's
// transparent text, so tokens() must give back the text exactly (site/tools/test_gdscript.mjs).
(function () {
  const KEYWORDS = new Set(('if elif else for while match when break continue pass return class class_name extends is in as ' +
    'signal func static const enum var breakpoint preload await yield assert super and or not').split(' '));
  const CONSTANTS = new Set('true false null self PI TAU INF NAN'.split(' '));
  const TYPES = new Set('void bool int float'.split(' '));
  const IDENT = /[A-Za-z_][A-Za-z0-9_]*/y;
  const NUMBER = /0x[0-9A-Fa-f_]*|0b[01_]*|(?:[0-9][0-9_]*(?:\.[0-9_]*)?|\.[0-9][0-9_]*)(?:[eE][+-]?[0-9_]+)?/y;

  // [{type, text}]: kw, def (a function being defined), fn (a call), type, const, num, str, com, ann, id, plain.
  function tokens(src) {
    const out = [];
    let i = 0;
    let last = '';   // the previous word, to tell func's name
    const add = (type, end) => {
      const text = src.slice(i, end);
      const prev = out[out.length - 1];
      if (type === 'plain' && prev && prev.type === 'plain') prev.text += text;
      else out.push({ type, text });
      i = end;
    };
    while (i < src.length) {
      const c = src[i];
      if (c === '#') {
        const end = src.indexOf('\n', i);
        add('com', end < 0 ? src.length : end);
        continue;
      }
      const prefixed = (c === 'r' || c === '&' || c === '^') && (src[i + 1] === '"' || src[i + 1] === "'") && !/[A-Za-z0-9_]/.test(src[i - 1] || '');
      if (c === '"' || c === "'" || prefixed) {
        const open = prefixed ? i + 1 : i;
        const q = src[open];
        const triple = src.startsWith(q + q + q, open);
        const raw = prefixed && c === 'r';
        let e = open + (triple ? 3 : 1);
        while (e < src.length) {
          if (!raw && src[e] === '\\') { e += 2; continue; }
          if (triple ? src.startsWith(q + q + q, e) : src[e] === q) { e += triple ? 3 : 1; break; }
          if (!triple && src[e] === '\n') break;   // an unclosed string ends with its line
          e += 1;
        }
        add('str', Math.min(e, src.length));
        last = '';
        continue;
      }
      if (/[0-9]/.test(c) || (c === '.' && /[0-9]/.test(src[i + 1] || '') && !/[A-Za-z0-9_]/.test(src[i - 1] || ''))) {
        NUMBER.lastIndex = i;
        const m = NUMBER.exec(src);
        add('num', i + Math.max(1, m ? m[0].length : 1));
        last = '';
        continue;
      }
      if (c === '@' && /[A-Za-z_]/.test(src[i + 1] || '')) {
        IDENT.lastIndex = i + 1;
        add('ann', i + 1 + IDENT.exec(src)[0].length);
        continue;
      }
      if (/[A-Za-z_]/.test(c)) {
        IDENT.lastIndex = i;
        const word = IDENT.exec(src)[0];
        let next = i + word.length;
        while (src[next] === ' ' || src[next] === '\t') next += 1;
        let type = 'id';
        if (last === 'func') type = 'def';
        else if (KEYWORDS.has(word)) type = 'kw';
        else if (CONSTANTS.has(word)) type = 'const';
        else if (TYPES.has(word) || /^[A-Z][A-Za-z0-9_]*[a-z]/.test(word)) type = 'type';
        else if (/^[A-Z][A-Z0-9_]+$/.test(word)) type = 'const';
        else if (src[next] === '(') type = 'fn';
        add(type, i + word.length);
        last = word;
        continue;
      }
      if (c !== ' ' && c !== '\t' && c !== '\n') last = '';
      add('plain', i + 1);
    }
    return out;
  }

  const ESCAPE = { '&': '&amp;', '<': '&lt;', '>': '&gt;' };
  const escape = (s) => s.replace(/[&<>]/g, (ch) => ESCAPE[ch]);

  // The colored copy as HTML. A text ending in a new line gets a space after it, so the last line
  // has its height, as it does in the editor.
  function html(src) {
    const body = tokens(src).map((t) => (t.type === 'plain' || t.type === 'id' ? escape(t.text) : `<span class="t-${t.type}">${escape(t.text)}</span>`)).join('');
    return src.endsWith('\n') ? body + ' ' : body;
  }

  globalThis.cueboxGDScript = { tokens, html };
})();
