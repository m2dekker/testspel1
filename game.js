(() => {
  'use strict';

  // ?fast in the URL runs everything 10x faster (for testing).
  const FAST = new URLSearchParams(location.search).has('fast');
  const TICK_MS = FAST ? 100 : 1000;
  const CD_SCALE = FAST ? 0.1 : 1;
  const SAVE_KEY = 'the-signal-v1';

  const $ = (sel) => document.querySelector(sel);
  const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
  const rand = (a, b) => a + Math.floor(Math.random() * (b - a + 1));
  const pick = (arr) => arr[Math.floor(Math.random() * arr.length)];
  const round1 = (v) => Math.round(v * 10) / 10;
  const fmt = (f) => f.toFixed(1);

  // ================================================================
  // state
  // ================================================================

  let s;
  let resetting = false;

  function fresh() {
    return {
      v: 1,
      t: 0,
      phase: 1,
      power: 0,
      res: { fuel: 0, parts: 0, food: 0 },
      seen: {},
      flags: {},
      antenna: 1,
      freq: 90.0,
      loot: 0,
      stations: {},
      contacts: {},
      talk: null,
      pop: 0,
      jobs: { woodcutter: 0, forager: 0, scavenger: 0, cranker: 0 },
      builds: { lean: 0, bench: 0, mast: 0, finder: 0 },
      hunger: 0,
      nextEvent: 0,
      queue: [],
      listen: 0,
      speaker: '',
      log: [],
      ended: false,
    };
  }

  function load() {
    try {
      const raw = localStorage.getItem(SAVE_KEY);
      if (!raw) return null;
      const data = JSON.parse(raw);
      const base = fresh();
      return {
        ...base,
        ...data,
        res: { ...base.res, ...data.res },
        jobs: { ...base.jobs, ...data.jobs },
        builds: { ...base.builds, ...data.builds },
      };
    } catch (e) {
      return null;
    }
  }

  function save() {
    if (resetting) return;
    try { localStorage.setItem(SAVE_KEY, JSON.stringify(s)); } catch (e) { /* storage unavailable */ }
  }

  // ================================================================
  // helpers
  // ================================================================

  const cap = () => 2 + 2 * s.builds.lean;
  const room = () => Math.max(0, cap() - s.pop);
  const working = () => Object.values(s.jobs).reduce((a, b) => a + b, 0);
  const idle = () => s.pop - working();
  const benchBoost = () => (s.builds.bench ? 1.5 : 1);

  function have(key) { return key === 'power' ? s.power : s.res[key]; }

  function can(cost) {
    return Object.entries(cost || {}).every(([k, v]) => have(k) >= v);
  }

  function pay(cost) {
    for (const [k, v] of Object.entries(cost || {})) {
      if (k === 'power') s.power -= v;
      else s.res[k] -= v;
    }
  }

  function gain(k, v) {
    s.res[k] += v;
    if (s.res[k] > 0) s.seen['res_' + k] = true;
  }

  function costText(cost) {
    return Object.entries(cost || {}).map(([k, v]) => `${v} ${k}`).join(', ');
  }

  function arrive(n) {
    const k = Math.min(n, room());
    s.pop += k;
    return k;
  }

  function loseSurvivor() {
    if (s.pop <= 0) return;
    if (idle() <= 0) {
      const busy = Object.keys(s.jobs).filter((j) => s.jobs[j] > 0);
      if (busy.length) s.jobs[pick(busy)]--;
    }
    s.pop--;
  }

  // ================================================================
  // log
  // ================================================================

  const MAX_LOG = 60;

  function log(text, cls) {
    s.log.unshift({ text, cls });
    if (s.log.length > MAX_LOG) s.log.pop();
    const el = document.createElement('div');
    el.textContent = text;
    if (cls) el.className = cls;
    const box = $('#log');
    box.prepend(el);
    while (box.children.length > MAX_LOG) box.lastChild.remove();
    fadeLog();
  }

  function renderLog() {
    const box = $('#log');
    box.innerHTML = '';
    for (const entry of s.log) {
      const el = document.createElement('div');
      el.textContent = entry.text;
      if (entry.cls) el.className = entry.cls;
      el.style.animation = 'none';
      box.append(el);
    }
    fadeLog();
  }

  function fadeLog() {
    [...$('#log').children].forEach((el, i) => {
      el.style.opacity = Math.max(0.12, 1 - i * 0.07);
    });
  }

  function phaseBanner(text) { log(text, 'phase'); }

  // ================================================================
  // sound (generated, no files)
  // ================================================================

  const Sound = {
    ctx: null,
    on: false,

    init() {
      const AC = window.AudioContext || window.webkitAudioContext;
      if (!AC) return;
      const ctx = new AC();
      const len = ctx.sampleRate * 2;
      const buf = ctx.createBuffer(1, len, ctx.sampleRate);
      const data = buf.getChannelData(0);
      for (let i = 0; i < len; i++) data[i] = Math.random() * 2 - 1;
      const src = ctx.createBufferSource();
      src.buffer = buf;
      src.loop = true;
      const band = ctx.createBiquadFilter();
      band.type = 'bandpass';
      band.frequency.value = 1700;
      band.Q.value = 0.5;
      this.noise = ctx.createGain();
      this.noise.gain.value = 0;
      src.connect(band).connect(this.noise).connect(ctx.destination);
      src.start();

      this.osc = ctx.createOscillator();
      this.osc.type = 'sine';
      this.tone = ctx.createGain();
      this.tone.gain.value = 0;
      this.osc.connect(this.tone).connect(ctx.destination);
      this.osc.start();
      this.ctx = ctx;
    },

    toggle() {
      if (!this.ctx) this.init();
      if (!this.ctx) return;
      this.on = !this.on;
      if (this.on) this.ctx.resume();
      $('#sound').textContent = 'sound: ' + (this.on ? 'on' : 'off');
      if (!this.on && 'speechSynthesis' in window) speechSynthesis.cancel();
    },

    update(r) {
      if (!this.ctx) return;
      const now = this.ctx.currentTime;
      let noise = 0;
      let tone = 0;
      if (this.on && r.powered) {
        noise = 0.05 * (1 - 0.85 * r.strength);
        if (r.st && r.strength > 0) {
          this.osc.frequency.setTargetAtTime(380 + ((r.st.freq * 37) % 300), now, 0.02);
          const beat = Math.floor(performance.now() / 150) % (r.lock ? 5 : 9) === 0;
          tone = beat ? 0.03 * r.strength : 0;
        }
      }
      this.noise.gain.setTargetAtTime(noise, now, 0.05);
      this.tone.gain.setTargetAtTime(tone, now, 0.01);
    },

    speak(text) {
      if (!this.on || !('speechSynthesis' in window)) return;
      const clean = text.replace(/\(.*?\)/g, '').trim();
      if (!clean) return;
      const u = new SpeechSynthesisUtterance(clean);
      u.rate = 0.7;
      u.pitch = 0.4;
      u.volume = 0.6;
      speechSynthesis.speak(u);
    },
  };

  // ================================================================
  // stations
  // ================================================================

  const STATIONS = [
    {
      id: 'numbers',
      freq: 94.3,
      antenna: 1,
      speak: true,
      avail: () => s.antenna < 3,
      lines: [
        '...seven...',
        'seven. four. one. nine.',
        'seven. four. one. nine. the light. the child. the soldier.',
        'seven. four. one. nine. answer them.',
        '(the voice is calm, and patient, and somehow familiar.)',
      ],
      done() {
        s.seen.repair = true;
        log('outside, the aerial hangs snapped against the wall. with a few parts, it could be spliced.');
      },
    },
    {
      id: 'numbers2',
      freq: 94.3,
      antenna: 3,
      speak: true,
      avail: () => s.antenna >= 3,
      lines: [
        'seven. four. one. nine.',
        'seven. four. one. nine. do not trust the soldier.',
        () => (s.flags.pipRevealed
          ? 'you told the child where you are. it followed her.'
          : 'keep the child where she is.'),
        'the light must stay lit. whatever it costs.',
        'you have heard this before. you will say it again.',
        'this is— (the voice says your name. the static swallows it.)',
      ],
      done() {
        s.seen.finder = true;
        log('the numbers are not coming from far away. with a direction finder, you could learn how close.');
      },
    },
    {
      id: 'song',
      freq: 99.1,
      antenna: 1,
      lines: [
        '♪ ...come home, come home, the kettle\'s on... ♪',
        '♪ ...the road is long but the light stays on... ♪',
        '(the song ends. a breath of silence. it starts again.)',
      ],
      done() {
        log('the same song, over and over. nobody ever introduces it.');
      },
    },
    {
      id: 'keeper',
      freq: 101.7,
      antenna: 2,
      lines: [
        '—anyone. is anyone out there. this is the light at saltmarsh point.',
        'the lamp still turns. i don\'t know who i keep it burning for.',
        'i have fish. salt fish, more than i can eat. what i don\'t have is fuel.',
        'if you can hear me— you can\'t, can you. nobody can.',
      ],
    },
    {
      id: 'pip',
      freq: 88.9,
      antenna: 2,
      lines: [
        'hello? hello. mum said not to touch the radio.',
        'she went to get batteries. that was eleven days ago.',
        'there\'s a man outside. by the fence. he doesn\'t move.',
        'if you\'re real, please say something.',
      ],
    },
    {
      id: 'hale',
      freq: 105.2,
      antenna: 3,
      lines: [
        'any station, any station, this is sergeant hale, relay company.',
        'we have civilians. we have a dead truck. we need shelter.',
        'if you have a transmitter, respond on this frequency.',
      ],
    },
  ];

  const station = (id) => STATIONS.find((st) => st.id === id);
  const prog = (id) => (s.stations[id] ||= { found: false, line: 0, loop: 0, done: false });
  const lineText = (st, i) => {
    const l = st.lines[i];
    return typeof l === 'function' ? l() : l;
  };
  const heard = (id) => !!(s.stations[id] && s.stations[id].done);

  // What the radio is picking up at the current frequency.
  function radioState() {
    const r = { powered: s.seen.radio && s.power > 0, st: null, strength: 0, lock: false, clear: false, faint: false };
    if (!s.seen.radio) return r;
    let best = null;
    let bd = Infinity;
    for (const st of STATIONS) {
      if (st.avail && !st.avail()) continue;
      if (s.antenna < st.antenna - 1) continue;
      const d = Math.abs(s.freq - st.freq);
      if (d < bd) { bd = d; best = st; }
    }
    if (!best || bd >= 0.6 || !r.powered) return r;
    r.st = best;
    const strength = 1 - bd / 0.6;
    if (s.antenna >= best.antenna) {
      r.strength = strength;
      r.lock = bd <= 0.25;
      r.clear = bd < 0.05;
    } else {
      r.faint = true;
      r.strength = strength * 0.3;
    }
    return r;
  }

  function garble(text, amount) {
    const noise = '·~-.:';
    return [...text].map((ch) => (ch !== ' ' && Math.random() < amount ? pick(noise) : ch)).join('');
  }

  function staticText() {
    const bits = ['ssss', 'hhh', '~', 'kkt', 'shhh', '· ·', 'zz', '…'];
    return Array.from({ length: 7 }, () => pick(bits)).join(' ');
  }

  function listen(r) {
    if (!r.powered || !r.st || !r.lock) { s.listen = 0; return; }
    const st = r.st;
    const p = prog(st.id);
    if (!p.found) {
      p.found = true;
      log(`a voice, buried in the static. ${fmt(st.freq)}.`);
    }
    if (!r.clear) { s.listen = 0; return; }
    if (s.listen === 0) s.listen = 2;
    s.listen++;
    if (s.listen < 4) return;
    s.listen = 0;

    if (p.line < st.lines.length) {
      const text = lineText(st, p.line);
      s.speaker = text;
      log(`${fmt(st.freq)} — "${text}"`, 'voice');
      if (st.speak) Sound.speak(text);
      p.line++;
      if (p.line >= st.lines.length && !p.done) {
        p.done = true;
        if (st.done) st.done();
      }
    } else {
      p.loop = (p.loop + 1) % st.lines.length;
      s.speaker = lineText(st, p.loop);
    }
  }

  // ================================================================
  // contacts & dialogue
  // ================================================================

  const CONTACTS = {
    keeper: { name: 'the keeper', start: 'k1' },
    pip: { name: 'pip', start: 'p1' },
    hale: { name: 'sergeant hale', start: 'h1' },
  };

  const contact = (id) => (s.contacts[id] ||= { node: CONTACTS[id].start, trust: 0, wait: 0, n: 0 });

  const PIP_TALK = [
    'the man moved today. only a little. closer.',
    'i counted the stars. there were fewer than yesterday.',
    'i made a calendar on the wall. it\'s mostly crosses.',
    'i sing the song from the radio. the one about the kettle. it helps.',
  ];

  const NODES = {
    // ---------- the keeper ----------
    k1: {
      say: [
        'you\'re real. god. it\'s been months since anyone answered.',
        'i have fish. more than i can eat. fuel\'s what i\'m short of. the lamp drinks it.',
      ],
      choices: [
        { label: 'ask why the lamp matters', go: 'k_why' },
        { label: 'offer to trade', go: 'k_trade', fx: (c) => { c.trust++; } },
      ],
    },
    k_why: {
      say: [
        'ships used to need it. there are no ships now.',
        'but something out on the water stays away from the light. so i keep it lit.',
      ],
      choices: [
        { label: 'offer to trade', go: 'k_trade', fx: (c) => { c.trust++; } },
      ],
    },
    k_trade: {
      redirect: (c) => {
        if (c.trust >= 3 && !s.flags.keeperBoat) return 'k_boat';
        if (c.trust >= 6 && !s.flags.keeperSecret) return 'k_secret';
        return null;
      },
      say: ['the lamp\'s low. fuel for fish, same as before?'],
      choices: [
        {
          label: 'send 5 fuel for fish',
          cost: { fuel: 5 },
          wait: 40,
          fx: (c) => {
            gain('food', 12);
            c.trust++;
            log('a crate of salt fish comes up the coast road on a sled. no one is pulling it.');
          },
        },
        { label: 'sign off' },
      ],
    },
    k_boat: {
      say: [
        'a boat washed in last night. two people in it, half frozen.',
        'i can\'t feed them and keep the lamp lit. can i send them to you?',
      ],
      choices: [
        {
          label: 'send them to me',
          need: () => room() >= 1,
          needText: 'no room',
          go: 'k_trade',
          fx: (c) => {
            s.flags.keeperBoat = true;
            c.trust += 2;
            const k = arrive(2);
            log(k === 2
              ? 'two strangers arrive at dusk, salt in their hair. they say the keeper told them to follow the static.'
              : 'one stranger arrives at dusk. the other didn\'t make the walk.');
          },
        },
        {
          label: 'we have no room',
          fx: (c) => {
            s.flags.keeperBoat = true;
            s.flags.refusedBoat = true;
            c.trust -= 2;
            log('the keeper is quiet for a long time. "understood."', 'voice');
          },
        },
      ],
    },
    k_secret: {
      say: [
        'i should tell you something. the numbers on 94.3.',
        'they started the night the lamp first went out. when the light\'s on, they\'re quieter.',
      ],
      choices: [
        { label: 'thank him', go: 'k_trade', fx: () => { s.flags.keeperSecret = true; } },
      ],
    },

    // ---------- pip ----------
    p1: {
      say: [
        'you answered! you\'re really really real.',
        'mum went to get batteries. that was eleven days ago. no— twelve.',
        'the man by the fence still hasn\'t moved. he\'s looking at my window.',
      ],
      choices: [
        { label: 'tell her to stay hidden', go: 'p_stay' },
        { label: 'tell her to come to you', go: 'p_come' },
      ],
    },
    p_come: {
      say: [
        'where are you? i can walk. i\'m good at walking.',
        'the man won\'t see. he never blinks, but he doesn\'t see.',
      ],
      choices: [
        {
          label: 'give her directions',
          fx: (c) => {
            s.flags.pipRevealed = true;
            s.flags.pipArriveAt = s.t + 90;
            c.node = 'p_road';
            log('pip: "ok. i\'m leaving now. i\'ll follow the road. don\'t stop talking."', 'voice');
          },
        },
        { label: 'no. stay where you are.', go: 'p_stay' },
      ],
    },
    p_road: {
      say: ['i\'m on the road. it\'s cold. my feet are loud in the snow.', 'something is walking when i walk.'],
      choices: [{ label: 'keep going, pip' }],
    },
    p_stay: {
      say: [
        'ok. i\'ll stay under the stairs. i have crackers.',
        'will you keep talking to me? when it\'s dark?',
      ],
      choices: [
        { label: 'promise', go: 'p_talk', fx: (c) => { s.flags.pipPromise = true; c.trust++; } },
      ],
    },
    p_talk: {
      redirect: (c) => (c.n >= 3 && !s.flags.pipNumbers ? 'p_numbers' : null),
      say: (c) => [PIP_TALK[c.n % PIP_TALK.length]],
      choices: [
        { label: 'keep her company', cost: { power: 5 }, wait: 45, fx: (c) => { c.n++; c.trust++; } },
        {
          label: 'leave her food at the crossroads',
          cost: { food: 5 },
          wait: 45,
          fx: (c) => {
            c.n++;
            c.trust += 2;
            s.flags.pipFed = true;
            log('you leave a parcel at the crossroads. the next morning it is gone. pip says thank you.');
          },
        },
        { label: 'sign off' },
      ],
    },
    p_numbers: {
      say: [
        'can i ask you something?',
        'yesterday i heard you on the radio. before you ever answered me.',
        'you were saying numbers. seven four one nine. over and over. why?',
      ],
      choices: [
        { label: '"that wasn\'t me."', go: 'p_talk', fx: () => { s.flags.pipNumbers = true; } },
        { label: '"i don\'t know."', go: 'p_talk', fx: () => { s.flags.pipNumbers = true; } },
      ],
    },

    // ---------- sergeant hale ----------
    h1: {
      say: [
        'station, this is hale. good to hear a voice that isn\'t mine.',
        'i\'ve got civilians and a dead truck. you\'ve got walls. i propose an arrangement.',
      ],
      choices: [
        { label: 'offer shelter', go: 'h_deal', fx: (c) => { c.trust++; } },
        { label: 'ask what he wants in return', go: 'h_want' },
      ],
    },
    h_want: {
      say: [
        'fuel, mostly. my people can strip anything for parts if they can keep warm.',
        'and you take in whoever can\'t keep up with us.',
      ],
      choices: [
        { label: 'agree', go: 'h_deal' },
        {
          label: 'refuse',
          fx: (c) => {
            s.flags.refusedHale = true;
            c.node = 'h_cold';
            log('hale: "your call, station. we\'ll be on 105.2."', 'voice');
          },
        },
      ],
    },
    h_cold: {
      say: ['the offer stands, station.'],
      choices: [
        { label: 'accept the arrangement', go: 'h_deal' },
        { label: 'sign off' },
      ],
    },
    h_deal: {
      redirect: (c) => (c.n >= 2 && !s.flags.haleAsked ? 'h_ask' : null),
      say: ['hale here. what do you need?'],
      choices: [
        {
          label: 'trade 6 fuel for parts',
          cost: { fuel: 6 },
          wait: 30,
          fx: () => {
            s.flags.haleDealt = true;
            gain('parts', 5);
            log('a crate of salvaged parts is left at the treeline. boot prints lead away in neat rows.');
          },
        },
        {
          label: 'take in refugees',
          need: () => room() >= 1,
          needText: 'no room',
          wait: 60,
          fx: (c) => {
            s.flags.haleDealt = true;
            c.n++;
            const k = arrive(3);
            log(`${k === 1 ? 'one figure arrives' : k + ' figures arrive'} in the snow, escorted to the edge of the trees. the soldiers do not come closer.`);
          },
        },
        { label: 'sign off' },
      ],
    },
    h_ask: {
      say: [
        'one more thing. 94.3. the numbers.',
        'we\'ve been logging that signal for months. tell me what you\'ve heard. all of it.',
      ],
      choices: [
        {
          label: 'tell him everything',
          go: 'h_deal',
          fx: (c) => {
            s.flags.haleAsked = true;
            s.flags.toldHale = true;
            c.trust += 2;
            log('hale: "...seven four one nine. thank you, station. that\'s very helpful."', 'voice');
          },
        },
        {
          label: 'lie: "only static"',
          go: 'h_deal',
          fx: () => {
            s.flags.haleAsked = true;
            s.flags.liedHale = true;
            log('hale: "understood." he does not sound like he believes you.', 'voice');
          },
        },
      ],
    },
  };

  const CALL_COST = { power: 4 };

  function contactAvailable(id) {
    if (s.phase < 2) return false;
    return heard(id);
  }

  function resolveNode(c, id) {
    for (let i = 0; i < 5; i++) {
      const node = NODES[id];
      const next = node.redirect && node.redirect(c);
      if (!next) return id;
      id = next;
    }
    return id;
  }

  function enterNode(who, id) {
    const c = contact(who);
    id = resolveNode(c, id);
    c.node = id;
    const node = NODES[id];
    const lines = typeof node.say === 'function' ? node.say(c) : node.say;
    const name = CONTACTS[who].name;
    for (const line of lines) log(`${name}: "${line}"`, 'voice');
    s.talk = { who, node: id, lines };
  }

  function choicesFor() {
    if (!s.talk) return [];
    return NODES[s.talk.node].choices;
  }

  function call(who) {
    const c = contact(who);
    if (who === 'pip' && s.flags.pipArrived) return;
    if (c.wait > s.t) {
      log(`${fmt(station(who).freq)}: no answer. only the carrier tone.`);
      s.talk = null;
      return;
    }
    if (!can(CALL_COST)) return;
    pay(CALL_COST);
    enterNode(who, c.node);
  }

  function choose(i) {
    if (!s.talk) return;
    const who = s.talk.who;
    const c = contact(who);
    const ch = choicesFor()[i];
    if (!ch) return;
    if (ch.need && !ch.need()) return;
    if (!can(ch.cost)) return;
    pay(ch.cost);
    log(`you: ${ch.label}`, 'you');
    if (ch.wait) c.wait = s.t + ch.wait;
    if (ch.fx) ch.fx(c);
    if (ch.go) enterNode(who, ch.go);
    else s.talk = null;
    render();
  }

  // ================================================================
  // actions (buttons with cooldowns)
  // ================================================================

  const LOOT = [
    { parts: 2, text: 'a toolbox under the cot. rusted, but the pliers still work.' },
    { food: 3, text: 'three tins of beans. the labels are long gone.' },
    { parts: 1, text: 'a coil of copper wire behind the stove.' },
    { text: 'a notebook. the handwriting is yours. you don\'t remember writing it. one page, pressed so hard it tore: 101.7' },
    { fuel: 2, text: 'a half-full can of fuel.' },
    { parts: 2, text: 'an old television. you gut it for parts.' },
    { parts: 1, text: 'a box of fuses.' },
    { food: 3, text: 'dried apples in a jar.' },
    { parts: 2, text: 'a car battery. dead, but the terminals are good.' },
    { fuel: 2, text: 'kindling, stacked neatly by the door. you don\'t remember stacking it.' },
    { parts: 2, text: 'a broken lamp and a broken clock. both have their uses.' },
    { parts: 1, text: 'loose screws in a coffee tin.' },
    { food: 2, text: 'a bag of rice. the mice got to some of it.' },
  ];

  const ACTIONS = [
    {
      id: 'crank',
      panel: 'shack',
      label: 'crank the generator',
      cd: 3,
      show: () => true,
      run() {
        s.power = clamp(s.power + 12, 0, 100);
        if (!s.flags.cranked) {
          s.flags.cranked = true;
          log('the handle is stiff. the generator coughs, then whines.');
        }
      },
    },
    {
      id: 'feed',
      panel: 'shack',
      label: 'feed the generator',
      cost: { fuel: 1 },
      cd: 1,
      show: () => s.seen.res_fuel,
      run() { s.power = clamp(s.power + 30, 0, 100); },
    },
    {
      id: 'search',
      panel: 'shack',
      label: 'search the shack',
      cd: 4,
      show: () => s.seen.search && s.loot < LOOT.length,
      run() {
        const item = LOOT[s.loot++];
        for (const k of ['parts', 'fuel', 'food']) if (item[k]) gain(k, item[k]);
        s.seen.stores = true;
        log(item.text);
        if (s.loot >= LOOT.length) log('there is nothing left in the shack but dust.');
      },
    },
    {
      id: 'gather',
      panel: 'shack',
      label: 'gather wood',
      cd: 6,
      show: () => s.seen.outside,
      run() {
        const n = rand(1, 3);
        gain('fuel', n);
        if (Math.random() < 0.2) {
          gain('parts', 1);
          log(`${n} armfuls of deadwood, and a rusted hinge from a fallen fence.`);
        } else {
          log(pick([
            `${n} armfuls of deadwood. the trees creak, though there is no wind.`,
            `${n} armfuls of wood. the snow is grey, and very quiet.`,
            `${n} armfuls of wood. there are footprints by the woodpile that aren't yours.`,
          ]));
        }
      },
    },
    {
      id: 'repair',
      panel: 'shack',
      label: 'splice the aerial',
      cost: { parts: 4 },
      show: () => s.seen.repair && s.antenna < 2,
      run() {
        s.antenna = 2;
        log('you splice the wire and lash the aerial back to the roof. the static deepens. there are more voices out there now.');
        log('for a moment, near the bottom of the dial, you think you hear a child.');
      },
    },
    {
      id: 'transmitter',
      panel: 'shack',
      label: 'build a transmitter',
      cost: { parts: 6, fuel: 4 },
      show: () => s.seen.transmitter && s.phase === 1,
      run: startPhase2,
    },
    {
      id: 'bearing',
      panel: 'shack',
      label: 'take a bearing on 94.3',
      cost: { power: 30 },
      show: () => s.builds.finder && !s.flags.bearingStarted,
      run() {
        s.flags.bearingStarted = true;
        log('the direction finder whirs. its needle swings east. then west.');
        s.queue.push(
          { at: s.t + 3, text: 'then it spins, slowly, as if it\'s looking for something.' },
          { at: s.t + 6, text: 'it stops. it points down.' },
          { at: s.t + 9, text: 'at the floor of your own shack.' },
          { at: s.t + 12, text: 'beneath the boards, faintly, you can hear it: seven. four. one. nine.', cls: 'voice', flag: 'bearing' },
        );
      },
    },
    {
      id: 'floor',
      panel: 'shack',
      label: 'pry up the floorboards',
      show: () => s.flags.bearing && !s.ended,
      run: ending,
    },

    // ---------- builds ----------
    {
      id: 'lean',
      panel: 'build',
      label: () => `lean-to (${s.builds.lean})`,
      cost: () => ({ parts: 2 + s.builds.lean, fuel: 4 + 2 * s.builds.lean }),
      show: () => s.phase >= 2 && s.builds.lean < 8,
      run() {
        s.builds.lean++;
        log(s.builds.lean === 1
          ? 'a lean-to against the shack wall. room for two more, if they don\'t mind the cold.'
          : 'another lean-to. the camp is starting to look like a place.');
      },
    },
    {
      id: 'bench',
      panel: 'build',
      label: 'workbench',
      cost: { parts: 5, fuel: 2 },
      show: () => s.phase >= 2 && !s.builds.bench,
      run() {
        s.builds.bench = 1;
        log('a workbench, made from the door of the outhouse. everyone works faster with proper tools.');
      },
    },
    {
      id: 'mast',
      panel: 'build',
      label: 'radio mast',
      cost: { parts: 10, fuel: 8 },
      show: () => s.phase >= 2 && s.builds.bench && !s.builds.mast,
      run() {
        s.builds.mast = 1;
        s.antenna = 3;
        log('the mast goes up above the treeline. the whole dial opens up: far voices, near voices.');
        log('94.3 sounds different now. closer.');
      },
    },
    {
      id: 'finder',
      panel: 'build',
      label: 'direction finder',
      cost: { parts: 12, fuel: 6 },
      show: () => s.seen.finder && !s.builds.finder,
      run() {
        s.builds.finder = 1;
        log('the direction finder sits on the table, needle trembling. it only needs power, and a frequency.');
      },
    },
  ];

  const val = (v) => (typeof v === 'function' ? v() : v);
  const cooldowns = {};

  function buildButtons() {
    for (const a of ACTIONS) {
      const b = document.createElement('button');
      b.className = 'act hidden';
      b.innerHTML = '<span class="fill"></span><span class="label"></span><span class="cost"></span>';
      b.addEventListener('click', () => doAction(a));
      $('#btns-' + a.panel).append(b);
      a.el = b;
    }
  }

  function doAction(a) {
    const now = performance.now();
    if (cooldowns[a.id] && cooldowns[a.id].end > now) return;
    const cost = val(a.cost);
    if (!can(cost)) return;
    pay(cost);
    if (a.cd) cooldowns[a.id] = { start: now, end: now + a.cd * 1000 * CD_SCALE };
    a.run();
    render();
  }

  function updateButtons() {
    const now = performance.now();
    for (const a of ACTIONS) {
      const visible = !!a.show();
      a.el.classList.toggle('hidden', !visible);
      if (!visible) continue;
      const cost = val(a.cost);
      const c = cooldowns[a.id];
      const cooling = c && c.end > now;
      a.el.disabled = cooling || !can(cost);
      a.el.querySelector('.label').textContent = val(a.label);
      a.el.querySelector('.cost').textContent = cost ? costText(cost) : '';
      a.el.querySelector('.fill').style.width = cooling ? `${((c.end - now) / (c.end - c.start)) * 100}%` : '0';
    }
  }

  // ================================================================
  // camp
  // ================================================================

  const JOBS = [
    { id: 'woodcutter', name: 'woodcutter', desc: '+fuel' },
    { id: 'forager', name: 'forager', desc: '+food. digs under the snow for roots and traps rabbits.' },
    { id: 'scavenger', name: 'scavenger', desc: '+parts. strips the empty houses down the road.' },
    { id: 'cranker', name: 'generator hand', desc: 'keeps the generator turning.' },
  ];

  function changeJob(id, d) {
    if (d > 0 && idle() <= 0) return;
    if (d < 0 && s.jobs[id] <= 0) return;
    s.jobs[id] += d;
    render();
  }

  function economy() {
    if (s.phase < 2) return;
    const boost = benchBoost();
    gain('fuel', 0.2 * s.jobs.woodcutter * boost);
    gain('food', 0.3 * s.jobs.forager * boost);
    gain('parts', 0.05 * s.jobs.scavenger * boost);
    s.res.food -= 0.1 * s.pop;
    if (s.res.food < 0) {
      s.res.food = 0;
      if (++s.hunger >= 20) {
        s.hunger = 0;
        loseSurvivor();
        log('someone walks out into the dark without a word. they do not come back. there was not enough food.', 'bad');
      }
    } else {
      s.hunger = 0;
    }
  }

  // ================================================================
  // story
  // ================================================================

  function startPhase2() {
    s.phase = 2;
    s.seen.contacts = true;
    s.seen.camp = true;
    s.nextEvent = s.t + 90;
    log('the microphone crackles. somewhere out there, they can hear you now.');
    phaseBanner('— II. the voices —');
    log('the shack has room for two more, if anyone comes.');
  }

  function story() {
    if (!s.seen.radio && s.power >= 25) {
      s.seen.radio = true;
      s.flags.radioAt = s.t;
      log('the radio hums. static fills the room.');
      log('the dial turns. somewhere in the noise, something might be talking.');
    }

    const anyFound = Object.values(s.stations).some((p) => p.found);
    if (s.seen.radio && !s.seen.search && (anyFound || s.t - s.flags.radioAt >= 40)) {
      s.seen.search = true;
      log('the shack is cluttered. there might be something useful in here.');
    }

    if (!s.seen.outside && s.loot >= 3) {
      s.seen.outside = true;
      log('outside, the snow is grey and the trees are very close. there is deadwood under them.');
    }

    if (!s.seen.transmitter && heard('keeper') && heard('pip')) {
      s.seen.transmitter = true;
      log('they can\'t hear you. this radio only listens. with enough parts, you could make it speak.');
    }

    if (s.flags.pipArriveAt && !s.flags.pipArrived && s.t >= s.flags.pipArriveAt) {
      s.flags.pipArrived = true;
      s.flags.watcher = true;
      s.pop++;
      if (s.talk && s.talk.who === 'pip') s.talk = null;
      log('a knock. a small girl in a too-big coat. "i followed the road," says pip.');
      log('behind her, at the treeline, a tall shape stands very still.', 'bad');
    }

    while (s.queue.length && s.queue[0].at <= s.t) {
      const q = s.queue.shift();
      log(q.text, q.cls);
      if (q.flag) s.flags[q.flag] = true;
    }
  }

  const EVENTS = [
    {
      can: () => room() > 0,
      weight: 3,
      run() {
        arrive(1);
        log(pick([
          'a stranger at the door, snow to the knees. they followed your broadcast.',
          'someone is sitting by the woodpile in the morning. they say they heard a voice on the radio telling them to come.',
          'a woman with a dog that won\'t bark. she says the static led her here.',
        ]));
      },
    },
    {
      can: () => true,
      weight: 1,
      run() {
        s.power = Math.max(0, s.power - 30);
        s.res.fuel = Math.max(0, s.res.fuel - 3);
        log('a storm rolls over the ridge. the wind gets into everything. the generator stutters.', 'bad');
      },
    },
    {
      can: () => !s.flags.cassette && s.pop >= 2,
      weight: 2,
      run() {
        s.flags.cassette = true;
        log('someone finds a cassette tape half-buried in the snow. on the label, in your handwriting: DON\'T ANSWER 94.3.');
      },
    },
    {
      can: () => s.flags.watcher && !s.flags.watcherGone,
      weight: 3,
      run() {
        s.flags.watcherGone = true;
        s.res.food = Math.max(0, s.res.food - 6);
        log('in the morning the shape at the treeline is gone. so is some of the food. nobody heard a thing.', 'bad');
      },
    },
    {
      can: () => !s.flags.silence,
      weight: 1,
      run() {
        s.flags.silence = true;
        log('for one long minute every frequency goes silent. not even static. then it all comes back.');
      },
    },
    {
      can: () => s.pop >= 3 && !s.flags.dream,
      weight: 2,
      run() {
        s.flags.dream = true;
        log('one of the survivors wakes up shouting numbers. they don\'t remember the dream.');
      },
    },
  ];

  function events() {
    if (s.phase < 2 || s.ended || s.t < s.nextEvent) return;
    s.nextEvent = s.t + rand(60, 120);
    const pool = [];
    for (const e of EVENTS) if (e.can()) for (let i = 0; i < e.weight; i++) pool.push(e);
    if (pool.length) pick(pool).run();
  }

  // ================================================================
  // ending of phase II
  // ================================================================

  function summary() {
    const lines = [];
    const k = s.contacts.keeper;
    if (!k) lines.push('you never answered the keeper.');
    else if (s.flags.refusedBoat) lines.push('you turned away the keeper\'s boat. the lamp still burns, for now.');
    else if (k.trust >= 4) lines.push('the keeper trusts you. the light at saltmarsh point stays lit.');
    else lines.push('the keeper is still waiting for your call.');

    if (s.flags.pipArrived) lines.push('pip sleeps by the radio. the tall shape is never far from the treeline.');
    else if (s.flags.pipRevealed) lines.push('pip is somewhere on the road.');
    else if (s.flags.pipPromise) lines.push('pip is hiding under the stairs, listening for your voice.');
    else lines.push('you left pip alone with the man by the fence.');

    if (!s.contacts.hale) lines.push('sergeant hale never heard from you.');
    else if (s.flags.toldHale) lines.push('hale knows everything you heard. he was very interested.');
    else if (s.flags.liedHale) lines.push('you lied to hale. he knows.');
    else if (s.flags.refusedHale && !s.flags.haleDealt) lines.push('you turned hale away.');
    else lines.push('hale is still on 105.2, counting.');

    lines.push(`${s.pop} ${s.pop === 1 ? 'person lives' : 'people live'} in your camp.`);
    return lines;
  }

  function ending() {
    s.ended = true;
    log('under the boards: a radio. identical to yours. still warm.');
    log('the dial reads 94.3. scratched into the microphone, in your handwriting: 7419.', 'voice');
    phaseBanner('— end of II —');
    showEnding();
    save();
  }

  function showEnding() {
    const card = $('#ending-card');
    card.innerHTML = `
      <h2>— II. the voices —</h2>
      <p>under the floorboards there is a radio, identical to yours. it is still warm.</p>
      <p>the dial reads 94.3. scratched into the microphone, in your handwriting: <b>7419</b>.</p>
      <ul>${summary().map((l) => `<li>${l}</li>`).join('')}</ul>
      <p class="dim">the signal remembers what you chose.</p>
      <p>III. the network — coming soon.</p>
      <div class="btns">
        <button id="keep">keep listening</button>
        <button id="again">start over</button>
      </div>`;
    $('#ending').classList.remove('hidden');
    $('#keep').addEventListener('click', () => $('#ending').classList.add('hidden'));
    $('#again').addEventListener('click', restart);
  }

  // ================================================================
  // rendering
  // ================================================================

  const lastHtml = {};
  function setHtml(id, html) {
    if (lastHtml[id] === html) return;
    lastHtml[id] = html;
    $('#' + id).innerHTML = html;
  }

  function bar(n, total) {
    return '▮'.repeat(n) + '▯'.repeat(total - n);
  }

  function renderRadio() {
    const r = radioState();
    $('#freq').textContent = fmt(s.freq);
    $('#dial').value = s.freq;
    $('#meter').textContent = r.powered ? bar(Math.round(r.strength * 5), 5) : '- - - - -';

    const pb = $('#power-bar');
    pb.textContent = bar(Math.ceil(s.power / 10), 10);
    pb.classList.toggle('low', s.power < 20);

    const sp = $('#speaker');
    sp.classList.toggle('lock', r.lock);
    sp.classList.toggle('clear', r.clear);
    if (!r.powered) {
      sp.textContent = '— the radio is dead. it needs power. —';
    } else if (r.faint) {
      sp.textContent = 'something faint is out there. the aerial can\'t hold it.';
    } else if (r.lock) {
      const p = prog(r.st.id);
      const i = p.line > 0 ? (p.line < r.st.lines.length ? p.line - 1 : p.loop) : 0;
      const text = r.clear && s.speaker ? s.speaker : lineText(r.st, i);
      sp.textContent = r.clear ? text : garble(text, clamp((1 - r.strength) * 1.6, 0, 0.85));
    } else if (r.st && r.strength > 0) {
      sp.textContent = garble(staticText(), 0.3) + '  ~ a voice? ~';
    } else {
      sp.textContent = staticText();
    }
    return r;
  }

  function renderStores() {
    const rows = ['fuel', 'parts', 'food']
      .filter((k) => s.seen['res_' + k])
      .map((k) => `<div class="row"><span>${k}</span><span>${Math.floor(s.res[k])}</span></div>`);
    setHtml('stores', rows.join(''));
  }

  function renderCamp() {
    let html = `<div class="row"><span>survivors</span><span>${s.pop} / ${cap()}</span></div>`;
    html += `<div class="row dim"><span>idle</span><span>${idle()}</span></div>`;
    for (const j of JOBS) {
      const n = s.jobs[j.id];
      html += `<div class="row job"><span>${j.name}</span><span class="ctl">
        <button data-job="${j.id}" data-d="-1" ${n > 0 ? '' : 'disabled'} aria-label="fewer ${j.name}s">−</button>
        <b>${n}</b>
        <button data-job="${j.id}" data-d="1" ${idle() > 0 ? '' : 'disabled'} aria-label="more ${j.name}s">+</button>
      </span></div><div class="desc">${j.desc}</div>`;
    }
    html += `<div class="desc">each survivor eats.${s.builds.bench ? ' the workbench makes everyone 50% faster.' : ''}</div>`;
    if (s.pop > 0 && s.res.food < 3) html += '<div class="warn">food is running out.</div>';
    setHtml('camp', html);
  }

  function renderContacts() {
    let html = '';
    const ids = Object.keys(CONTACTS).filter(contactAvailable);
    if (!ids.length) html += '<div class="dim">no one to call yet. keep listening.</div>';
    for (const id of ids) {
      const c = contact(id);
      const st = station(id);
      let btn;
      if (id === 'pip' && s.flags.pipArrived) {
        btn = '<span class="dim">here, by the radio</span>';
      } else {
        const quiet = c.wait > s.t;
        btn = `<button data-call="${id}" ${!quiet && !can(CALL_COST) ? 'disabled' : ''}>${quiet ? 'quiet…' : 'call · 4 power'}</button>`;
      }
      html += `<div class="contact"><span>${CONTACTS[id].name} <span class="dim">${fmt(st.freq)}</span></span>${btn}</div>`;
    }
    if (s.talk) {
      html += `<div class="convo"><div class="who">${CONTACTS[s.talk.who].name.toUpperCase()}</div>`;
      html += s.talk.lines.map((l) => `<p>"${l}"</p>`).join('');
      html += '<div class="choices">';
      choicesFor().forEach((ch, i) => {
        const blocked = ch.need && !ch.need();
        const ok = can(ch.cost) && !blocked;
        const extra = blocked ? ch.needText : (ch.cost ? costText(ch.cost) : '');
        html += `<button data-choice="${i}" ${ok ? '' : 'disabled'}>${ch.label}${extra ? ` <span class="dim">· ${extra}</span>` : ''}</button>`;
      });
      html += '</div></div>';
    }
    setHtml('contacts', html);
  }

  function render() {
    $('#p-radio').classList.toggle('hidden', !s.seen.radio);
    $('#p-stores').classList.toggle('hidden', !s.seen.stores);
    $('#p-contacts').classList.toggle('hidden', !s.seen.contacts);
    $('#p-camp').classList.toggle('hidden', !s.seen.camp);
    if (s.seen.radio) renderRadio();
    if (s.seen.stores) renderStores();
    if (s.seen.camp) renderCamp();
    if (s.seen.contacts) renderContacts();
    updateButtons();
  }

  // ================================================================
  // loop
  // ================================================================

  function tick() {
    s.t++;
    if (s.seen.radio) {
      const r = radioState();
      const drain = 0.2 + (r.lock ? 0.6 : 0);
      s.power = clamp(s.power - drain + 0.8 * s.jobs.cranker, 0, 100);
      if (s.power === 0 && !s.flags.deadWarned) {
        s.flags.deadWarned = true;
        log('the radio dies with a click. the generator needs turning.');
      }
      if (s.power > 20) s.flags.deadWarned = false;
      listen(radioState());
    }
    economy();
    story();
    events();
    if (s.t % 5 === 0) save();
    render();
  }

  function frame() {
    updateButtons();
    if (s.seen.radio) Sound.update(radioState());
    requestAnimationFrame(frame);
  }

  function tune(f) {
    s.freq = clamp(round1(f), 87.5, 108);
    s.listen = 0;
    s.speaker = '';
    render();
  }

  function restart() {
    if (!confirm('start over? everything will be forgotten.')) return;
    resetting = true;
    try { localStorage.removeItem(SAVE_KEY); } catch (e) { /* ignore */ }
    location.reload();
  }

  function init() {
    s = load();
    const isNew = !s;
    if (isNew) s = fresh();

    buildButtons();
    renderLog();

    if (isNew) {
      phaseBanner('— I. the shack —');
      log('the room is cold. it is dark.');
      log('a radio sits on the table, silent. in the corner, a hand-crank generator.');
    }

    $('#dial').addEventListener('input', (e) => tune(parseFloat(e.target.value)));
    document.querySelectorAll('[data-tune]').forEach((b) => {
      b.addEventListener('click', () => tune(s.freq + parseFloat(b.dataset.tune)));
    });
    document.addEventListener('keydown', (e) => {
      if (!s.seen.radio || e.target.tagName === 'INPUT') return;
      if (e.key === 'ArrowLeft') tune(s.freq - 0.1);
      if (e.key === 'ArrowRight') tune(s.freq + 0.1);
    });
    $('#contacts').addEventListener('click', (e) => {
      const b = e.target.closest('button');
      if (!b) return;
      if (b.dataset.call) { call(b.dataset.call); render(); }
      if (b.dataset.choice) choose(Number(b.dataset.choice));
    });
    $('#camp').addEventListener('click', (e) => {
      const b = e.target.closest('button[data-job]');
      if (b) changeJob(b.dataset.job, Number(b.dataset.d));
    });
    $('#sound').addEventListener('click', () => Sound.toggle());
    $('#restart').addEventListener('click', restart);
    window.addEventListener('beforeunload', save);

    render();
    setInterval(tick, TICK_MS);
    requestAnimationFrame(frame);

    // for debugging in the console
    window.signal = { get state() { return s; }, tick, render };
  }

  init();
})();
