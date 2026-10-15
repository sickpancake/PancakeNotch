/* The working notch on the home page: a pretend, silent player and an example Shelf.
   The one at the top is written into the page; the live pieces further down get copies of it
   (live.js) and steer them through `element.notch`. Like the app, a copy does nothing while nobody
   is looking: the sound bars and the 1-second progress tick run only while it's visible, and a
   song's end is a single timer, not a loop. */
(() => {
  'use strict';

  const hero = document.querySelector('[data-demo]');
  if (!hero) return;

  // A clean copy of the notch, taken before anything changes it, for the live pieces.
  const blueprint = hero.querySelector('.stage').cloneNode(true);

  const SONGS = [
    { title: 'Pancake Sunrise', artist: 'The Flipsides', album: 'Breakfast Club', duration: 192 },
    { title: 'Golden Edges', artist: 'Maple & Co.', album: 'Stack', duration: 168 },
    { title: 'Night Owl', artist: 'Syrup Static', album: 'After Hours', duration: 220 },
  ];
  const EXAMPLES = [
    { kind: 'file', name: 'Report.pdf', meta: 'PDF document · 84 KB', thumb: 'pdf' },
    { kind: 'file', name: 'Holiday.jpg', meta: 'JPEG image · 11 KB', thumb: 'photo' },
    { kind: 'text', text: 'Pick up the cake at 5' },
    { kind: 'link', url: 'https://github.com' },
  ];
  const VIEWS = ['menu', 'np', 'shelf'];
  const CAPACITY = 20;
  const NEARLY_FULL = 15; // the Shelf's count shows beside the notch from here (the app's rule)
  const touchOnly = matchMedia('(hover: none)');
  let made = 0;

  /* ---------- Small helpers shared by every copy ---------- */

  const now = () => performance.now();
  const time = (seconds) => {
    const whole = Math.max(0, Math.floor(seconds));
    return `${Math.floor(whole / 60)}:${String(whole % 60).padStart(2, '0')}`;
  };
  const el = (tag, className, text) => {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined) node.textContent = text;
    return node;
  };
  const icon = (name) => {
    const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    svg.setAttribute('class', 'icon');
    svg.setAttribute('aria-hidden', 'true');
    const use = document.createElementNS('http://www.w3.org/2000/svg', 'use');
    use.setAttribute('href', `#i-${name}`);
    svg.append(use);
    return svg;
  };
  const host = (url) => {
    try { return new URL(url).host || url; } catch { return url; }
  };
  const nameOf = (item) => (item.kind === 'file' ? item.name : item.kind === 'link' ? host(item.url) : item.text.split('\n')[0]);
  const kindOf = (item) => ({ file: 'File', text: 'Text', link: 'Link' })[item.kind];
  const size = (bytes) => {
    if (bytes < 1000) return `${bytes} bytes`;
    if (bytes < 1e6) return `${Math.round(bytes / 1000)} KB`;
    return `${(bytes / 1e6).toFixed(1)} MB`;
  };

  /* A thumbnail: drawn pictures for the examples, a page or picture icon for anything dropped. */
  function thumb(item) {
    if (item.kind === 'text') {
      const note = el('span', 'thumb-note', item.text.slice(0, 60));
      note.append(icon('text'));
      return note;
    }
    if (item.kind === 'link') {
      const link = el('span', 'thumb-link');
      link.append(icon('link'));
      return link;
    }
    const template = document.getElementById(`thumb-${item.thumb}`);
    return template.content.firstElementChild.cloneNode(true);
  }

  /* ---------- One working notch ---------- */

  function createNotch(root, options = {}) {
    const opts = { autoStart: true, items: EXAMPLES, keepOpenWithin: null, hint: null, ...options };
    if (!root.querySelector('.stage')) {
      const copy = blueprint.cloneNode(true);
      copy.classList.add('stage-fit');
      root.prepend(copy);
    }
    root.classList.add('demo');
    made += 1;

    const $ = (selector, scope = root) => scope.querySelector(selector);
    const $$ = (selector, scope = root) => Array.from(scope.querySelectorAll(selector));

    const stage = $('.stage');
    const notch = $('.notch');
    const trigger = $('.notch-trigger');
    const panel = $('.panel');
    const hint = $('[data-hint]');
    const hintIcon = $('[data-hint-icon]');
    const [slotL, slotR] = $$('.ear-slot');
    panel.id = `notch-panel-${made}`;
    trigger.setAttribute('aria-controls', panel.id);

    const emit = (type, detail = {}) => root.dispatchEvent(new CustomEvent('notch', { detail: { type, ...detail } }));
    const keepsOpen = (target) => opts.keepOpenWithin && opts.keepOpenWithin.contains(target);

    const s = {
      state: 'closed', // closed, compact or expanded
      module: 'np',
      lastModule: 'np',
      song: 0,
      playing: false,
      pos: 74, // seconds into the song when `since` was taken
      since: 0,
      shuffle: false,
      repeat: false,
      started: false,
      yielded: false, // music stopped and moved on from: Now Playing leaves the side spots
      visible: false,
      hovering: false,
      keyboard: false, // opened with Enter, Space or the shortcut
      byButton: false, // opened by a button beside it, not by hovering it
      hoverLocked: false, // closed with a click: hovering opens it again only after leaving
      hidden: false, // stepped aside for a full-screen film
      items: opts.items.map((item, id) => ({ ...item, id })),
      nextID: opts.items.length,
      detail: null,
      confirmingClear: false,
      waiting: null, // items that arrived at a full Shelf, while the visitor picks what goes
      picked: new Set(),
      order: ['np', 'shelf'],
      enabled: { np: true, shelf: true },
      favorites: { np: true, shelf: true },
      swap: false,
    };

    /* ---------- The notch's states ---------- */

    // While an item is open or the Shelf asks what goes, leaving with the pointer doesn't close it.
    const holdsOpen = () => s.detail !== null || s.waiting !== null;

    function setState(next) {
      if (s.state === next) return;
      s.state = next;
      notch.dataset.state = next;
      const open = next === 'expanded';
      trigger.setAttribute('aria-expanded', String(open));
      panel.inert = !open;
      if (open) endPeek();
      if (!open) {
        cancelChoosing();
        closeDetail(false);
        setConfirming(false);
        setDragging(false);
      }
      updateHint();
      updateTicking();
      emit('state', { state: next });
    }

    function open() {
      if (s.hidden) return;
      if (s.module !== 'menu' && !s.enabled[s.module]) showModule(firstEnabled() || 'menu');
      setState('expanded');
    }
    const close = () => setState(rest());

    /* Hover (mouse only), with the app's default delays. */
    let hoverTimer = 0;
    notch.addEventListener('pointerenter', (event) => {
      if (event.pointerType !== 'mouse') return;
      s.hovering = true;
      s.keyboard = false;
      s.byButton = false;
      clearTimeout(hoverTimer);
      if (!s.hoverLocked && s.state !== 'expanded') hoverTimer = setTimeout(open, 150);
    });
    notch.addEventListener('pointerleave', (event) => {
      if (event.pointerType !== 'mouse') return;
      s.hovering = false;
      s.hoverLocked = false;
      clearTimeout(hoverTimer);
      if (s.state === 'expanded' && !holdsOpen()) hoverTimer = setTimeout(close, 300);
    });

    /* Click or tap the notch (or Enter/Space on it) to open it; again to close it. */
    trigger.addEventListener('click', (event) => {
      clearTimeout(hoverTimer);
      if (s.state === 'expanded') {
        close();
        s.hoverLocked = s.hovering;
      } else {
        s.keyboard = event.detail === 0; // Enter or Space, not a click
        s.byButton = false;
        open();
      }
    });

    /* Escape steps back once: out of choosing, out of an open item, then closes the notch. */
    document.addEventListener('keydown', (event) => {
      if (event.key !== 'Escape' || s.state !== 'expanded') return;
      event.preventDefault();
      if (s.waiting !== null) {
        cancelChoosing();
      } else if (s.detail !== null) {
        closeDetail(true);
      } else {
        close();
        if (notch.contains(document.activeElement)) trigger.focus();
      }
    });

    /* Clicking or tapping anywhere else closes it. */
    document.addEventListener('pointerdown', (event) => {
      if (s.state === 'expanded' && !notch.contains(event.target) && !keepsOpen(event.target)) close();
    });

    /* Tabbing out of it closes it too. */
    notch.addEventListener('focusout', () => {
      setTimeout(() => {
        const inside = notch.contains(document.activeElement) || keepsOpen(document.activeElement);
        if (s.state === 'expanded' && !s.hovering && !inside) close();
      }, 0);
    });

    function updateHint() {
      if (!hint) return;
      const touch = touchOnly.matches;
      const opened = s.state === 'expanded';
      const own = opts.hint && opts.hint(s.state);
      hint.textContent = own || (opened
        ? (s.keyboard ? 'Press Esc to close it'
          : touch ? 'Tap outside the notch to close it'
          : holdsOpen() || s.byButton ? 'Click outside the notch to close it' : 'Move the pointer away to close it')
        : (touch ? 'Tap the notch' : 'Hover the notch'));
      hintIcon.setAttribute('href', touch ? '#i-tap' : '#i-cursor');
    }

    /* ---------- The small spots beside the notch (the app's rule) ----------
       The first two active modules in the visitor's order get them, the first on the left (or the
       right, with Swap sides). Now Playing alone fills both: art on one side, sound bars on the other. */

    const npActive = () => s.enabled.np && s.started && (s.playing || !s.yielded);
    const shelfActive = () => s.enabled.shelf && s.items.length >= NEARLY_FULL;
    const firstEnabled = () => s.order.find((module) => s.enabled[module]);

    function ears() {
      const active = s.order.filter((module) => (module === 'np' ? npActive() : shelfActive())).slice(0, 2);
      const main = { np: 'art', shelf: 'tray' };
      let pair = [null, null];
      if (active.length === 2) pair = [main[active[0]], main[active[1]]];
      else if (active.length === 1) pair = [main[active[0]], active[0] === 'np' ? 'bars' : null];
      return s.swap ? pair.reverse() : pair;
    }
    const rest = () => (s.hidden ? 'closed' : ears().some(Boolean) ? 'compact' : 'closed');

    function renderEars() {
      const [left, right] = ears();
      if (left) slotL.dataset.show = left;
      if (right) slotR.dataset.show = right;
      // An empty side keeps showing what it had while it tucks away, so nothing pops.
      slotL.classList.toggle('is-empty', !left);
      slotR.classList.toggle('is-empty', !right);
      const count = s.items.length;
      for (const badge of $$('[data-tray-count]')) {
        if (badge.textContent !== String(count)) {
          badge.textContent = String(count);
          badge.classList.remove('is-bumped');
          void badge.offsetWidth;
          badge.classList.add('is-bumped');
        }
      }
      for (const slot of [slotL, slotR]) slot.classList.toggle('is-full', count >= CAPACITY);
      if (s.state !== 'expanded') setState(rest());
    }

    /* ---------- Now Playing ---------- */

    const song = () => SONGS[s.song];
    const position = () => Math.min(song().duration, s.playing ? s.pos + (now() - s.since) / 1000 : s.pos);

    const bar = $('.np-bar');
    const seek = $('[data-seek]');
    let seeking = false;

    function renderProgress(ticking) {
      const pos = position();
      const length = song().duration;
      $('[data-elapsed]').textContent = time(pos);
      $('[data-remaining]').textContent = `-${time(length - pos)}`;
      // While ticking, the bar glides toward where it'll be in a second, so it moves smoothly.
      const target = ticking ? Math.min(length, pos + 1) : pos;
      bar.classList.toggle('is-ticking', ticking);
      bar.style.setProperty('--p', (target / length).toFixed(4));
      if (!seeking) {
        seek.max = String(length);
        seek.value = String(Math.floor(pos));
      }
      seek.setAttribute('aria-valuetext', `${time(pos)} of ${time(length)}`);
    }

    let tick = 0;
    function updateTicking() {
      const on = s.state === 'expanded' && s.module === 'np' && s.playing && s.visible && !document.hidden;
      if (on && !tick) {
        renderProgress(true);
        tick = setInterval(() => renderProgress(!seeking), 1000);
      } else if (!on && tick) {
        clearInterval(tick);
        tick = 0;
        renderProgress(false);
      }
    }

    let endTimer = 0;
    function scheduleEnd() {
      clearTimeout(endTimer);
      if (s.playing) endTimer = setTimeout(songEnded, (song().duration - position()) * 1000 + 50);
    }

    function songEnded() {
      if (s.repeat) jumpTo(0);
      else changeSong(1);
    }

    function jumpTo(seconds) {
      s.pos = Math.max(0, Math.min(song().duration, seconds));
      s.since = now();
      scheduleEnd();
      renderProgress(false);
      if (tick) requestAnimationFrame(() => renderProgress(true));
    }

    function setPlaying(playing) {
      s.pos = position();
      s.since = now();
      s.playing = playing;
      if (playing) {
        s.started = true;
        s.yielded = false;
      }
      root.classList.toggle('is-playing', playing);
      $('[data-play]').setAttribute('aria-label', playing ? 'Pause' : 'Play');
      scheduleEnd();
      renderProgress(false);
      updateTicking();
      renderLabel();
      renderEars();
      emit('play', { playing });
    }

    /* Back goes to the start of the song first, then to the one before (like the app). */
    function changeSong(step) {
      if (step < 0 && position() > 3) {
        jumpTo(0);
        emit('song', { step: 0 });
        return;
      }
      let next = (s.song + step + SONGS.length) % SONGS.length;
      if (s.shuffle && step > 0) {
        const others = SONGS.map((_, index) => index).filter((index) => index !== s.song);
        next = others[Math.floor(Math.random() * others.length)];
      }
      s.song = next;
      renderSong(true);
      jumpTo(0);
      peek();
      emit('song', { step });
    }

    function renderSong(animate) {
      const { title, artist, album } = song();
      $('[data-title]').textContent = title;
      $('[data-sub]').textContent = `${artist} · ${album}`;
      $('[data-menu-np]').textContent = title;
      $('[data-peek-title]').textContent = title;
      $('[data-peek-artist]').textContent = artist;
      for (const art of $$('[data-cover]')) {
        art.setAttribute('href', `#cover-${s.song}`);
        const svg = art.closest('svg');
        if (animate && svg) {
          svg.classList.remove('is-new');
          void svg.getBoundingClientRect();
          svg.classList.add('is-new');
        }
      }
      renderLabel();
    }

    function renderLabel() {
      const { title, artist } = song();
      trigger.setAttribute('aria-label', s.started
        ? `Notch: ${title} by ${artist}, ${s.playing ? 'playing' : 'paused'}`
        : 'Notch');
    }

    /* A new song shows its name under the small notch for 3 seconds, then tucks in (the app's peek). */
    let peekTimer = 0;
    function peek() {
      if (s.state !== 'compact' || !npActive()) return;
      notch.toggleAttribute('data-peek', true);
      clearTimeout(peekTimer);
      peekTimer = setTimeout(endPeek, 3000);
    }
    function endPeek() {
      clearTimeout(peekTimer);
      notch.removeAttribute('data-peek');
    }

    $('[data-play]').addEventListener('click', () => {
      s.started = true; // the visitor's choice wins over the automatic start
      setPlaying(!s.playing);
    });
    $('[data-next]').addEventListener('click', () => changeSong(1));
    $('[data-prev]').addEventListener('click', () => changeSong(-1));
    for (const [selector, key] of [['[data-shuffle]', 'shuffle'], ['[data-repeat]', 'repeat']]) {
      const button = $(selector);
      button.addEventListener('click', () => {
        s[key] = !s[key];
        button.setAttribute('aria-pressed', String(s[key]));
        emit(key, { on: s[key] });
      });
    }

    seek.addEventListener('input', () => {
      seeking = true;
      s.pos = Number(seek.value);
      s.since = now();
      renderProgress(false);
    });
    seek.addEventListener('change', () => {
      seeking = false;
      jumpTo(Number(seek.value));
      emit('seek');
    });

    /* ---------- Switching modules ---------- */

    function showModule(module) {
      if (module === s.module) {
        if (module === 'menu') showModule(s.lastModule); // the Menu button toggles the Menu
        return;
      }
      const forward = VIEWS.indexOf(module) > VIEWS.indexOf(s.module);
      s.module = module;
      if (module !== 'menu') s.lastModule = module;
      panel.dataset.module = module;
      cancelChoosing();
      closeDetail(false);
      setConfirming(false);
      for (const view of $$('[data-view]')) {
        const shown = view.dataset.view === module;
        view.hidden = !shown;
        view.classList.remove('enter-fwd', 'enter-back', 'enter-menu');
        if (shown) {
          void view.offsetWidth; // restart the entrance animation
          view.classList.add(module === 'menu' ? 'enter-menu' : forward ? 'enter-fwd' : 'enter-back');
        }
      }
      for (const tab of $$('.tab')) tab.setAttribute('aria-pressed', String(tab.dataset.go === module));
      for (const tile of $$('.menu-tile')) tile.classList.toggle('is-current', tile.dataset.go === s.lastModule);
      updateTicking();
      if (module === 'np') renderProgress(false);
      emit('module', { module });
    }

    for (const button of $$('[data-go]')) {
      button.addEventListener('click', () => showModule(button.dataset.go));
    }

    /* Order, favorites and switches from the Modules piece: tabs, the Menu and the side spots follow. */
    function renderModules() {
      const tabs = $('.tabs');
      const grid = $('.menu-grid');
      const list = $('.menu-all');
      const none = $('[data-menu-none]');
      for (const module of s.order) {
        const starred = s.enabled[module] && s.favorites[module];
        const tab = $(`.tab[data-go="${module}"]`);
        tab.hidden = !starred;
        tabs.append(tab);
        const tile = $(`.menu-tile[data-go="${module}"]`);
        tile.hidden = !starred;
        grid.append(tile);
        const row = $(`.menu-row[data-go="${module}"]`);
        row.hidden = !s.enabled[module];
        list.insertBefore(row, none);
      }
      $('.tab-sep').hidden = !s.order.some((module) => s.enabled[module] && s.favorites[module]);
      $('.menu-favs').hidden = !s.order.some((module) => s.enabled[module] && s.favorites[module]);
      none.hidden = Boolean(firstEnabled());
      if (s.module !== 'menu' && !s.enabled[s.module]) showModule(firstEnabled() || 'menu');
      if (!s.enabled[s.lastModule]) s.lastModule = firstEnabled() || 'np';
      renderEars();
    }

    /* ---------- The Shelf ---------- */

    const tiles = $('[data-tiles]');
    const empty = $('[data-empty]');
    const detail = $('[data-detail]');
    const clearButton = $('[data-clear]');
    const copyButton = $('[data-copy]');
    const chars = $('[data-chars]');
    const removePicked = $('[data-choose-remove]');

    function renderShelf() {
      const count = s.items.length;
      const choosing = s.waiting !== null;
      tiles.replaceChildren(...s.items.map((item) => {
        const li = el('li');
        const button = el('button', 'tile');
        button.type = 'button';
        button.dataset.id = String(item.id);
        button.setAttribute('aria-label', `${kindOf(item)}, ${nameOf(item)}`);
        if (choosing) button.setAttribute('aria-pressed', String(s.picked.has(item.id)));
        const box = el('span', 'thumb');
        box.append(thumb(item));
        const check = el('span', 'tile-check');
        check.append(icon('check'));
        button.append(box, el('span', 'tile-name', nameOf(item)), check);
        button.addEventListener('click', () => (s.waiting !== null ? pick(item.id, button) : openDetail(item.id)));
        li.append(button);
        return li;
      }));
      if (s.detail === null) {
        tiles.hidden = count === 0;
        empty.hidden = count > 0;
      }
      panel.toggleAttribute('data-empty', count === 0);
      const label = count === 1 ? '1 item' : `${count} items`;
      $('[data-shelf-count]').textContent = label;
      $('[data-menu-shelf]').textContent = count ? label : 'Empty';
      renderEars();
    }

    // A mouse wheel moves a long Shelf sideways, as a trackpad does.
    tiles.addEventListener('wheel', (event) => {
      if (Math.abs(event.deltaY) <= Math.abs(event.deltaX) || tiles.scrollWidth <= tiles.clientWidth) return;
      event.preventDefault();
      tiles.scrollLeft += event.deltaY;
    }, { passive: false });

    function openDetail(id) {
      const item = s.items.find((entry) => entry.id === id);
      if (!item) return;
      s.detail = id;
      panel.setAttribute('data-detail', '');
      $('[data-detail-kind]').textContent = kindOf(item);
      copyButton.hidden = item.kind === 'file';
      copyButton.textContent = 'Copy';
      chars.hidden = item.kind !== 'text';

      let content;
      if (item.kind === 'text') {
        // Notes can be changed right here, like in the app.
        const area = el('textarea', 'detail-text');
        area.value = item.text;
        area.maxLength = 2000;
        area.spellcheck = false;
        area.setAttribute('aria-label', 'Note');
        const count = () => { chars.textContent = `${area.value.length} characters`; };
        area.addEventListener('input', () => {
          item.text = area.value;
          count();
          copyButton.textContent = 'Copy';
          emit('note-edit');
        });
        count();
        content = [area];
      } else {
        const preview = el('div', 'detail-preview');
        preview.append(thumb(item));
        const info = el('div', 'detail-info');
        const meta = item.kind === 'link' ? item.url : item.meta;
        info.append(el('p', 'detail-name', nameOf(item)), el('p', 'detail-meta', meta));
        content = [preview, info];
      }
      detail.replaceChildren(...content);
      tiles.hidden = true;
      empty.hidden = true;
      detail.hidden = false;
      updateHint();
      $('[data-back]').focus();
      emit('shelf-open', { kind: item.kind });
    }

    function closeDetail(restoreFocus) {
      if (s.detail === null) return;
      const id = s.detail;
      const item = s.items.find((entry) => entry.id === id);
      // A note emptied while editing goes away, as in the app.
      if (item && item.kind === 'text' && !item.text.trim()) s.items = s.items.filter((entry) => entry !== item);
      s.detail = null;
      panel.removeAttribute('data-detail');
      detail.hidden = true;
      chars.hidden = true;
      renderShelf();
      updateHint();
      emit('shelf-close');
      if (restoreFocus) {
        const tile = $(`.tile[data-id="${id}"]`) || $('.tile') || $('.tab[data-go="shelf"]');
        if (tile) tile.focus();
      }
    }

    function remove(id) {
      s.items = s.items.filter((item) => item.id !== id);
      s.detail = null;
      panel.removeAttribute('data-detail');
      detail.hidden = true;
      chars.hidden = true;
      renderShelf();
      updateHint();
      const first = $('.tile') || $('[data-restore]');
      if (first) first.focus();
    }

    /* "Clear all" asks once more ("Clear 4 items?"), like the app. */
    let confirmTimer = 0;
    function setConfirming(on) {
      s.confirmingClear = on;
      clearTimeout(confirmTimer);
      const count = s.items.length;
      clearButton.textContent = on ? (count === 1 ? 'Clear 1 item?' : `Clear ${count} items?`) : 'Clear all';
      clearButton.classList.toggle('is-prominent', on);
      if (on) confirmTimer = setTimeout(() => setConfirming(false), 4000);
    }

    clearButton.addEventListener('click', () => {
      if (!s.confirmingClear) {
        setConfirming(true);
        return;
      }
      setConfirming(false);
      s.items = [];
      renderShelf();
      $('[data-restore]').focus();
      emit('shelf-clear');
    });

    $('[data-restore]').addEventListener('click', () => {
      setItems(EXAMPLES);
      const first = $('.tile');
      if (first) first.focus();
    });

    $('[data-back]').addEventListener('click', () => closeDetail(true));
    $('[data-remove]').addEventListener('click', () => {
      if (s.detail !== null) remove(s.detail);
    });

    copyButton.addEventListener('click', async () => {
      const item = s.items.find((entry) => entry.id === s.detail);
      if (!item || !navigator.clipboard) return;
      try {
        await navigator.clipboard.writeText(item.kind === 'link' ? item.url : item.text);
        copyButton.textContent = 'Copied';
      } catch {
        copyButton.textContent = 'Couldn’t copy';
      }
    });

    /* A full Shelf: what arrives waits while the visitor picks what goes (the app's prompt). */
    function startChoosing(inputs) {
      if (s.state !== 'expanded') open();
      if (s.state !== 'expanded') return;
      if (s.module !== 'shelf') showModule('shelf');
      closeDetail(false);
      s.waiting = inputs;
      s.picked.clear();
      panel.setAttribute('data-choosing', '');
      renderShelf();
      renderPicked();
      updateHint();
      emit('choose');
    }

    function cancelChoosing() {
      if (s.waiting === null) return;
      s.waiting = null;
      s.picked.clear();
      panel.removeAttribute('data-choosing');
      renderShelf();
      updateHint();
    }

    function pick(id, button) {
      if (s.picked.has(id)) s.picked.delete(id);
      else s.picked.add(id);
      button.setAttribute('aria-pressed', String(s.picked.has(id)));
      renderPicked();
    }

    function renderPicked() {
      const count = s.picked.size;
      removePicked.textContent = count ? `Remove ${count}` : 'Remove';
      removePicked.disabled = count === 0;
    }

    $('[data-choose-cancel]').addEventListener('click', () => {
      cancelChoosing();
      const first = $('.tile');
      if (first) first.focus();
    });
    removePicked.addEventListener('click', () => {
      const waiting = s.waiting;
      s.items = s.items.filter((item) => !s.picked.has(item.id));
      s.waiting = null;
      s.picked.clear();
      panel.removeAttribute('data-choosing');
      add(waiting);
      updateHint();
      const first = $('.tile');
      if (first) first.focus();
    });

    /* Drop real files, text or links on the notch and they land on its Shelf. Only names are read;
       nothing is opened, kept or sent anywhere. */
    const canDrop = (data) => data && Array.from(data.types).some((type) => type === 'Files' || type.startsWith('text/'));
    let dragDepth = 0;

    function setDragging(on) {
      root.classList.toggle('is-dragging', on);
      if (!on) dragDepth = 0;
    }

    stage.addEventListener('dragenter', (event) => {
      if (!canDrop(event.dataTransfer) || s.hidden) return;
      event.preventDefault();
      dragDepth += 1;
      if (s.state !== 'expanded') open();
      if (s.enabled.shelf) showModule('shelf');
      cancelChoosing();
      closeDetail(false);
      setDragging(true);
    });
    stage.addEventListener('dragover', (event) => {
      if (!canDrop(event.dataTransfer) || s.hidden) return;
      event.preventDefault();
      event.dataTransfer.dropEffect = 'copy';
    });
    stage.addEventListener('dragleave', () => {
      dragDepth = Math.max(0, dragDepth - 1);
      if (dragDepth === 0) setDragging(false);
    });
    stage.addEventListener('drop', (event) => {
      if (!canDrop(event.dataTransfer) || s.hidden) return;
      event.preventDefault();
      setDragging(false);
      add(readDrop(event.dataTransfer));
    });

    function readDrop(data) {
      const files = Array.from(data.files || []);
      if (files.length) {
        return files.map((file) => {
          const image = file.type.startsWith('image/');
          const kind = image ? 'Image' : file.type ? 'Document' : 'File';
          return { kind: 'file', name: file.name, meta: `${kind} · ${size(file.size)}`, thumb: image ? 'image' : 'doc' };
        });
      }
      const link = (data.getData('text/uri-list') || '').split(/\r?\n/).find((line) => line && !line.startsWith('#'));
      if (link && /^(https?|mailto):/i.test(link)) return [{ kind: 'link', url: link.trim() }];
      const text = (data.getData('text/plain') || '').trim().slice(0, 2000);
      if (!text) return [];
      if (!/\s/.test(text) && /^https?:\/\//i.test(text)) return [{ kind: 'link', url: text }];
      return [{ kind: 'text', text }];
    }

    function add(inputs) {
      if (!inputs || !inputs.length) {
        renderShelf();
        return;
      }
      if (s.items.length + inputs.length > CAPACITY) {
        renderShelf();
        startChoosing(inputs);
        return;
      }
      const added = inputs.map((item) => ({ ...item, id: s.nextID++ }));
      s.items = [...added.reverse(), ...s.items];
      renderShelf();
      emit('shelf-add', { count: added.length });
    }

    function setItems(list) {
      s.waiting = null;
      s.picked.clear();
      panel.removeAttribute('data-choosing');
      if (s.detail !== null) {
        s.detail = null;
        panel.removeAttribute('data-detail');
        detail.hidden = true;
        chars.hidden = true;
      }
      s.items = list.map((item) => ({ ...item, id: s.nextID++ }));
      renderShelf();
      updateHint();
    }

    /* ---------- Only work while someone can see it ---------- */

    function start() {
      if (s.started) return;
      setPlaying(true);
    }

    let startTimer = 0;
    function setVisible(visible) {
      s.visible = visible;
      root.classList.toggle('is-visible', visible);
      if (visible && opts.autoStart && !s.started && !startTimer) startTimer = setTimeout(start, 700);
      updateTicking();
    }

    if ('IntersectionObserver' in window) {
      new IntersectionObserver((entries) => setVisible(entries[0].isIntersecting), { threshold: 0.2 }).observe(stage);
    } else {
      setVisible(true);
    }
    document.addEventListener('visibilitychange', updateTicking);
    touchOnly.addEventListener('change', updateHint);

    /* ---------- First paint ---------- */

    root.classList.remove('is-playing');
    notch.dataset.state = 'closed';
    notch.removeAttribute('data-peek');
    panel.inert = true;
    renderSong(false);
    renderProgress(false);
    renderShelf();
    updateHint();

    /* ---------- What the live pieces can do with it ---------- */

    const api = {
      root,
      get state() { return s.state; },
      get playing() { return s.playing; },
      get count() { return s.items.length; },
      get hidden() { return s.hidden; },
      open() { s.keyboard = false; s.byButton = true; open(); },
      close,
      toggle() {
        if (s.state === 'expanded') close();
        else { s.keyboard = true; s.byButton = false; open(); }
      },
      show(module) {
        if (s.state !== 'expanded') {
          s.keyboard = false;
          s.byButton = true;
          open();
        }
        if (module === 'menu' && s.module === 'menu') return;
        showModule(module);
      },
      play(on) { setPlaying(on); },
      peek() { peek(); },
      next() {
        if (s.state === 'expanded') close();
        if (!npActive()) setPlaying(true);
        changeSong(1);
      },
      stopMusic() {
        setPlaying(false);
        s.yielded = true;
        renderEars();
      },
      setItems,
      fill(total, make) {
        setItems(Array.from({ length: total }, (_, index) => (index < EXAMPLES.length ? EXAMPLES[index] : make(index - EXAMPLES.length + 1))));
      },
      add(item) { add([item]); },
      takeOne() {
        s.items = s.items.slice(1);
        renderShelf();
      },
      openNote() {
        let note = s.items.find((item) => item.kind === 'text');
        if (!note) {
          add([EXAMPLES[2]]);
          note = s.items.find((item) => item.kind === 'text');
        }
        if (!note) return;
        api.show('shelf');
        if (s.state === 'expanded') openDetail(note.id);
      },
      arrange({ order, enabled, favorites, swap }) {
        if (order) s.order = order.slice();
        if (enabled) s.enabled = { ...enabled };
        if (favorites) s.favorites = { ...favorites };
        if (swap !== undefined) s.swap = swap;
        renderModules();
      },
      setHidden(on) {
        if (s.hidden === on) return;
        s.hidden = on;
        notch.toggleAttribute('data-hidden', on);
        trigger.tabIndex = on ? -1 : 0;
        if (on) {
          endPeek();
          setState('closed');
        } else {
          setState(s.state === 'expanded' ? 'expanded' : rest());
        }
      },
      refreshHint: updateHint,
    };
    root.notch = api;
    return api;
  }

  window.PancakeNotch = { create: createNotch };
  createNotch(hero);
})();
