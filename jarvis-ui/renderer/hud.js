// jarvis-ui/renderer/hud.js — connects to jarvis-core, drives the HUD.
(() => {
  const $ = (id) => document.getElementById(id);
  const body = document.body;
  const els = {
    clock: $('clock'), conn: $('conn'), connDot: $('conn').querySelector('.dot'),
    connTxt: $('connTxt'), cpuBar: $('cpuBar'), cpuVal: $('cpuVal'),
    memBar: $('memBar'), memVal: $('memVal'), uptime: $('uptime'),
    procs: $('procs'), netUp: $('netUp'), netDown: $('netDown'),
    state: $('state'), hint: $('hint'), notes: $('notes'),
    plugins: $('plugins'), mic: $('mic'), micTxt: $('micTxt'),
    transcript: $('transcript'), input: $('textInput'),
    wavePath: $('wavePath'),
  };

  // ---- clock ----
  setInterval(() => {
    els.clock.textContent = new Date().toLocaleTimeString('en-GB');
  }, 1000);

  // ---- state machine ----
  function setState(s, label) {
    body.dataset.state = s;
    els.state.textContent = (label || s).toUpperCase();
  }
  setState('standby', 'standby');

  // ---- waveform animation while listening/speaking ----
  let waveTimer = null;
  function startWave() {
    if (waveTimer) return;
    waveTimer = setInterval(() => {
      const pts = [];
      for (let x = 0; x <= 200; x += 8) {
        const y = 30 + Math.sin((x + Date.now() / 80) / 12) *
          (Math.random() * 18 + 4);
        pts.push(`${x},${y.toFixed(1)}`);
      }
      els.wavePath.setAttribute('points', pts.join(' '));
    }, 60);
  }
  function stopWave() { clearInterval(waveTimer); waveTimer = null; }

  // ---- notifications ----
  function notify(text) {
    const li = document.createElement('li');
    const t = new Date().toLocaleTimeString('en-GB');
    li.innerHTML = `${text}<time>${t}</time>`;
    els.notes.prepend(li);
    while (els.notes.children.length > 6) els.notes.lastChild.remove();
  }

  // ---- transcript ----
  function showLine(who, text) {
    const cls = who === 'user' ? 'you' : 'jarvis';
    const tag = who === 'user' ? 'YOU' : 'JARVIS';
    els.transcript.innerHTML = `<span class="${cls}">${tag} ▸</span> ${text}`;
  }

  // ---- plugins ----
  function renderPlugins(list) {
    els.plugins.innerHTML = '';
    (list || []).forEach((p) => {
      const li = document.createElement('li');
      const btn = document.createElement('button');
      btn.textContent = p.enabled ? 'ON' : 'OFF';
      btn.className = p.enabled ? 'on' : '';
      btn.onclick = () => send('plugin', {
        action: p.enabled ? 'disable' : 'enable', name: p.name,
      });
      li.append(Object.assign(document.createElement('span'),
        { textContent: p.name }), btn);
      els.plugins.appendChild(li);
    });
  }

  // ---- WebSocket to core ----
  let ws = null;
  function connect() {
    const url = (window.jarvis && window.jarvis.coreUrl())
      || 'ws://127.0.0.1:8765';
    ws = new WebSocket(url);
    ws.onopen = () => {
      els.connDot.className = 'dot dot--on';
      els.connTxt.textContent = 'core online';
      notify('Core link established');
    };
    ws.onclose = () => {
      els.connDot.className = 'dot dot--off';
      els.connTxt.textContent = 'reconnecting…';
      setState('standby', 'standby');
      setTimeout(connect, 1500);
    };
    ws.onmessage = (e) => {
      let m; try { m = JSON.parse(e.data); } catch { return; }
      handle(m.type, m.payload || {});
    };
  }

  function send(type, payload) {
    if (ws && ws.readyState === 1) {
      ws.send(JSON.stringify({ type, ts: Date.now() / 1000, payload }));
    }
  }

  function handle(type, p) {
    switch (type) {
      case 'hello':
        notify(`Profile loaded: ${p.user || 'operator'}`);
        send('plugin', { action: 'list' });
        break;
      case 'stat': {
        els.cpuBar.style.width = `${p.cpu}%`;
        els.cpuVal.textContent = `${p.cpu}%`;
        els.memBar.style.width = `${p.mem}%`;
        els.memVal.textContent = `${p.mem}%`;
        els.uptime.textContent = p.uptime;
        els.procs.textContent = p.procs;
        els.netUp.textContent = p.net_up;
        els.netDown.textContent = p.net_down;
        break;
      }
      case 'wake':
        setState('listening', 'listening');
        els.hint.textContent = 'I’m listening…';
        break;
      case 'listening':
        if (p.state) { setState('listening', 'listening'); els.micTxt.textContent = 'recording'; startWave(); }
        else { els.micTxt.textContent = 'idle'; }
        break;
      case 'transcript':
        showLine('user', p.text);
        break;
      case 'thinking':
        if (p.state) { setState('thinking', 'processing'); els.hint.textContent = 'Working on it…'; }
        break;
      case 'speaking':
        if (p.state) { setState('speaking', 'responding'); startWave(); }
        else { stopWave(); setState('standby', 'standby'); els.hint.textContent = 'Say “Jarvis” to wake me'; els.micTxt.textContent = 'idle'; }
        break;
      case 'reply':
        showLine('jarvis', p.text);
        break;
      case 'intent':
        notify(`Intent: ${p.name}`);
        break;
      case 'notify':
        notify(p.text);
        break;
      case 'interrupt':
        stopWave(); setState('standby', 'standby');
        break;
      case 'plugin':
        if (p.action === 'list') renderPlugins(p.plugins);
        else send('plugin', { action: 'list' });
        break;
    }
  }

  // ---- typed input ----
  els.input.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && els.input.value.trim()) {
      const text = els.input.value.trim();
      showLine('user', text);
      send('text', { text });
      els.input.value = '';
    }
  });

  // seed default plugins display until core responds
  renderPlugins([
    { name: 'weather', enabled: true },
    { name: 'calendar', enabled: false },
    { name: 'vision', enabled: true },
  ]);

  connect();
})();
