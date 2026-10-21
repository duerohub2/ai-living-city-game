#!/usr/bin/env node
import assert from 'node:assert/strict';
import { WebSocket } from 'ws';

const base = process.argv[2] || process.env.PONG_WS_URL || 'ws://127.0.0.1:8787/ws';
const room = (process.env.PONG_TEST_ROOM || `E2E${Date.now().toString(36)}`).toUpperCase().replace(/[^A-Z0-9]/g, '').slice(-8).padStart(4, 'E');
const healthUrl = base.replace(/^ws/, 'http').replace(/\/ws(?:\?.*)?$/, '/healthz');

class Client {
  constructor(name, resume = '') {
    this.name = name;
    this.seq = 0;
    this.messages = [];
    this.waiters = [];
    const url = `${base}${base.includes('?') ? '&' : '?'}room=${room}${resume ? `&resume=${resume}` : ''}`;
    this.ws = new WebSocket(url);
    this.ws.on('message', data => {
      const message = JSON.parse(data.toString());
      this.messages.push(message);
      if (this.messages.length > 100) this.messages.shift();
      for (const waiter of [...this.waiters]) {
        if (waiter.predicate(message)) {
          clearTimeout(waiter.timer);
          this.waiters.splice(this.waiters.indexOf(waiter), 1);
          waiter.resolve(message);
        }
      }
    });
  }

  waitFor(predicate, timeout = 10_000) {
    const existing = [...this.messages].reverse().find(predicate);
    if (existing) return Promise.resolve(existing);
    return new Promise((resolve, reject) => {
      const waiter = { predicate, resolve, timer: null };
      waiter.timer = setTimeout(() => {
        this.waiters = this.waiters.filter(value => value !== waiter);
        reject(new Error(`${this.name} timed out waiting for message`));
      }, timeout);
      this.waiters.push(waiter);
    });
  }

  sendInput(value) {
    this.ws.send(JSON.stringify({ type: 'input', value, seq: ++this.seq, sent_msec: Math.floor(performance.now()) }));
  }

  latestState() {
    return [...this.messages].reverse().find(message => message.type === 'state');
  }

  async close() {
    if (this.ws.readyState === WebSocket.CLOSED) return;
    await new Promise(resolve => {
      const timer = setTimeout(resolve, 1000);
      this.ws.once('close', () => { clearTimeout(timer); resolve(); });
      this.ws.close(1000, 'test close');
    });
  }
}

const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

async function main() {
  const health = await fetch(healthUrl).then(response => response.json());
  assert.equal(health.ok, true);
  assert.equal(health.marker, 'pong-online-v2');

  const first = new Client('first');
  const welcomeFirst = await first.waitFor(message => message.type === 'welcome');
  const second = new Client('second');
  const welcomeSecond = await second.waitFor(message => message.type === 'welcome');
  assert.deepEqual(new Set([welcomeFirst.role, welcomeSecond.role]), new Set(['left', 'right']));

  const left = welcomeFirst.role === 'left' ? first : second;
  const right = welcomeFirst.role === 'right' ? first : second;
  const leftWelcome = welcomeFirst.role === 'left' ? welcomeFirst : welcomeSecond;
  await Promise.all([
    left.waitFor(message => message.type === 'state' && message.phase === 'live'),
    right.waitFor(message => message.type === 'state' && message.phase === 'live'),
  ]);

  const beforeLeft = left.latestState();
  left.sendInput(1);
  await sleep(520);
  left.sendInput(0);
  const afterLeft = await right.waitFor(message => message.type === 'state' && message.paddles.left.y > beforeLeft.paddles.left.y + 0.12);
  assert.ok(Math.abs(afterLeft.paddles.right.y - beforeLeft.paddles.right.y) < 0.03, 'left input must not move right paddle');

  const beforeRight = right.latestState();
  right.sendInput(-1);
  await sleep(520);
  right.sendInput(0);
  const afterRight = await left.waitFor(message => message.type === 'state' && message.paddles.right.y < beforeRight.paddles.right.y - 0.12);
  assert.ok(Math.abs(afterRight.paddles.left.y - left.latestState().paddles.left.y) < 0.05, 'right input must not control left paddle');

  left.sendInput(1);
  right.sendInput(-1);
  await sleep(900);
  left.sendInput(0);
  right.sendInput(0);
  const initialTotal = afterRight.score.left + afterRight.score.right;
  const [leftScored, rightScored] = await Promise.all([
    left.waitFor(message => message.type === 'state' && message.score.left + message.score.right > initialTotal, 25_000),
    right.waitFor(message => message.type === 'state' && message.score.left + message.score.right > initialTotal, 25_000),
  ]);
  assert.deepEqual(leftScored.score, rightScored.score, 'both clients must receive the same authoritative score');

  const scoreBeforeReconnect = { ...leftScored.score };
  await left.close();
  await right.waitFor(message => message.type === 'state' && message.phase === 'waiting' && message.players.left === false, 5000);

  const resumed = new Client('resumed-left', leftWelcome.resume_token);
  const resumedWelcome = await resumed.waitFor(message => message.type === 'welcome');
  assert.equal(resumedWelcome.role, 'left');
  const resumedState = await resumed.waitFor(message => message.type === 'state' && message.phase === 'live');
  assert.deepEqual(resumedState.score, scoreBeforeReconnect, 'reconnect must restore the authoritative score');
  await right.waitFor(message => message.type === 'state' && message.phase === 'live' && message.players.left === true, 5000);

  const reconnectStart = resumedState.paddles.left.y;
  resumed.sendInput(-1);
  await sleep(420);
  resumed.sendInput(0);
  await right.waitFor(message => message.type === 'state' && message.paddles.left.y < reconnectStart - 0.08, 5000);

  await resumed.close();
  await right.close();
  console.log(JSON.stringify({
    marker: 'pong-online-v2',
    result: 'PASS',
    room,
    roles: { first: welcomeFirst.role, second: welcomeSecond.role },
    score: scoreBeforeReconnect,
    checks: ['left-input', 'right-input', 'shared-score', 'disconnect', 'resume-token', 'post-reconnect-input'],
  }));
}

main().catch(error => {
  console.error(JSON.stringify({ marker: 'pong-online-v2', result: 'FAIL', error: error.stack || String(error) }));
  process.exitCode = 1;
});
