/* The live pieces on the home page: the notch's seven shapes, a lesson, the Modules page, the
   shortcut recorder, full-screen hiding and Statistics. Each one is a small working copy of that
   part of the app, built on the notch in demo.js. Nothing here runs on a timer while it sits still. */
(() => {
  'use strict';

  const make = window.PancakeNotch && window.PancakeNotch.create;
  if (!make) return;

  const touchOnly = matchMedia('(hover: none)');
  const $ = (selector, scope = document) => scope.querySelector(selector);
  const $$ = (selector, scope = document) => Array.from(scope.querySelectorAll(selector));
  const file = (number) => ({ kind: 'file', name: `File ${number}.pdf`, meta: 'PDF document · 120 KB', thumb: 'pdf' });
  let arrivals = 0;
  const arrival = () => {
    arrivals += 1;
    return { kind: 'file', name: `New file ${arrivals}.pdf`, meta: 'PDF document · 96 KB', thumb: 'doc' };
  };

  /* A row of choices (role="radio"): click, or arrow keys like the app's segmented controls. */
  function segmented(group, onChange) {
    const options = $$('[role="radio"]', group);
    const choose = (option, focus) => {
      for (const other of options) {
        const on = other === option;
        other.setAttribute('aria-checked', String(on));
        other.tabIndex = on ? 0 : -1;
      }
      if (focus) option.focus();
      onChange(option);
    };
    for (const option of options) {
      option.tabIndex = option.getAttribute('aria-checked') === 'true' ? 0 : -1;
      option.addEventListener('click', () => choose(option, false));
      option.addEventListener('keydown', (event) => {
        const step = { ArrowRight: 1, ArrowDown: 1, ArrowLeft: -1, ArrowUp: -1 }[event.key];
        if (!step) return;
        event.preventDefault();
        choose(options[(options.indexOf(option) + step + options.length) % options.length], true);
      });
    }
  }

  /* ---------- One notch, seven shapes ---------- */

  const shapes = $('.shapes');
  if (shapes) {
    const notch = make($('[data-live-notch="shapes"]', shapes), { keepOpenWithin: shapes });
    const buttons = $$('[data-shape]', shapes);
    const actions = $$('[data-act]', shapes);
    const take = $('[data-act="take"]', shapes);
    let current = 'song';

    const ensureMusic = () => { if (!notch.playing) notch.play(true); };
    const shapeOf = {
      song() {
        notch.fill(4, file);
        notch.next();
      },
      player() {
        if (notch.count >= 15) notch.fill(4, file);
        ensureMusic();
        notch.show('np');
      },
      menu() {
        ensureMusic();
        notch.show('menu');
      },
      shelf() {
        if (notch.count === 0 || notch.count >= 15) notch.fill(4, file);
        notch.show('shelf');
      },
      note() {
        if (notch.count >= 15) notch.fill(4, file);
        notch.openNote();
      },
      choose() {
        notch.fill(20, file);
        notch.show('shelf');
        notch.add(arrival());
      },
      count() {
        notch.close();
        notch.fill(16, file);
        notch.stopMusic();
      },
    };

    const renderActions = () => {
      for (const action of actions) action.hidden = action.dataset.for !== current;
      take.disabled = notch.count === 0;
    };

    for (const button of buttons) {
      button.addEventListener('click', () => {
        current = button.dataset.shape;
        for (const other of buttons) other.setAttribute('aria-pressed', String(other === button));
        shapeOf[current]();
        renderActions();
      });
    }

    const act = {
      next: () => notch.next(),
      drop: () => {
        if (notch.count < 20) notch.fill(20, file);
        notch.add(arrival());
      },
      add: () => notch.add(arrival()),
      take: () => notch.takeOne(),
    };
    for (const action of actions) action.addEventListener('click', () => act[action.dataset.act]());
    notch.root.addEventListener('notch', renderActions);

    // The first time it settles beside the notch, the song shows its name (the shape picked first).
    const firstPeek = (event) => {
      if (event.detail.type !== 'state' || event.detail.state !== 'compact') return;
      notch.root.removeEventListener('notch', firstPeek);
      if (current === 'song') setTimeout(() => notch.peek(), 500);
    };
    notch.root.addEventListener('notch', firstPeek);
    renderActions();
  }

  /* ---------- A lesson (the app's Now Playing lesson) ---------- */

  const learn = $('[data-live="learn"]');
  if (learn) {
    const notch = make($('[data-live-notch]', learn), { keepOpenWithin: learn });
    const say = (text) => (touchOnly.matches ? text.replace(/\bClick/g, 'Tap').replace(/\bclick/g, 'tap') : text);
    const STEPS = [
      {
        title: 'Open the player',
        detail: () => (touchOnly.matches
          ? 'A pretend song is playing: see its album art and sound bars beside the notch? Tap the notch to open it.'
          : 'A pretend song is playing: see its album art and sound bars beside the notch? Hover the notch to open it.'),
        done: (e) => e.type === 'state' && e.state === 'expanded',
      },
      { title: 'Pause the song', detail: () => say('Click the pause button in the middle.'), done: (e) => e.type === 'play' && !e.playing },
      { title: 'Play it again', detail: () => 'The same button carries on where you left off.', done: (e) => e.type === 'play' && e.playing },
      {
        title: 'Skip to the next song',
        detail: () => say('Click the forward button. The back button goes to the start of the song, then the one before.'),
        done: (e) => e.type === 'song' && e.step === 1,
      },
      { title: 'Jump to another part', detail: () => say('Drag along the progress bar, or click anywhere on it.'), done: (e) => e.type === 'seek' },
      {
        title: 'Turn on shuffle or repeat',
        detail: () => 'The small buttons at either end. They light up while they’re on.',
        done: (e) => (e.type === 'shuffle' || e.type === 'repeat') && e.on,
      },
      { title: 'Switch to the Shelf', detail: () => 'Pick it at the top left of the open notch.', done: (e) => e.type === 'module' && e.module === 'shelf' },
    ];

    const count = $('[data-learn-count]', learn);
    const title = $('[data-learn-title]', learn);
    const detail = $('[data-learn-detail]', learn);
    const mark = $('[data-learn-mark]', learn);
    const back = $('[data-learn-back]', learn);
    const skip = $('[data-learn-skip]', learn);
    let step = 0;
    let advancing = 0;

    function render() {
      clearTimeout(advancing);
      advancing = 0;
      mark.classList.remove('is-done');
      const finished = step >= STEPS.length;
      count.textContent = finished ? 'Done' : `Step ${step + 1} of ${STEPS.length}`;
      title.textContent = finished ? 'Lesson done' : STEPS[step].title;
      detail.textContent = finished
        ? 'That’s the player. The app has two more lessons, Notch basics and the Shelf, in its Learn page.'
        : STEPS[step].detail();
      mark.classList.toggle('is-done', finished);
      back.disabled = step === 0;
      skip.textContent = finished ? 'Start Again' : 'Skip Step';
    }

    notch.root.addEventListener('notch', (event) => {
      if (advancing || step >= STEPS.length || !STEPS[step].done(event.detail)) return;
      mark.classList.add('is-done');
      advancing = setTimeout(() => {
        step += 1;
        render();
      }, 700);
    });
    back.addEventListener('click', () => {
      step = Math.max(0, step - 1);
      render();
    });
    skip.addEventListener('click', () => {
      if (step >= STEPS.length) {
        step = 0;
        notch.close();
        if (!notch.playing) notch.play(true);
      } else {
        step += 1;
      }
      render();
    });
    touchOnly.addEventListener('change', render);
    render();
  }

  /* ---------- Modules: order, favorites, switches, sides ---------- */

  const modules = $('[data-live="modules"]');
  if (modules) {
    const notch = make($('[data-live-notch]', modules), { keepOpenWithin: modules });
    notch.fill(16, file);
    const list = $('[data-mod-list]', modules);
    const rows = Object.fromEntries($$('[data-mod]', modules).map((row) => [row.dataset.mod, row]));
    const names = { np: 'Now Playing', shelf: 'Shelf' };
    const m = { order: ['np', 'shelf'], enabled: { np: true, shelf: true }, favorites: { np: true, shelf: true }, swap: false };

    // Where its spot is, in the app's words.
    function status(id) {
      if (!m.enabled[id]) return 'Off';
      const place = m.order.filter((other) => m.enabled[other]).indexOf(id);
      if (place === 0) return m.swap ? 'Right of the notch when active' : 'Left of the notch when active';
      return m.swap
        ? 'Left of the notch when active, or right when it’s the only one'
        : 'Right of the notch when active, or left when it’s the only one';
    }

    function render() {
      m.order.forEach((id, index) => {
        const row = rows[id];
        list.append(row);
        $('[data-rank]', row).textContent = String(index + 1);
        $('[data-status]', row).textContent = status(id);
        $('[data-up]', row).disabled = index === 0;
        $('[data-down]', row).disabled = index === m.order.length - 1;
        $('[data-star]', row).setAttribute('aria-pressed', String(m.favorites[id]));
        $('[data-on]', row).setAttribute('aria-checked', String(m.enabled[id]));
        row.classList.toggle('is-off', !m.enabled[id]);
      });
      $('[data-swap]', modules).setAttribute('aria-checked', String(m.swap));
      notch.arrange(m);
    }

    function move(id, by, button) {
      const from = m.order.indexOf(id);
      const to = Math.max(0, Math.min(m.order.length - 1, from + by));
      if (from === to) return;
      m.order.splice(to, 0, ...m.order.splice(from, 1));
      render();
      // Keep the keyboard where it was; if that arrow is now disabled, use the other one.
      const again = button.disabled ? $(by < 0 ? '[data-down]' : '[data-up]', rows[id]) : button;
      again.focus();
      $('[data-mod-live]', modules).textContent = `${names[id]}, now number ${to + 1}`;
    }

    for (const [id, row] of Object.entries(rows)) {
      $('[data-up]', row).addEventListener('click', (event) => move(id, -1, event.currentTarget));
      $('[data-down]', row).addEventListener('click', (event) => move(id, 1, event.currentTarget));
      $('[data-star]', row).addEventListener('click', () => {
        m.favorites[id] = !m.favorites[id];
        render();
      });
      $('[data-on]', row).addEventListener('click', () => {
        m.enabled[id] = !m.enabled[id];
        render();
      });
    }
    $('[data-swap]', modules).addEventListener('click', () => {
      m.swap = !m.swap;
      render();
    });
    const live = document.createElement('span');
    live.className = 'visually-hidden';
    live.dataset.modLive = '';
    live.setAttribute('aria-live', 'polite');
    modules.append(live);
    render();
  }

  /* ---------- A keyboard shortcut ---------- */

  const keys = $('[data-live="keys"]');
  if (keys) {
    const MODS = [['ctrl', '⌃'], ['alt', '⌥'], ['shift', '⇧'], ['meta', '⌘']];
    // The shortcuts the app refuses because macOS or every app already uses them (HotKey.swift).
    const RESERVED = [
      ['meta', 'KeyQ KeyW KeyH KeyM Comma Tab Space Backquote KeyA KeyC KeyV KeyX KeyZ KeyS KeyO KeyN KeyP KeyF KeyT'],
      ['shift meta', 'KeyQ KeyZ Digit3 Digit4 Digit5 Tab'],
      ['alt meta', 'Escape KeyD KeyH Space'],
      ['ctrl', 'Space ArrowUp ArrowDown ArrowLeft ArrowRight'],
      ['ctrl meta', 'KeyQ KeyF Space'],
    ].flatMap(([mods, codes]) => codes.split(' ').map((code) => `${mods}+${code}`));
    const NAMED = {
      Space: 'Space', Enter: '↩', Tab: '⇥', Backspace: '⌫', Delete: '⌦', Escape: 'Esc', ArrowLeft: '←', ArrowRight: '→',
      ArrowUp: '↑', ArrowDown: '↓', Home: '↖', End: '↘', PageUp: '⇞', PageDown: '⇟', Backquote: '`', Minus: '-',
      Equal: '=', BracketLeft: '[', BracketRight: ']', Backslash: '\\', Semicolon: ';', Quote: '\'', Comma: ',', Period: '.', Slash: '/',
    };
    const keyName = (code) => {
      if (/^Key[A-Z]$/.test(code)) return code.slice(3);
      if (/^Digit\d$/.test(code)) return code.slice(5);
      if (/^F\d{1,2}$/.test(code)) return code;
      return NAMED[code] || null;
    };
    const parts = (combo) => [...MODS.filter(([mod]) => combo[mod]).map(([, sign]) => sign), keyName(combo.code)];
    const text = (combo) => parts(combo).join('');
    const signature = (combo) => `${MODS.filter(([mod]) => combo[mod]).map(([mod]) => mod).join(' ')}+${combo.code}`;
    const fromEvent = (event) => ({ ctrl: event.ctrlKey, alt: event.altKey, shift: event.shiftKey, meta: event.metaKey, code: event.code });

    const rec = $('[data-rec]', keys);
    const label = $('[data-rec-label]', keys);
    const clear = $('[data-rec-clear]', keys);
    const hint = $('[data-rec-hint]', keys);
    let combo = { ctrl: false, alt: true, shift: false, meta: true, code: 'KeyN' };
    let recording = false;

    const notch = make($('[data-live-notch]', keys), {
      keepOpenWithin: keys,
      hint: (state) => (combo ? (state === 'expanded' ? `Press ${text(combo)} again to close it` : `Press ${text(combo)}`) : null),
    });

    function renderKeys() {
      rec.classList.toggle('is-recording', recording);
      rec.setAttribute('aria-pressed', String(recording));
      if (recording) label.textContent = 'Type a shortcut';
      else if (combo) label.replaceChildren(...parts(combo).map((part) => Object.assign(document.createElement('kbd'), { textContent: part })));
      else label.textContent = 'Record Shortcut';
      clear.hidden = !combo || recording;
      notch.refreshHint();
    }

    function stop() {
      recording = false;
      renderKeys();
    }

    rec.addEventListener('click', () => {
      recording = !recording;
      hint.textContent = recording ? 'Press the keys you want. Esc cancels, Delete clears.' : hint.textContent;
      renderKeys();
    });
    rec.addEventListener('blur', () => { if (recording) stop(); });
    clear.addEventListener('click', () => {
      combo = null;
      hint.textContent = 'No shortcut now. Click Record Shortcut to set one.';
      renderKeys();
      rec.focus();
    });

    addEventListener('keydown', (event) => {
      if (recording) {
        if (/^(Meta|Alt|Control|Shift|CapsLock|Fn)/.test(event.code) || event.key === 'Dead' && !event.code) return;
        event.preventDefault();
        event.stopPropagation();
        const plain = !event.ctrlKey && !event.altKey && !event.metaKey && !event.shiftKey;
        if (event.code === 'Escape' && plain) {
          hint.textContent = combo ? `Kept ${text(combo)}.` : 'No shortcut set.';
          stop();
          return;
        }
        if ((event.code === 'Backspace' || event.code === 'Delete') && plain) {
          combo = null;
          hint.textContent = 'No shortcut now. Click Record Shortcut to set one.';
          stop();
          return;
        }
        const next = fromEvent(event);
        if (!keyName(next.code)) return;
        if (!next.ctrl && !next.alt && !next.meta && !/^F\d{1,2}$/.test(next.code)) {
          hint.textContent = 'Include ⌘, ⌥ or ⌃ (or use a function key).';
          return;
        }
        if (RESERVED.includes(signature(next))) {
          hint.textContent = `${text(next)} is a system shortcut. Try another, like ⌥⌘N.`;
          return;
        }
        combo = next;
        hint.textContent = `${text(combo)} now opens and closes the notch. Try it.`;
        stop();
        return;
      }
      if (!combo || event.repeat || event.code !== combo.code) return;
      if (MODS.some(([mod]) => event[`${mod}Key`] !== combo[mod])) return;
      event.preventDefault();
      notch.toggle();
    }, true);

    renderKeys();
  }

  /* ---------- Full screen: the notch steps aside for a film ---------- */

  const fs = $('[data-live="fullscreen"]');
  if (fs) {
    const mount = $('[data-live-notch]', fs);
    const notch = make(mount, { keepOpenWithin: fs });
    const screen = $('.screen', mount);
    const status = $('[data-fs-status]', fs);
    const IDLE = 3000; // how long you sit still before it hides again (the app waits a few seconds)

    const film = document.createElement('div');
    film.className = 'film';
    film.innerHTML = `
      <div class="film-scene" aria-hidden="true"><span class="film-moon"></span><span class="film-hill film-hill-a"></span><span class="film-hill film-hill-b"></span></div>
      <button class="film-watch" type="button" data-film-watch><svg class="icon" aria-hidden="true"><use href="#i-play"/></svg>Watch full screen</button>
      <div class="film-bar">
        <button class="film-btn" type="button" data-film-play aria-label="Pause the film"><svg class="icon when-on" aria-hidden="true"><use href="#i-pause"/></svg><svg class="icon when-off" aria-hidden="true"><use href="#i-play"/></svg></button>
        <span class="film-track" aria-hidden="true"><span class="film-progress"></span></span>
        <button class="film-btn" type="button" data-film-exit aria-label="Leave full screen"><svg class="icon" aria-hidden="true"><use href="#i-expand"/></svg></button>
      </div>`;
    screen.prepend(film);

    const watch = $('[data-film-watch]', film);
    const playButton = $('[data-film-play]', film);
    const exit = $('[data-film-exit]', film);
    const f = { mode: 'whileWatching', full: false, playing: false, active: false };
    let idle = 0;

    function render() {
      const hides = f.full && (f.mode === 'always' || (f.mode === 'whileWatching' && f.playing && !f.active));
      mount.classList.toggle('is-full', f.full);
      film.classList.toggle('is-playing', f.full && f.playing);
      film.classList.toggle('shows-bar', f.full && (f.active || !f.playing));
      playButton.setAttribute('aria-label', f.playing ? 'Pause the film' : 'Play the film');
      watch.hidden = f.full;
      notch.setHidden(hides);
      status.textContent = !f.full ? 'Press Watch to play the film full screen.'
        : f.mode === 'never' ? 'Never: the notch works as usual in full screen.'
        : f.mode === 'always' ? 'Always: the notch stays hidden while the film fills the screen.'
        : !f.playing ? 'The film is paused, so the notch is back.'
        : hides ? 'The notch has stepped aside. Move the pointer over the screen and it comes back.'
        : 'You moved, so the notch is back until you sit still.';
    }

    function nudge() {
      if (!f.full) return;
      f.active = true;
      clearTimeout(idle);
      idle = setTimeout(() => {
        f.active = false;
        render();
      }, IDLE);
      render();
    }

    watch.addEventListener('click', () => {
      f.full = true;
      f.playing = true;
      f.active = false;
      render();
      playButton.focus({ preventScroll: true });
    });
    playButton.addEventListener('click', () => {
      f.playing = !f.playing;
      render();
    });
    exit.addEventListener('click', () => {
      f.full = false;
      f.playing = false;
      clearTimeout(idle);
      render();
      watch.focus();
    });
    for (const type of ['pointermove', 'wheel', 'pointerdown', 'focusin']) mount.addEventListener(type, nudge, { passive: true });
    film.addEventListener('keydown', (event) => {
      if (event.key === 'Escape' && f.full) exit.click();
    });
    segmented($('.seg-ctl', fs), (option) => {
      f.mode = option.dataset.fsMode;
      render();
    });
    render();
  }

  /* ---------- Statistics ---------- */

  const stats = $('[data-live="stats"]');
  if (stats) {
    const DAYS = 90;
    // Made-up listening for the last 90 days: steady, a little busier at the weekend. Fixed, not random.
    let seed = 7;
    const rand = () => {
      seed = (seed * 16807) % 2147483647;
      return seed / 2147483647;
    };
    const today = new Date();
    today.setHours(12, 0, 0, 0);
    const EXAMPLE = Array.from({ length: DAYS }, (_, index) => {
      const date = new Date(today);
      date.setDate(today.getDate() - (DAYS - 1 - index));
      const weekend = date.getDay() === 0 || date.getDay() === 6;
      const minutes = Math.round((weekend ? 34 : 20) + rand() * 30 - (rand() < 0.12 ? 18 : 0));
      return { date, minutes: Math.max(0, minutes) };
    });
    const SONGS = [
      { title: 'Pancake Sunrise', artist: 'The Flipsides', share: 0.46 },
      { title: 'Golden Edges', artist: 'Maple & Co.', share: 0.33 },
      { title: 'Night Owl', artist: 'Syrup Static', share: 0.21 },
    ];

    const chart = $('[data-chart]', stats);
    const readout = $('[data-readout]', stats);
    const average = $('[data-stats-avg]', stats);
    const tops = $('[data-tops]', stats);
    const body = $('[data-stats-body]', stats);
    const empty = $('[data-stats-empty]', stats);
    const clear = $('[data-stats-clear]', stats);
    const note = $('[data-stats-note]', stats);
    const st = { range: 7, selected: -1, cleared: false, confirming: false };
    let confirmTimer = 0;

    const minutes = (value) => (value < 60 ? `${value} min` : `${Math.floor(value / 60)} h ${value % 60} min`);
    const dayName = (date, long) => date.toLocaleDateString('en-GB', long
      ? { weekday: 'short', day: 'numeric', month: 'short' }
      : st.range === 7 ? { weekday: 'short' } : { day: 'numeric', month: 'short' });
    const days = () => EXAMPLE.slice(-st.range);

    function renderChart() {
      const list = days();
      const top = Math.max(10, Math.ceil(Math.max(...list.map((day) => day.minutes)) / 10) * 10);
      const plot = document.createElement('div');
      plot.className = 'chart-plot';
      plot.style.setProperty('--n', String(list.length));
      for (const value of [top, top / 2, 0]) {
        const line = document.createElement('span');
        line.className = 'chart-line';
        line.style.setProperty('--y', String(value / top));
        line.dataset.value = String(value);
        plot.append(line);
      }
      const bars = document.createElement('div');
      bars.className = 'chart-bars';
      list.forEach((day, index) => {
        const bar = document.createElement('span');
        bar.className = 'chart-bar';
        bar.style.setProperty('--v', String(day.minutes / top));
        bar.classList.toggle('is-on', index === st.selected);
        bars.append(bar);
      });
      plot.append(bars);
      const tip = document.createElement('span');
      tip.className = 'chart-tip';
      tip.setAttribute('aria-hidden', 'true');
      plot.append(tip);
      const axis = document.createElement('div');
      axis.className = 'chart-axis';
      axis.setAttribute('aria-hidden', 'true');
      const every = st.range === 7 ? 1 : st.range === 30 ? 7 : 21;
      list.forEach((day, index) => {
        if ((list.length - 1 - index) % every !== 0) return;
        const tick = document.createElement('span');
        tick.textContent = index === list.length - 1 ? 'Today' : dayName(day.date, false);
        tick.style.setProperty('--x', String((index + 0.5) / list.length));
        axis.append(tick);
      });
      chart.replaceChildren(plot, axis);
      renderSelection();
    }

    function renderSelection() {
      const list = days();
      const bars = $$('.chart-bar', chart);
      bars.forEach((bar, index) => bar.classList.toggle('is-on', index === st.selected));
      const tip = $('.chart-tip', chart);
      if (st.selected < 0) {
        tip.hidden = true;
        readout.textContent = touchOnly.matches ? 'Tap a bar for that day.' : 'Point at a bar, or use the arrow keys, for that day.';
        return;
      }
      const day = list[st.selected];
      const words = `${st.selected === list.length - 1 ? 'Today' : dayName(day.date, true)}: ${minutes(day.minutes)}`;
      tip.hidden = false;
      tip.textContent = minutes(day.minutes);
      tip.style.setProperty('--x', String((st.selected + 0.5) / list.length));
      tip.style.setProperty('--v', bars[st.selected].style.getPropertyValue('--v'));
      readout.textContent = words;
    }

    function renderTops() {
      const total = days().reduce((sum, day) => sum + day.minutes, 0);
      average.textContent = `About ${minutes(Math.round(total / st.range))} a day`;
      tops.replaceChildren(...SONGS.map((song, index) => {
        const li = document.createElement('li');
        li.innerHTML = `<svg class="art" viewBox="0 0 100 100" aria-hidden="true"><use href="#cover-${index}"/></svg>
          <span class="top-text"><span class="top-title"></span><span class="top-artist"></span></span><span class="top-time"></span>`;
        $('.top-title', li).textContent = song.title;
        $('.top-artist', li).textContent = song.artist;
        $('.top-time', li).textContent = minutes(Math.round(total * song.share));
        return li;
      }));
    }

    function render() {
      body.hidden = st.cleared;
      empty.hidden = !st.cleared;
      clear.hidden = st.cleared;
      $('.seg-ctl', stats).hidden = st.cleared;
      if (st.cleared) {
        average.textContent = 'Nothing yet';
        return;
      }
      renderChart();
      renderTops();
    }

    // Point, tap or use the arrow keys to read a day.
    const pickAt = (event) => {
      const bars = $('.chart-bars', chart);
      if (!bars) return;
      const box = bars.getBoundingClientRect();
      const index = Math.floor(((event.clientX - box.left) / box.width) * st.range);
      if (index < 0 || index >= st.range || index === st.selected) return;
      st.selected = index;
      renderSelection();
    };
    chart.addEventListener('pointermove', pickAt);
    chart.addEventListener('pointerdown', pickAt);
    chart.addEventListener('pointerleave', (event) => {
      if (event.pointerType !== 'mouse' || document.activeElement === chart) return;
      st.selected = -1;
      renderSelection();
    });
    chart.addEventListener('keydown', (event) => {
      const last = st.range - 1;
      const next = {
        ArrowLeft: Math.max(0, (st.selected < 0 ? last : st.selected) - 1),
        ArrowRight: Math.min(last, (st.selected < 0 ? last - 1 : st.selected) + 1),
        Home: 0,
        End: last,
      }[event.key];
      if (next === undefined) return;
      event.preventDefault();
      st.selected = next;
      renderSelection();
    });
    chart.addEventListener('focus', () => {
      if (st.selected >= 0) return;
      st.selected = st.range - 1;
      renderSelection();
    });

    segmented($('.seg-ctl', stats), (option) => {
      st.range = Number(option.dataset.range);
      st.selected = -1;
      render();
    });

    function setConfirming(on) {
      st.confirming = on;
      clearTimeout(confirmTimer);
      clear.textContent = on ? 'Clear All Statistics?' : 'Clear Statistics';
      clear.classList.toggle('is-prominent', on);
      note.textContent = on ? 'Click again to delete all statistics.' : st.cleared ? 'Cleared. New statistics start from now.' : 'Kept for 90 days, only on this Mac.';
      if (on) confirmTimer = setTimeout(() => setConfirming(false), 4000);
    }
    clear.addEventListener('click', () => {
      if (!st.confirming) {
        setConfirming(true);
        return;
      }
      st.cleared = true;
      setConfirming(false);
      render();
      $('[data-stats-restore]', stats).focus();
    });
    $('[data-stats-restore]', stats).addEventListener('click', () => {
      st.cleared = false;
      st.selected = -1;
      setConfirming(false);
      render();
      clear.focus();
    });
    render();
  }
})();
