import assert from 'node:assert/strict';
import { createServer, connect } from 'node:net';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';

const oneWayMs = Number(process.env.PONG_TEST_LATENCY_MS ?? 100);
assert.ok(Number.isFinite(oneWayMs) && oneWayMs >= 0 && oneWayMs <= 250);
const root = resolve(import.meta.dirname, '..');
const data = mkdtempSync(join(tmpdir(), 'pong-native-'));
const server = spawn(process.execPath, ['server/authoritative_server.mjs'], { cwd: root, env: { ...process.env, HOST: '127.0.0.1', PORT: '0' }, stdio: ['ignore', 'pipe', 'pipe'] });
const children = [];
const sockets = new Set();
const timers = new Set();
let proxy;
// Delay both TCP directions, preserving byte order even when jitter varies.
function forward(source, destination) {
  let due = 0;
  let packet = 0;
  source.on('data', bytes => {
    const jitter = oneWayMs ? [0, 12, -12, 6, -6][packet++ % 5] : 0;
    due = Math.max(due, performance.now() + Math.max(0, oneWayMs + jitter));
    const timer = setTimeout(() => {
      timers.delete(timer);
      if (!destination.destroyed) destination.write(bytes);
    }, Math.max(0, due - performance.now()));
    timers.add(timer);
  });
}
const deadline = setTimeout(() => { for (const child of [...children, server]) child.kill('SIGKILL'); }, 25000);
try {
  const ready = await new Promise((resolve, reject) => {
    let output = '';
    server.once('exit', () => reject(new Error('server exited before ready')));
    server.stdout.on('data', bytes => { output += bytes; if (output.includes('\n')) resolve(JSON.parse(output.split('\n')[0])); });
  });
  proxy = createServer(downstream => {
    const upstream = connect(ready.port, '127.0.0.1');
    sockets.add(downstream); sockets.add(upstream);
    for (const socket of [downstream, upstream]) {
      socket.on('error', () => {});
      socket.once('close', () => {
        sockets.delete(socket);
        downstream.destroy(); upstream.destroy();
      });
    }
    forward(downstream, upstream); forward(upstream, downstream);
  });
  proxy.listen(0, '127.0.0.1');
  await once(proxy, 'listening');
  const run = index => new Promise((resolve, reject) => {
    const child = spawn(process.env.GODOT_BIN || 'godot', ['--headless', '--path', root, '--script', 'test/network_client.gd'], {
      env: { ...process.env, PONG_WS_URL: `ws://127.0.0.1:${proxy.address().port}/ws`, PONG_ROOM: 'NATIVE', XDG_DATA_HOME: join(data, String(index)) }, stdio: ['ignore', 'pipe', 'pipe'],
    });
    children.push(child);
    let output = '';
    child.stdout.on('data', bytes => { output += bytes; });
    child.stderr.on('data', bytes => { output += bytes; });
    child.once('error', reject);
    child.once('exit', code => {
      const result = output.match(/PONG_NATIVE_PASS (.+)/);
      if (code !== 0 || !result || /SCRIPT ERROR|ERROR:/.test(output)) reject(new Error(output));
      else resolve(JSON.parse(result[1]));
    });
  });
  const results = await Promise.all([run(0), run(1)]);
  assert.deepEqual(new Set(results.map(result => result.role)), new Set(['left', 'right']));
  assert.equal(results[0].score, results[1].score);
  assert.ok(results.every(result => result.modal_snapshot_updates > 0), "live snapshots continue while both owner panels are open");
  console.log(JSON.stringify({ result: 'PASS', simulatedRttMs: oneWayMs * 2, jitterMs: oneWayMs ? 12 : 0, clients: results }));
} finally {
  clearTimeout(deadline);
  for (const timer of timers) clearTimeout(timer);
  for (const socket of sockets) socket.destroy();
  proxy?.close();
  for (const child of children) child.kill();
  server.kill();
  await once(server, 'exit').catch(() => {});
  rmSync(data, { recursive: true, force: true });
}
