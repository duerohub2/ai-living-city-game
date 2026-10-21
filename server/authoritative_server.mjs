#!/usr/bin/env node
import { createServer } from 'node:http';
import { randomBytes } from 'node:crypto';
import { stat, realpath } from 'node:fs/promises';
import { createReadStream } from 'node:fs';
import { pipeline } from 'node:stream/promises';
import { dirname, extname, join, normalize, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { WebSocketServer, WebSocket } from 'ws';

const MARKER = 'pong-online-v2';
const HOST = process.env.HOST || '127.0.0.1';
const PORT = Number(process.env.PORT || 8787);
const STATIC_ROOT = resolve(process.env.STATIC_ROOT || join(dirname(fileURLToPath(import.meta.url)), '../site'));
const TICK_HZ = 60;
const SNAPSHOT_HZ = 20;
const RECONNECT_GRACE_MS = 60_000;
const ROOM_IDLE_MS = 10 * 60_000;
const PADDLE_HALF_HEIGHT = 0.11;
const PADDLE_HALF_WIDTH = 0.012;
const PADDLE_SPEED = 0.74;
const BALL_RADIUS = 0.014;
const BALL_SPEED = 0.48;
const LEFT_X = 0.05;
const RIGHT_X = 0.95;

const MIME = new Map([
  ['.html', 'text/html; charset=utf-8'],
  ['.js', 'text/javascript; charset=utf-8'],
  ['.wasm', 'application/wasm'],
  ['.pck', 'application/octet-stream'],
  ['.png', 'image/png'],
  ['.svg', 'image/svg+xml'],
  ['.ogg', 'audio/ogg'],
  ['.wav', 'audio/wav'],
  ['.json', 'application/json; charset=utf-8'],
]);

const rooms = new Map();
const MAX_ROOMS = 128;
const MAX_CLIENTS = 256;
const MAX_SPECTATORS = 8;
const MAX_BUFFERED_BYTES = 64 * 1024;
const allowedOrigins = new Set((process.env.ALLOWED_ORIGINS || '').split(',').map(value => value.trim()).filter(Boolean));
if (!Number.isInteger(PORT) || PORT < 0 || PORT > 65535) throw new Error('Invalid PORT');

function cleanRoomCode(value) {
  const code = String(value || '').toUpperCase();
  return /^[A-Z0-9]{4,8}$/.test(code) ? code : '';
}

function token() {
  return randomBytes(18).toString('base64url');
}

function send(ws, payload) {
  if (ws.bufferedAmount > MAX_BUFFERED_BYTES) { ws.terminate(); return; }
  if (ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify(payload));
}

class Room {
  constructor(code) {
    this.code = code;
    this.createdAt = Date.now();
    this.lastActivity = Date.now();
    this.seq = 0;
    this.eventSeq = 0;
    this.eventKind = '';
    this.score = { left: 0, right: 0 };
    this.ball = { x: 0.5, y: 0.5, vx: 0, vy: 0 };
    this.paddles = { left: { y: 0.5, vy: 0, ack_seq: 0, sent_msec: 0 }, right: { y: 0.5, vy: 0, ack_seq: 0, sent_msec: 0 } };
    this.seats = {
      left: { token: '', socket: null, input: 0, seq: 0, sentMsec: 0, inputAt: 0, disconnectedAt: 0 },
      right: { token: '', socket: null, input: 0, seq: 0, sentMsec: 0, inputAt: 0, disconnectedAt: 0 },
    };
    this.observers = new Set();
    this.serveAt = 0;
  }

  connected(role) {
    return this.seats[role].socket?.readyState === WebSocket.OPEN;
  }

  bothConnected() {
    return this.connected('left') && this.connected('right');
  }

  phase() {
    return this.bothConnected() ? 'live' : 'waiting';
  }

  claim(ws, resumeToken) {
    this.lastActivity = Date.now();
    let role = 'spectator';
    for (const side of ['left', 'right']) {
      const seat = this.seats[side];
      if (resumeToken && seat.token === resumeToken && (!seat.disconnectedAt || Date.now() - seat.disconnectedAt <= RECONNECT_GRACE_MS)) {
        if (seat.socket && seat.socket !== ws && seat.socket.readyState === WebSocket.OPEN) {
          seat.socket.close(4001, 'seat resumed elsewhere');
        }
        role = side;
        seat.socket = ws;
        seat.disconnectedAt = 0;
        seat.input = 0;
        seat.seq = 0;
        seat.sentMsec = 0;
        seat.inputAt = 0;
        Object.assign(this.paddles[side], { vy: 0, ack_seq: 0, sent_msec: 0 });
        break;
      }
    }
    if (role === 'spectator') {
      for (const side of ['left', 'right']) {
        const seat = this.seats[side];
        if (!seat.token) {
          role = side;
          seat.token = token();
          seat.socket = ws;
          seat.disconnectedAt = 0;
          seat.input = 0;
          seat.seq = 0;
          seat.sentMsec = 0;
          seat.inputAt = 0;
          Object.assign(this.paddles[side], { vy: 0, ack_seq: 0, sent_msec: 0 });
          break;
        }
      }
    }
    if (role === 'spectator') {
      if (this.observers.size >= MAX_SPECTATORS) { ws.close(1013, 'room full'); return; }
      this.observers.add(ws);
    }
    ws.room = this;
    ws.role = role;
    const resume = role === 'spectator' ? '' : this.seats[role].token;
    send(ws, { type: 'welcome', marker: MARKER, room: this.code, role, resume_token: resume,
      movement: { speed: PADDLE_SPEED, min_y: PADDLE_HALF_HEIGHT, max_y: 1 - PADDLE_HALF_HEIGHT } });
    if (this.bothConnected() && this.ball.vx === 0 && this.serveAt === 0) this.serveAt = Date.now() + 650;
    this.broadcast();
  }

  release(ws) {
    this.lastActivity = Date.now();
    if (ws.role === 'left' || ws.role === 'right') {
      const seat = this.seats[ws.role];
      if (seat.socket === ws) {
        seat.socket = null;
        seat.input = 0;
        seat.disconnectedAt = Date.now();
      }
    } else {
      this.observers.delete(ws);
    }
    this.broadcast();
  }

  input(role, value, seq, sentMsec) {
    if (role !== 'left' && role !== 'right') return;
    if (typeof value !== 'number' || ![-1, 0, 1].includes(value)) return;
    const seat = this.seats[role];
    if (!Number.isSafeInteger(seq) || seq <= seat.seq || !Number.isSafeInteger(sentMsec) || sentMsec < 0) return;
    seat.input = value;
    seat.seq = seq;
    seat.sentMsec = sentMsec; // Echo only. Client time never drives authoritative simulation.
    seat.inputAt = Date.now();
    this.lastActivity = Date.now();
  }

  tick(dt, now) {
    for (const side of ['left', 'right']) {
      const seat = this.seats[side];
      if (seat.token && seat.disconnectedAt && now - seat.disconnectedAt > RECONNECT_GRACE_MS) {
        seat.token = '';
        seat.disconnectedAt = 0;
      }
    }
    if (!this.bothConnected()) {
      for (const paddle of Object.values(this.paddles)) paddle.vy = 0;
      return;
    }
    for (const side of ['left', 'right']) {
      const paddle = this.paddles[side];
      const seat = this.seats[side];
      if (now - seat.inputAt > 500) seat.input = 0;
      const previousY = paddle.y;
      paddle.y = Math.max(PADDLE_HALF_HEIGHT, Math.min(1 - PADDLE_HALF_HEIGHT, paddle.y + seat.input * PADDLE_SPEED * dt));
      paddle.vy = (paddle.y - previousY) / dt;
      paddle.ack_seq = seat.seq;
      paddle.sent_msec = seat.sentMsec;
    }
    if (this.serveAt && now >= this.serveAt) this.serve();
    if (this.ball.vx === 0) return;
    const previousX = this.ball.x;
    this.ball.x += this.ball.vx * dt;
    this.ball.y += this.ball.vy * dt;
    if (this.ball.y - BALL_RADIUS <= 0 && this.ball.vy < 0) {
      this.ball.y = BALL_RADIUS;
      this.ball.vy = Math.abs(this.ball.vy);
      this.event('wall');
    } else if (this.ball.y + BALL_RADIUS >= 1 && this.ball.vy > 0) {
      this.ball.y = 1 - BALL_RADIUS;
      this.ball.vy = -Math.abs(this.ball.vy);
      this.event('wall');
    }
    this.collidePaddle('left', previousX);
    this.collidePaddle('right', previousX);
    if (this.ball.x < -BALL_RADIUS) this.point('right');
    else if (this.ball.x > 1 + BALL_RADIUS) this.point('left');
  }

  collidePaddle(side, previousX) {
    const isLeft = side === 'left';
    if ((isLeft && this.ball.vx >= 0) || (!isLeft && this.ball.vx <= 0)) return;
    const plane = (isLeft ? LEFT_X + PADDLE_HALF_WIDTH : RIGHT_X - PADDLE_HALF_WIDTH);
    const crossed = isLeft
      ? previousX - BALL_RADIUS > plane && this.ball.x - BALL_RADIUS <= plane
      : previousX + BALL_RADIUS < plane && this.ball.x + BALL_RADIUS >= plane;
    const paddle = this.paddles[side];
    if (!crossed || Math.abs(this.ball.y - paddle.y) > PADDLE_HALF_HEIGHT + BALL_RADIUS) return;
    this.ball.x = plane + (isLeft ? BALL_RADIUS : -BALL_RADIUS);
    const offset = Math.max(-1, Math.min(1, (this.ball.y - paddle.y) / PADDLE_HALF_HEIGHT));
    const speed = Math.min(0.72, Math.hypot(this.ball.vx, this.ball.vy) * 1.035);
    const angle = offset * 0.88 + this.seats[side].input * 0.08;
    this.ball.vx = Math.cos(angle) * speed * (isLeft ? 1 : -1);
    this.ball.vy = Math.sin(angle) * speed;
    this.event('paddle');
  }

  serve() {
    const total = this.score.left + this.score.right;
    const direction = total % 2 === 0 ? 1 : -1;
    const vertical = total % 3 === 0 ? 0.19 : total % 3 === 1 ? -0.23 : 0.27;
    const horizontal = Math.sqrt(Math.max(0.01, BALL_SPEED * BALL_SPEED - vertical * vertical));
    this.ball = { x: 0.5, y: 0.5, vx: horizontal * direction, vy: vertical };
    this.serveAt = 0;
  }

  point(side) {
    this.score[side] += 1;
    this.ball = { x: 0.5, y: 0.5, vx: 0, vy: 0 };
    this.serveAt = Date.now() + 650;
    this.event('score');
  }

  event(kind) {
    this.eventSeq += 1;
    this.eventKind = kind;
  }

  snapshot() {
    this.seq += 1;
    return {
      type: 'state', marker: MARKER, room: this.code, seq: this.seq,
      phase: this.phase(),
      players: { left: this.connected('left'), right: this.connected('right') },
      paddles: Object.fromEntries(['left', 'right'].map(side => [side, {
        ...this.paddles[side], vy: this.bothConnected() ? this.paddles[side].vy : 0,
      }])),
      ball: { x: this.ball.x, y: this.ball.y },
      score: { left: this.score.left, right: this.score.right },
      event: { seq: this.eventSeq, kind: this.eventKind },
      server_time: Date.now(),
    };
  }

  broadcast() {
    const payload = JSON.stringify(this.snapshot());
    for (const side of ['left', 'right']) {
      const socket = this.seats[side].socket;
      if (socket?.bufferedAmount > MAX_BUFFERED_BYTES) socket.terminate();
      else if (socket?.readyState === WebSocket.OPEN) socket.send(payload);
    }
    for (const socket of this.observers) {
      if (socket.bufferedAmount > MAX_BUFFERED_BYTES) socket.terminate();
      else if (socket.readyState === WebSocket.OPEN) socket.send(payload);
      else this.observers.delete(socket);
    }
  }
}

function roomFor(code) {
  if (!rooms.has(code)) rooms.set(code, new Room(code));
  return rooms.get(code);
}

const httpServer = createServer(async (request, response) => {
  try {
    const url = new URL(request.url || '/', `http://${request.headers.host || 'localhost'}`);
    if (url.pathname === '/healthz') {
      response.writeHead(200, { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' });
      response.end(JSON.stringify({ ok: true, marker: MARKER, rooms: rooms.size, uptime: process.uptime() }));
      return;
    }
    let pathname = decodeURIComponent(url.pathname);
    if (pathname === '/') pathname = '/index.html';
    const relative = normalize(pathname).replace(/^([/\\])+/, '');
    const filePath = resolve(STATIC_ROOT, relative);
    if (!filePath.startsWith(STATIC_ROOT + '/') && filePath !== STATIC_ROOT) throw new Error('invalid path');
    const info = await stat(filePath);
    if (!info.isFile()) throw new Error('not a file');
    const physicalRoot = await realpath(STATIC_ROOT);
    const physicalFile = await realpath(filePath);
    if (!physicalFile.startsWith(physicalRoot + '/') || relative.split('/').some(part => part.startsWith('.'))) throw new Error('invalid path');
    if (!['GET', 'HEAD'].includes(request.method)) { response.writeHead(405); response.end(); return; }
    response.writeHead(200, {
      'content-type': MIME.get(extname(filePath).toLowerCase()) || 'application/octet-stream',
      'cache-control': filePath.endsWith('index.html') ? 'no-store' : 'public, max-age=3600',
      'x-content-type-options': 'nosniff',
      'content-length': info.size,
    });
    if (request.method === 'HEAD') response.end();
    else await pipeline(createReadStream(physicalFile), response);
  } catch {
    if (response.headersSent) { response.destroy(); return; }
    response.writeHead(404, { 'content-type': 'text/plain; charset=utf-8' });
    response.end('Not found');
  }
});

const websocketServer = new WebSocketServer({ noServer: true, maxPayload: 4096 });
httpServer.on('upgrade', (request, socket, head) => {
  let url;
  try { url = new URL(request.url || '/', `http://${request.headers.host || 'localhost'}`); }
  catch { socket.destroy(); return; }
  const origin = request.headers.origin;
  let sameOrigin = false;
  try { sameOrigin = Boolean(origin) && ['http:', 'https:'].includes(new URL(origin).protocol) && new URL(origin).host === request.headers.host; } catch {}
  if (websocketServer.clients.size >= MAX_CLIENTS || (origin && !sameOrigin && !allowedOrigins.has(origin))) { socket.destroy(); return; }
  if (url.pathname !== '/ws') {
    socket.destroy();
    return;
  }
  const roomCode = cleanRoomCode(url.searchParams.get('room'));
  if (!roomCode || (!rooms.has(roomCode) && rooms.size >= MAX_ROOMS)) {
    socket.destroy();
    return;
  }
  websocketServer.handleUpgrade(request, socket, head, ws => {
    websocketServer.emit('connection', ws, request, roomCode, url.searchParams.get('resume') || '');
  });
});

websocketServer.on('connection', (ws, _request, roomCode, resumeToken) => {
  const room = roomFor(roomCode);
  ws.alive = true;
  ws.on('pong', () => { ws.alive = true; });
  let inputWindow = Date.now();
  let inputCount = 0;
  room.claim(ws, resumeToken);
  ws.on('message', data => {
    try {
      if (Date.now() - inputWindow >= 1000) { inputWindow = Date.now(); inputCount = 0; }
      if (++inputCount > 60) { ws.close(1008, 'input rate exceeded'); return; }
      const message = JSON.parse(data.toString());
      if (message?.type === 'input' && room.seats[ws.role]?.socket === ws) room.input(ws.role, message.value, message.seq, message.sent_msec);
    } catch {
      send(ws, { type: 'error', marker: MARKER, room: room.code, code: 'invalid_message' });
    }
  });
  ws.on('close', () => room.release(ws));
  ws.on('error', () => room.release(ws));
});

setInterval(() => {
  for (const ws of websocketServer.clients) {
    if (!ws.alive) { ws.terminate(); continue; }
    ws.alive = false;
    ws.ping();
  }
}, 15_000).unref();

let lastTick = Date.now();
let accumulated = 0;
let lastSnapshot = 0;
setInterval(() => {
  const now = Date.now();
  accumulated += Math.min(0.05, Math.max(0, (now - lastTick) / 1000));
  lastTick = now;
  while (accumulated >= 1 / TICK_HZ) {
    for (const room of rooms.values()) room.tick(1 / TICK_HZ, now);
    accumulated -= 1 / TICK_HZ;
  }
  if (now - lastSnapshot >= 1000 / SNAPSHOT_HZ) {
    lastSnapshot = now;
    for (const room of rooms.values()) room.broadcast();
  }
  for (const [code, room] of rooms) {
    const hasSockets = room.connected('left') || room.connected('right') || room.observers.size > 0;
    if (!hasSockets && now - room.lastActivity > ROOM_IDLE_MS) rooms.delete(code);
  }
}, 1000 / TICK_HZ).unref();

httpServer.listen(PORT, HOST, () => {
  console.log(JSON.stringify({ marker: MARKER, status: 'listening', host: HOST, port: httpServer.address().port, staticRoot: STATIC_ROOT }));
});

for (const signal of ['SIGINT', 'SIGTERM']) {
  process.on(signal, () => {
    for (const room of rooms.values()) {
      for (const side of ['left', 'right']) room.seats[side].socket?.close(1012, 'server restart');
      for (const observer of room.observers) observer.close(1012, 'server restart');
    }
    httpServer.close(() => process.exit(0));
    setTimeout(() => process.exit(1), 3000).unref();
  });
}
