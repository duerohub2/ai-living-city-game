import assert from 'node:assert/strict';
import test from 'node:test';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { WebSocket } from 'ws';

async function startServer() {
  const child = spawn(process.execPath, ['authoritative_server.mjs'], {
    cwd: import.meta.dirname, env: { ...process.env, HOST: '127.0.0.1', PORT: '0' }, stdio: ['ignore', 'pipe', 'pipe'],
  });
  let errors = '';
  child.stderr.on('data', chunk => { errors += chunk; });
  const ready = await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('server startup timeout: ' + errors)), 10000);
    child.once('exit', code => { clearTimeout(timer); reject(new Error('server exit ' + code + ': ' + errors)); });
    let output = '';
    child.stdout.on('data', chunk => {
      output += chunk;
      if (output.includes('\n')) {
        try { const value = JSON.parse(output.split('\n')[0]); clearTimeout(timer); resolve(value); } catch (error) { reject(error); }
      }
    });
  }).catch(error => { child.kill(); throw error; });
  return { child, url: `ws://127.0.0.1:${ready.port}/ws` };
}

async function client(url, room, resume) {
  const ws = new WebSocket(`${url}?room=${room}${resume ? '&resume=' + encodeURIComponent(resume) : ''}`);
  const messages = [];
  const waiters = new Set();
  ws.on('error', () => {});
  ws.on('message', bytes => {
    const value = JSON.parse(bytes.toString());
    messages.push(value);
    if (messages.length > 100) messages.shift();
    for (const waiter of waiters) if (waiter.predicate(value)) { waiters.delete(waiter); clearTimeout(waiter.timer); waiter.resolve(value); }
  });
  function wait(predicate) {
    const existing = messages.find(predicate);
    if (existing) return Promise.resolve(existing);
    return new Promise((resolve, reject) => {
      const waiter = { predicate, resolve, timer: setTimeout(() => { waiters.delete(waiter); reject(new Error('packet timeout')); }, 5000) };
      waiters.add(waiter);
    });
  }
  let seq = 0;
  const welcome = await wait(value => value.type === 'welcome');
  return { ws, welcome, wait, send: value => ws.send(JSON.stringify({ type: 'input', value, seq: ++seq, sent_msec: Math.floor(performance.now()) })) };
}

test('two seats, spectator authority, isolated rooms, strict input and seat resume', { timeout: 20000 }, async () => {
  const { child, url } = await startServer();
  const clients = [];
  const open = async (...args) => { const value = await client(url, ...args); clients.push(value); return value; };
  try {
    const left = await open('ROOM');
    const right = await open('ROOM');
    const spectator = await open('ROOM');
    const other = await open('ELSE');
    assert.equal(left.welcome.role, 'left');
    assert.deepEqual(left.welcome.movement, { speed: 0.74, min_y: 0.11, max_y: 0.89 });
    assert.equal(right.welcome.role, 'right');
    assert.equal(spectator.welcome.role, 'spectator');
    assert.equal(other.welcome.role, 'left');
    const initial = await right.wait(value => value.type === 'state' && value.phase === 'live');
    spectator.send(1);
    left.send('1');
    left.send({ y: 1 });
    const unchanged = await right.wait(value => value.type === 'state' && value.seq > initial.seq + 4);
    assert.equal(unchanged.paddles.left.y, initial.paddles.left.y);
    assert.equal(unchanged.paddles.right.y, initial.paddles.right.y);
    left.send(1);
    const moved = await right.wait(value => value.type === 'state' && value.paddles.left.y > initial.paddles.left.y + 0.1);
    assert.ok(moved.paddles.left.ack_seq > 0);
    assert.ok(moved.paddles.left.sent_msec > 0);
    assert.ok(Math.abs(moved.paddles.left.vy - 0.74) < 1e-9);
    left.send(0);
    assert.equal(moved.paddles.right.y, initial.paddles.right.y);
    const isolated = await other.wait(value => value.type === 'state');
    assert.equal(isolated.phase, 'waiting');
    assert.equal(isolated.paddles.left.y, 0.5);
    const closed = once(left.ws, 'close');
    const resumed = await open('ROOM', left.welcome.resume_token);
    assert.equal(resumed.welcome.role, 'left');
    assert.equal((await closed)[0], 4001);
    resumed.send(-1);
    await right.wait(value => value.type === 'state' && value.seq > moved.seq && value.paddles.left.y < moved.paddles.left.y - 0.08);
    resumed.send(0);
    resumed.ws.send('not json');
    const rejected = await resumed.wait(value => value.type === 'error');
    assert.deepEqual(rejected, { type: 'error', marker: 'pong-online-v2', room: 'ROOM', code: 'invalid_message' });
    const response = await fetch(url.replace('ws:', 'http:').replace('/ws', '/healthz'));
    assert.equal((await response.json()).marker, 'pong-online-v2');
  } finally {
    for (const value of clients) value.ws.terminate();
    child.kill('SIGTERM');
    await once(child, 'exit');
  }
});

test('original two-client scoring and disconnect regression', { timeout: 40000 }, async () => {
  const { child, url } = await startServer();
  const runner = spawn(process.execPath, ['e2e_clients.mjs', url], { cwd: import.meta.dirname, stdio: ['ignore', 'pipe', 'pipe'] });
  let output = '';
  runner.stdout.on('data', data => { output += data; });
  runner.stderr.on('data', data => { output += data; });
  const timeout = setTimeout(() => runner.kill('SIGKILL'), 35000);
  try {
    const [code] = await once(runner, 'exit');
    assert.equal(code, 0, output);
    assert.match(output, /"result":"PASS"/);
  } finally { clearTimeout(timeout); runner.kill(); child.kill('SIGTERM'); await once(child, 'exit'); }
});


test('input acknowledgements are applied, bounded and reset on seat replacement', { timeout: 10000 }, async () => {
  const { child, url } = await startServer();
  const clients = [];
  try {
    const left = await client(url, 'ACKS'); clients.push(left);
    const right = await client(url, 'ACKS'); clients.push(right);
    left.ws.send(JSON.stringify({ type: 'input', value: 1, seq: 10, sent_msec: 123 }));
    const moved = await right.wait(value => value.type === 'state' && value.paddles.left.ack_seq === 10);
    assert.equal(moved.paddles.left.sent_msec, 123);
    for (const seq of [9, 10, -1, 10.5, Number.MAX_SAFE_INTEGER + 1]) {
      left.ws.send(JSON.stringify({ type: 'input', value: -1, seq, sent_msec: 999 }));
    }
    const later = await right.wait(value => value.type === 'state' && value.seq > moved.seq + 2);
    assert.equal(later.paddles.left.ack_seq, 10);
    assert.equal(later.paddles.left.sent_msec, 123);
    assert.ok(later.paddles.left.y >= moved.paddles.left.y);
    const stale = await right.wait(value => value.type === 'state' && value.seq > later.seq + 12);
    assert.equal(stale.paddles.left.vy, 0, 'silent input is released');
    const resumed = await client(url, 'ACKS', left.welcome.resume_token); clients.push(resumed);
    resumed.send(-1);
    const reset = await resumed.wait(value => value.type === 'state' && value.paddles.left.ack_seq === 1);
    assert.ok(reset.paddles.left.vy < 0, 'fresh socket starts its own sequence');
  } finally {
    for (const value of clients) value.ws.terminate();
    child.kill('SIGTERM');
    await once(child, 'exit');
  }
});
