'use strict';
// A tiny website illustration, separate from the actual Cuebox sample below.
const line = document.querySelector('#scene-line');
const pocket = document.querySelector('#pocket');
let hasFuse = false;
let radioReady = false;
document.querySelectorAll('[data-object]').forEach(button => {
  button.addEventListener('click', () => {
    switch (button.dataset.object) {
      case 'drawer':
        line.textContent = hasFuse || radioReady ? '“Just dust and the promise of more dust.”' : '“A spare fuse. Almost suspiciously convenient.”';
        if (!radioReady) { hasFuse = true; pocket.textContent = '╫'; pocket.setAttribute('aria-label', 'A spare fuse'); }
        break;
      case 'radio':
        if (hasFuse) {
          radioReady = true; hasFuse = false; pocket.textContent = '·'; pocket.setAttribute('aria-label', 'Empty pocket');
          line.textContent = '“WE’RE ON THE AIR. …Does anyone know what to say?”';
        } else { line.textContent = radioReady ? '“Good evening to all three of our listeners.”' : '“No signal. That drawer looks promising.”'; }
        break;
      case 'plant': line.textContent = '“It knows something. It’s not talking.”'; break;
    }
  });
});
document.querySelector('#scene-reset').addEventListener('click', () => {
  hasFuse = false; radioReady = false; pocket.textContent = '·'; pocket.setAttribute('aria-label', 'Empty pocket');
  line.textContent = '“There’s definitely a story in here.”';
});

document.querySelector('#copy-command').addEventListener('click', async event => {
  const button = event.currentTarget;
  const commands = 'git clone https://github.com/ajokela/cuebox.git\ncd cuebox\ngodot --editor --path .';
  try {
    await navigator.clipboard.writeText(commands);
    button.textContent = 'Copied ✓';
    document.querySelector('#copy-status').textContent = 'Commands copied to your clipboard.';
    setTimeout(() => { button.textContent = 'Copy ⧉'; }, 2500);
  } catch (_) {
    document.querySelector('#copy-status').textContent = 'Copy unavailable. Select the commands and copy them manually.';
    button.textContent = 'Select text';
    const selection = window.getSelection();
    const range = document.createRange();
    range.selectNodeContents(document.querySelector('.terminal code'));
    selection.removeAllRanges(); selection.addRange(range);
  }
});

document.querySelector('#start-game').addEventListener('click', () => {
  const iframe = document.createElement('iframe');
  iframe.src = '/play/game.html';
  iframe.title = 'The Last Signal — playable Cuebox sample';
  iframe.allow = 'fullscreen; autoplay';
  iframe.setAttribute('allowfullscreen', '');
  document.querySelector('#game-cover').remove();
  document.querySelector('#game-viewport').append(iframe);
  iframe.focus();
});
