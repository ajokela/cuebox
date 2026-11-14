'use strict';
// Try Cuebox. The game frame (game.html, examples/playground/host.gd) asks window.cueboxTry.files()
// for the code when it starts, and posts back what happens: {cuebox: {kind, ...}}. Edits are kept in
// this browser's localStorage and are never uploaded.
const STORE = 'cuebox-try-files-v1';
const ORDER = ['rooms/shack/shack.gd', 'rooms/shack/geometry.gd', 'rooms/roof/roof.gd', 'rooms/roof/geometry.gd', 'content.gd'];
const tabs = document.querySelector('.try-tabs');
const text = document.querySelector('#try-text');
const gutter = document.querySelector('.try-gutter');
const colored = document.querySelector('#try-hl');   // the colored copy under the editor's text
const log = document.querySelector('#try-log');
const input = document.querySelector('#try-input');
const viewport = document.querySelector('#try-viewport');
let originals = {};
let files = {};
let current = ORDER[0];
let frame = null;
let bad = {};          // file -> set of line numbers with errors in the last run
let history = [];
let back = 0;
let leaving = false;   // Esc was pressed: the next Tab leaves the editor

window.cueboxTry = { files: () => ({ ...files }) };

function saved() {
  try { return JSON.parse(localStorage.getItem(STORE) || '{}'); } catch (_) { return {}; }
}
function keep() {
  const changed = {};
  for (const path of ORDER) if (files[path] !== originals[path]) changed[path] = files[path];
  try {
    if (Object.keys(changed).length) localStorage.setItem(STORE, JSON.stringify(changed));
    else localStorage.removeItem(STORE);
  } catch (_) { /* storage full or blocked: edits last this visit */ }
}

function drawTabs() {
  tabs.replaceChildren(...ORDER.map(path => {
    const button = document.createElement('button');
    button.type = 'button';
    button.role = 'tab';
    button.textContent = path;
    button.setAttribute('aria-selected', String(path === current));
    if (files[path] !== originals[path]) button.classList.add('changed');
    if (bad[path] && bad[path].size) button.classList.add('broken');
    button.addEventListener('click', () => open(path));
    return button;
  }));
}
function drawGutter() {
  const lines = text.value.split('\n').length;
  const marks = bad[current] || new Set();
  gutter.replaceChildren(...Array.from({ length: lines }, (_, i) => {
    const row = document.createElement('div');
    row.textContent = String(i + 1);
    if (marks.has(i + 1)) row.className = 'bad';
    return row;
  }));
  gutter.scrollTop = text.scrollTop;
  colored.innerHTML = window.cueboxGDScript ? window.cueboxGDScript.html(text.value) : '';
  follow();
}
function follow() {   // the copy and the line numbers move with the editor's scroll
  gutter.scrollTop = text.scrollTop;
  colored.style.transform = `translate(${-text.scrollLeft}px, ${-text.scrollTop}px)`;
}
function open(path, line) {
  files[current] = text.value;
  current = path;
  text.value = files[path];
  drawTabs();
  drawGutter();
  if (line) {
    const rows = text.value.split('\n');
    const start = rows.slice(0, line - 1).reduce((n, row) => n + row.length + 1, 0);
    text.focus();
    text.setSelectionRange(start, start + (rows[line - 1] || '').length);
    text.scrollTop = Math.max(0, (line - 4) * parseFloat(getComputedStyle(text).lineHeight));
    drawGutter();
  }
}

function say(className, ...parts) {
  const item = document.createElement('li');
  item.className = className;
  item.append(...parts);
  log.append(item);
  while (log.children.length > 400) log.firstElementChild.remove();
  log.scrollTop = log.scrollHeight;
}
function strong(value) { const b = document.createElement('b'); b.textContent = value; return b; }

function report(r) {
  switch (r.kind) {
    case 'started': say('c-dim', `Running. Rae is in the ${r.room}.`); break;
    case 'stopped': say('c-err', 'Stopped. Fix the error above, then press Run.'); break;
    case 'line': {
      const m = /^say (\w+): ([\s\S]*)$/.exec(r.text);
      if (m) say('c-say', strong(m[1].toUpperCase() + ': '), m[2]);
      else if (r.text.startsWith('room ')) say('c-room', `→ ${r.text.slice(5)}`);
      else if (!r.text.startsWith('sfx ')) say('c-dim', r.text);
      break;
    }
    case 'flag': say('c-flag', `flag ${r.name} = ${r.value === null ? '(cleared)' : JSON.stringify(r.value)}`); break;
    case 'result': say('c-in', `> ${r.input}`); if (r.text !== '') say('c-out', r.text); break;
    case 'error': {
      if (r.input) say('c-in', `> ${r.input}`);
      if (r.file && files[r.file] !== undefined) {
        (bad[r.file] = bad[r.file] || new Set()).add(r.line);
        const at = document.createElement('button');
        at.type = 'button';
        at.textContent = r.line ? `${r.file}:${r.line}` : r.file;
        at.addEventListener('click', () => open(r.file, r.line));
        say('c-err', '✕ ', at, ` ${r.text}`);
        drawTabs();
        if (r.file === current) drawGutter();
      } else say('c-err', `✕ ${r.text}`);
      break;
    }
  }
}
window.addEventListener('message', event => {
  if (event.origin !== location.origin || !frame || event.source !== frame.contentWindow) return;
  if (event.data && typeof event.data.cuebox === 'object') report(event.data.cuebox);
});

function run() {
  files[current] = text.value;
  keep();
  bad = {};
  drawTabs();
  drawGutter();
  log.replaceChildren();
  say('c-dim', frame ? 'Starting your version…' : 'Downloading the engine, then starting your version…');
  if (!frame) {
    frame = document.createElement('iframe');
    frame.title = 'The Last Signal, running your code';
    frame.allow = 'autoplay; fullscreen';
    document.querySelector('#try-cover').remove();
    viewport.append(frame);
  }
  frame.src = 'game.html?run=' + Date.now();
  const box = viewport.getBoundingClientRect();
  if (box.top < 0 || box.bottom > innerHeight) viewport.scrollIntoView({ block: 'start', behavior: 'smooth' });   // stacked: the game is below the editor
}

function consoleLine(line) {
  if (!line.trim()) return;
  history.push(line);
  back = history.length;
  const reach = frame && frame.contentWindow && frame.contentWindow.cueboxConsole;
  if (reach) reach(line);
  else { say('c-in', `> ${line}`); say('c-err', '✕ Press Run first: the console talks to the running game.'); }
}

let saving = 0;
text.addEventListener('input', () => {
  files[current] = text.value; drawTabs(); drawGutter();
  clearTimeout(saving);
  saving = setTimeout(keep, 400);   // kept as you type: a reload loses nothing
});
text.addEventListener('scroll', follow);
text.addEventListener('keydown', event => {
  if ((event.metaKey || event.ctrlKey) && event.key === 'Enter') { event.preventDefault(); run(); return; }
  if (event.key === 'Escape') { leaving = true; return; }
  if (event.key === 'Tab' && !leaving && !event.shiftKey) {
    event.preventDefault();
    const { selectionStart: a, selectionEnd: b } = text;
    text.setRangeText('\t', a, b, 'end');
    text.dispatchEvent(new Event('input'));
  }
  leaving = false;
});
document.querySelector('#try-run').addEventListener('click', run);
document.querySelector('#try-start').addEventListener('click', run);
document.querySelector('#try-reset').addEventListener('click', () => {
  files[current] = originals[current];
  text.value = files[current];
  keep(); drawTabs(); drawGutter();
});
document.querySelector('#try-reset-all').addEventListener('click', () => {
  files = { ...originals };
  text.value = files[current];
  keep(); drawTabs(); drawGutter();
});
document.querySelector('#try-form').addEventListener('submit', event => {
  event.preventDefault();
  consoleLine(input.value);
  input.value = '';
});
input.addEventListener('keydown', event => {
  if (event.key !== 'ArrowUp' && event.key !== 'ArrowDown') return;
  event.preventDefault();
  back = Math.max(0, Math.min(history.length, back + (event.key === 'ArrowUp' ? -1 : 1)));
  input.value = history[back] || '';
});

fetch('/try/files.json').then(response => response.json()).then(data => {
  originals = data;
  const edits = saved();
  files = {};
  for (const path of ORDER) files[path] = typeof edits[path] === 'string' ? edits[path] : originals[path];
  text.value = files[current];
  drawTabs();
  drawGutter();
}).catch(() => say('c-err', '✕ The sample’s files didn’t load. Reload the page to try again.'));
