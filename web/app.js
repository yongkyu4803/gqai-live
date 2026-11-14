// GQAI Live page: microphone → Whisper (local) → Claude cleanup → (macOS app) paste into the front app.
//
// Flow
//   1. An AudioWorklet delivers mono frames. Speech is cut into segments at short pauses (max 20 s each),
//      resampled to 16 kHz and sent to /api/transcribe one at a time, in order.
//   2. Transcribed text accumulates in `org.pending`. When the speaker pauses for the chosen time and
//      Whisper has caught up, the pending text goes to /api/organize (Claude, streamed) and is appended.
//   3. On stop, the remaining audio and text are processed. In the macOS app with "insert" on, this
//      recording's cleaned text (or the raw text if cleanup failed) is sent to the app, which pastes it.
//
// Native bridge (see mac/ and docs/WINDOWS.md)
//   page → app : Native.post({type: 'state' | 'insert' | 'insertPermission', ...})
//   app → page : window.gqaiNative.toggle() / .inserted(message) / .insertPermission(ok)
'use strict';
const $ = id => document.getElementById(id);
const store = {get: k => { try { return localStorage.getItem(k) || ''; } catch { return ''; } },
               set: (k, v) => { try { localStorage.setItem(k, v); } catch {} }};

// macOS WKWebView exposes webkit.messageHandlers; Windows WebView2 exposes chrome.webview.
const Native = (() => {
  const wk = window.webkit?.messageHandlers?.gqai, wv = window.chrome?.webview;
  if (wk) return {post: m => wk.postMessage(m), shortcut: '⌥⇧R'};
  if (wv) return {post: m => wv.postMessage(m), shortcut: 'Ctrl+Alt+R'};
  return null;
})();

// ---------------- status chips ----------------
let claudeReady = false;
async function refreshStatus() {
  try {
    const st = await (await fetch('/api/status')).json();
    const w = $('whisperChip'), c = $('claudeChip');
    w.textContent = st.whisper.ready ? `Whisper · ${st.whisper.model}` : 'Whisper 없음';
    w.className = 'chip ' + (st.whisper.ready ? 'ok' : 'bad'); w.title = st.whisper.message || '';
    claudeReady = st.claude.loggedIn;
    c.textContent = claudeReady ? `Claude · ${st.claude.model}` : 'Claude 인증 필요';
    c.className = 'chip ' + (claudeReady ? 'ok' : 'bad'); c.title = st.claude.message || '';
  } catch { $('whisperChip').textContent = '서버 연결 안 됨'; $('whisperChip').className = 'chip bad'; }
}
refreshStatus();
window.addEventListener('focus', refreshStatus);

// ---------------- settings remembered per browser ----------------
for (const id of ['language', 'pause', 'outLang']) {
  if (store.get('gqai.' + id)) $(id).value = store.get('gqai.' + id);
  $(id).onchange = () => store.set('gqai.' + id, $(id).value);
}
$('orgOn').checked = store.get('gqai.orgOn') !== '0';
$('orgOn').onchange = () => store.set('gqai.orgOn', $('orgOn').checked ? '1' : '0');

async function micList() {
  if (!navigator.mediaDevices?.enumerateDevices) return;
  const inputs = (await navigator.mediaDevices.enumerateDevices()).filter(d => d.kind === 'audioinput' && d.deviceId !== 'default');
  const saved = $('mic').value || store.get('gqai.mic');
  $('mic').innerHTML = '<option value="">시스템 기본 마이크</option>' +
    inputs.map((d, i) => `<option value="${d.deviceId}">${(d.label || `입력 장치 ${i + 1}`).replace(/[<>&]/g, '')}</option>`).join('');
  if (inputs.some(d => d.deviceId === saved)) $('mic').value = saved;
}
$('mic').onchange = () => store.set('gqai.mic', $('mic').value);
navigator.mediaDevices?.addEventListener?.('devicechange', () => void micList());
void micList();

// ---------------- audio → 16 kHz WAV ----------------
function toWav16k(parts, length, rate) {
  const src = new Float32Array(length); let o = 0;
  for (const p of parts) { src.set(p, o); o += p.length; }
  const ratio = rate / 16000, n = Math.floor(length / ratio), pcm = new Int16Array(n);
  for (let i = 0; i < n; i++) {  // average each source window: a simple low-pass for downsampling
    const a = Math.floor(i * ratio), b = Math.max(a + 1, Math.floor((i + 1) * ratio));
    let v = 0; for (let j = a; j < b; j++) v += src[j];
    v = Math.max(-1, Math.min(1, v / (b - a)));
    pcm[i] = v < 0 ? v * 0x8000 : v * 0x7fff;
  }
  const view = new DataView(new ArrayBuffer(44 + n * 2)), str = (at, s) => [...s].forEach((c, i) => view.setUint8(at + i, c.charCodeAt(0)));
  str(0, 'RIFF'); view.setUint32(4, 36 + n * 2, true); str(8, 'WAVE'); str(12, 'fmt ');
  view.setUint32(16, 16, true); view.setUint16(20, 1, true); view.setUint16(22, 1, true);
  view.setUint32(24, 16000, true); view.setUint32(28, 32000, true); view.setUint16(32, 2, true); view.setUint16(34, 16, true);
  str(36, 'data'); view.setUint32(40, n * 2, true);
  new Int16Array(view.buffer, 44).set(pcm);
  return new Uint8Array(view.buffer);
}
function base64(bytes) {
  let s = ''; for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(s);
}

// ---------------- live recording ----------------
let live = null;
const LIMIT_SECONDS = 7200;
function setStatus(s, extra = '') {
  $('status').textContent = `${s.recording ? '● 녹음 중' : '녹음 종료'} · ${Math.floor(s.seconds)}초 · 전사 ${s.done}구간 · 대기 ${s.queue.length}구간${extra ? ' · ' + extra : ''}`;
}
function flush(s) {
  // Skip nearly silent windows: they make Whisper invent text.
  if (s.length && s.energy / s.length > 0.000004) s.queue.push(toWav16k(s.parts, s.length, s.rate));
  s.parts = []; s.length = 0; s.energy = 0; s.silence = 0;
  if (s.queue.length >= 5 && s.recording) void stop(s, '처리가 밀려 녹음을 멈췄습니다. 남은 구간을 처리합니다.');
  void drain(s);
}
async function drain(s) {
  if (s.processing) return;
  s.processing = true;
  try {
    while (s.queue.length) {
      setStatus(s, '전사 중');
      const res = await fetch('/api/transcribe', {method: 'POST', headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({audio: base64(s.queue[0]), language: s.language})});
      const data = await res.json();
      if (!res.ok) throw new Error(data.error || '전사하지 못했습니다.');
      const text = data.text.trim();
      if (text) {
        orgFeed(text);
        const raw = $('raw'); raw.value += (raw.value.trim() ? (raw.value.length === s.rawStart ? '\n\n' : '\n') : '') + text;
        raw.scrollTop = raw.scrollHeight;
      }
      s.queue.shift(); s.done++; setStatus(s);
    }
  } catch (e) {
    s.queue.length = 0;
    if (s.recording) await stop(s);
    setStatus(s, e.message);
  } finally { s.processing = false; orgTick(s); finish(s); }
}
async function start() {
  if (!navigator.mediaDevices?.getUserMedia || !window.AudioWorkletNode) { $('status').textContent = '이 브라우저는 마이크 녹음을 지원하지 않습니다.'; return; }
  const s = live = {recording: false, queue: [], parts: [], length: 0, energy: 0, silence: 0, quiet: 0, voiced: false,
                    seconds: 0, done: 0, processing: false, pauseAt: 0, language: $('language').value,
                    pause: Number($('pause').value) || 3, rawStart: $('raw').value.length};
  $('toggle').disabled = true;
  try {
    const id = $('mic').value;
    s.stream = await navigator.mediaDevices.getUserMedia({audio: {echoCancellation: true, noiseSuppression: true, ...(id ? {deviceId: {exact: id}} : {})}});
    void micList();
    s.context = new AudioContext(); await s.context.resume(); s.rate = s.context.sampleRate;
    await s.context.audioWorklet.addModule('/mic-worklet.js');
    s.source = s.context.createMediaStreamSource(s.stream);
    s.node = new AudioWorkletNode(s.context, 'microphone-capture');
    s.node.port.onmessage = ({data}) => onFrame(s, data);
    s.source.connect(s.node); s.node.connect(s.context.destination);
    s.stream.getTracks().forEach(t => t.onended = () => void stop(s, '마이크가 끊겨 녹음을 멈췄습니다.'));
    s.recording = true;
    orgBegin(s);
    $('toggle').textContent = '중지'; $('toggle').classList.add('recording');
    lockSettings(true); setStatus(s, '말씀하세요');
  } catch (e) {
    s.stream?.getTracks().forEach(t => t.stop());
    if (s.context && s.context.state !== 'closed') await s.context.close();
    live = null;
    $('status').textContent = e.name === 'NotAllowedError' ? '마이크 권한이 필요합니다. 허용한 뒤 다시 시작하세요.' : `시작하지 못했습니다: ${e.message}`;
  } finally { $('toggle').disabled = false; }
}
function onFrame(s, data) {
  if (!s.recording) return;
  let energy = 0; for (const x of data) energy += x * x;
  const sec = data.length / s.rate, quietFrame = energy / data.length < 0.0001;
  s.parts.push(data); s.length += data.length; s.energy += energy; s.seconds += sec;
  s.silence = quietFrame ? s.silence + sec : 0;
  s.quiet = quietFrame ? s.quiet + sec : 0;  // time since the last voiced frame, kept across flushes
  if (!quietFrame) s.voiced = true;
  $('level').value = Math.min(1, Math.sqrt(energy / data.length) * 5);
  // Cut at a pause so words aren't split; never more than 20 s per segment.
  if ((s.length / s.rate >= 6 && s.silence >= 0.65) || s.length / s.rate >= 20) flush(s);
  else if (s.voiced && s.quiet >= 1) { flush(s); s.voiced = false; }  // short utterance then a pause
  orgTick(s);
  if (s.seconds >= LIMIT_SECONDS) void stop(s, '2시간 제한으로 멈췄습니다.');
  if (Math.floor(s.seconds) !== Math.floor(s.seconds - sec)) setStatus(s);
}
async function stop(s, note = '') {
  if (!s.recording) return;
  s.recording = false;
  s.stream.getTracks().forEach(t => t.stop());
  s.node.port.onmessage = null; s.node.disconnect(); s.source.disconnect();
  if (s.context.state !== 'closed') await s.context.close();
  $('level').value = 0; $('toggle').textContent = '시작'; $('toggle').classList.remove('recording');
  flush(s); setStatus(s, note || '남은 구간을 처리합니다.'); finish(s);
}
function finish(s) {
  if (s.recording || s.processing || s.queue.length || s.finished) return;
  s.finished = true;
  lockSettings(false);
  setStatus(s, s.done ? '전사 완료' : '인식된 음성이 없습니다.');
  void orgFinish();
}
function lockSettings(on) { for (const id of ['mic', 'language', 'pause', 'insertOn']) $(id).disabled = on; }
function toggle() { if (live?.recording) void stop(live); else if (!$('toggle').disabled && !(live && !live.finished)) void start(); }
$('toggle').onclick = toggle;
document.addEventListener('keydown', e => {
  if (e.altKey && e.code === 'KeyR' && !e.metaKey && !e.ctrlKey) { e.preventDefault(); toggle(); }
});
window.addEventListener('pagehide', () => live?.stream?.getTracks().forEach(t => t.stop()));

// ---------------- Claude cleanup ----------------
const EMPTY_MARK = '[[EMPTY]]';
const org = {session: null, busy: false, current: null, pending: '', due: false, failedAt: 0, failed: false, start: null, insert: false};
const orgState = t => { $('orgStatus').textContent = t; };
const orgEnabled = () => claudeReady && $('orgOn').checked;
const clean = t => { const s = t.replace(/\[\[EMPTY\]\]/g, ''); return s.trim() && EMPTY_MARK.startsWith(s.trim()) ? '' : s; };

function orgBegin(s) {
  org.session = crypto.randomUUID(); org.pending = ''; org.due = false; org.failed = false;
  org.start = {raw: s.rawStart, org: $('organized').value.length};
  org.insert = !!Native && $('insertOn').checked;
  if (orgEnabled()) void post('/api/organize/warm', {session: org.session});
}
function orgFeed(text) { org.pending += (org.pending ? ' ' : '') + text; }
// Called on every audio frame and whenever the transcription queue drains.
function orgTick(s) {
  if (!orgEnabled()) return;
  // Remember the pause even while Whisper is still busy, and send once the text before it has arrived.
  if (s.recording && s.quiet >= s.pause && !s.pauseAt) s.pauseAt = performance.now();
  if (!s.pauseAt || !org.pending.trim() || s.queue.length || s.processing) return;
  if (Date.now() - org.failedAt < 10000) return;  // back off after a failure
  s.pauseAt = 0;
  if (org.busy) { org.due = true; return; }
  void orgSend();
}
function post(url, body) {
  return fetch(url, {method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(body)});
}
async function readSSE(res, on) {
  const reader = res.body.getReader(), dec = new TextDecoder(); let buf = '';
  for (;;) {
    const {value, done} = await reader.read(); if (done) break;
    buf += dec.decode(value, {stream: true}); let i;
    while ((i = buf.indexOf('\n\n')) >= 0) {
      const block = buf.slice(0, i); buf = buf.slice(i + 2); let ev = 'message', data = '';
      for (const line of block.split('\n')) {
        if (line.startsWith('event: ')) ev = line.slice(7); else if (line.startsWith('data: ')) data += line.slice(6);
      }
      on(ev, data ? JSON.parse(data) : null);
    }
  }
}
function orgSend() {
  if (org.busy) return org.current;
  const text = org.pending.trim(); org.pending = ''; org.due = false;
  if (!text) return Promise.resolve(true);
  const box = $('organized'), before = box.value, sessionText = before.slice(org.start.org);
  const sep = before.trim() ? '\n\n' : '';  // paragraphs (and recordings) are separated by a blank line
  org.busy = true; box.readOnly = true; orgState('Claude가 정리하는 중…');
  const t0 = performance.now(); let first = 0;
  org.current = (async () => {
    let streamed = '', failure = null, done = false;
    try {
      const res = await post('/api/organize', {session: org.session, text, context: sessionText.slice(-4000), lang: $('outLang').value});
      if (!res.ok) throw new Error((await res.json().catch(() => ({}))).error || '정리를 시작하지 못했습니다.');
      await readSSE(res, (ev, data) => {
        if (ev === 'delta') {
          if (!first) first = performance.now();
          streamed += data.text; const body = clean(streamed).replace(/^\s+/, '');
          box.value = before + (body ? sep : '') + body; box.scrollTop = box.scrollHeight;
        } else if (ev === 'progress') orgState(`Claude가 정리하는 중… ${data.seconds}초`);
        else if (ev === 'error') failure = data.message;
        else if (ev === 'done') done = true;
      });
      if (failure) throw new Error(failure);
      if (!done) throw new Error('정리 응답이 중간에 끊겼습니다.');
      if (!clean(streamed).trim()) box.value = before;
      org.failed = false;
      orgState(`정리 완료 · 첫 글자까지 ${first ? ((first - t0) / 1000).toFixed(1) : '-'}초`);
      return true;
    } catch (e) {
      box.value = before; org.pending = text + (org.pending ? ' ' + org.pending : '');
      org.failedAt = Date.now(); org.failed = true;
      orgState(`${e.message} 다음 쉼에 다시 시도합니다.`);
      return false;
    } finally { org.busy = false; box.readOnly = false; }
  })();
  return org.current.then(ok => { if (ok && org.due && org.pending.trim()) void orgSend(); return ok; });
}
async function orgFinish() {
  const session = org.session;
  while (org.busy) await org.current;
  if (orgEnabled() && org.pending.trim()) { org.failedAt = 0; await orgSend(); while (org.busy) await org.current; }
  if (org.insert) orgInsert();
  if (session) void post('/api/organize/end', {session});
  org.session = null;
}
// Sends this recording's text to the app for pasting: the cleaned text, or the raw text if cleanup was off or failed.
function orgInsert() {
  org.insert = false;
  const raw = $('raw').value.slice(org.start.raw).trim();
  const useRaw = !orgEnabled() || org.failed || !!org.pending.trim();
  const text = useRaw ? raw : $('organized').value.slice(org.start.org).trim();
  if (!text) { orgState(raw ? '정리할 내용이 없어(잡음) 넣지 않았습니다.' : '넣을 내용이 없습니다.'); return; }
  orgState('앞 앱 입력창에 넣는 중…');
  Native.post({type: 'insert', text, source: useRaw ? 'raw' : 'organized'});
}

// ---------------- buttons ----------------
async function copy(id) {
  try { await navigator.clipboard.writeText($(id).value); orgState('복사했습니다.'); } catch { orgState('복사하지 못했습니다.'); }
}
$('copyRaw').onclick = () => copy('raw');
$('copyOrg').onclick = () => copy('organized');
$('clear').onclick = () => { if (live && !live.finished) return; $('raw').value = ''; $('organized').value = ''; orgState(''); };

// ---------------- dictionary ----------------
function renderDict(words) {
  $('dictList').innerHTML = '';
  for (const w of words) {
    const li = document.createElement('li'); li.textContent = w.term + (w.note ? ` · ${w.note}` : '');
    const del = document.createElement('button'); del.textContent = '×'; del.setAttribute('aria-label', `${w.term} 삭제`);
    del.onclick = async () => renderDict((await (await post('/api/dictionary', {action: 'delete', term: w.term})).json()).words);
    li.append(del); $('dictList').append(li);
  }
}
$('termAdd').onclick = async () => {
  const res = await post('/api/dictionary', {action: 'add', term: $('term').value, note: $('termNote').value});
  const data = await res.json();
  if (!res.ok) { orgState(data.error); return; }
  $('term').value = ''; $('termNote').value = ''; renderDict(data.words);
};
fetch('/api/dictionary').then(r => r.json()).then(d => renderDict(d.words)).catch(() => {});

// ---------------- native app (macOS: mac/, Windows: see docs/WINDOWS.md) ----------------
window.gqaiNative = {
  toggle,
  inserted(message) { orgState(message); },
  insertPermission(ok) {
    orgState(ok ? '권한이 있습니다. 단축키로 말하면 앞 앱 입력창에 넣습니다.'
                : '손쉬운 사용 권한이 필요합니다. 시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용에서 GQAI Live를 켜세요.');
  },
  state() {
    return {recording: !!live?.recording, processing: !!(live && !live.finished && !live.recording),
            organizing: org.busy, seconds: Math.floor(live?.seconds || 0)};
  },
};
if (Native) {
  $('shortcut').textContent = Native.shortcut;
  $('insertRow').hidden = false;
  $('insertOn').checked = store.get('gqai.insert') === '1';
  const ask = () => Native.post({type: 'insertPermission'});
  $('insertOn').onchange = () => { store.set('gqai.insert', $('insertOn').checked ? '1' : '0'); if ($('insertOn').checked) ask(); };
  if ($('insertOn').checked) ask();
  let last = '';
  setInterval(() => {  // report state changes (menu bar icon)
    const st = window.gqaiNative.state(), key = JSON.stringify(st);
    if (key !== last) { last = key; Native.post({type: 'state', ...st}); }
  }, 400);
}
