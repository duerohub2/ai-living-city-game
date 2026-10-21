#!/usr/bin/env node
import { createServer } from 'node:http';
import { randomBytes } from 'node:crypto';
import { WebSocketServer, WebSocket } from 'ws';

const MARKER = 'ai-living-city-v1';
const HOST = process.env.HOST || '0.0.0.0';
const PORT = Number(process.env.PORT || 10000);
const SNAPSHOT_MS = 1000;
const MAX_PAYLOAD = 8192;
const MAX_CLIENTS = 200;
const MAX_ACTIONS_PER_MINUTE = 30;
const MAX_CATCHUP_HOURS = 6;

if (!Number.isInteger(PORT) || PORT < 0 || PORT > 65535) throw new Error('Invalid PORT');

const residents = [
  { id: 'mira', name: 'Mira Santoso', role: 'Pemilik kios bunga', location: 'Commercial', trust: 46, memory: 'Mira mengingat festival terakhir bersama warga.' },
  { id: 'raka', name: 'Raka Wijaya', role: 'Teknisi workshop', location: 'Industrial', trust: 31, memory: 'Raka menguji komponen baru untuk jalur produksi.' },
  { id: 'naya', name: 'Naya Chen', role: 'Kurator taman', location: 'Park District', trust: 58, memory: 'Naya menjaga taman sebagai ruang aman.' },
  { id: 'bimo', name: 'Bimo Ardi', role: 'Kurir distrik', location: 'Town Square', trust: 24, memory: 'Bimo memetakan rute baru menuju Civic District.' },
];

const city = {
  simulationHours: 8,
  tick: 0,
  lastTickAt: Date.now(),
  events: [{ type: 'festival', text: 'Festival lampion dimulai di Town Square.', at: Date.now() }],
  ledger: [],
  clients: new Map(),
  seenActions: new Map(),
};

function json(response, status, body) {
  response.writeHead(status, { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store', 'x-content-type-options': 'nosniff' });
  response.end(JSON.stringify(body));
}

function publicResidents() {
  return residents.map(({ id, name, role, location, trust, memory }) => ({ id, name, role, location, trust, memory }));
}

function snapshotFor(client) {
  const player = city.clients.get(client.id);
  return {
    type: 'state',
    marker: MARKER,
    seq: city.tick,
    simulation_hours: Number(city.simulationHours.toFixed(2)),
    residents: publicResidents(),
    player: player ? {
      id: player.id,
      display_name: player.displayName,
      location: player.location,
      wallet: player.wallet,
      reputation: player.reputation,
      inventory: player.inventory,
      needs: player.needs,
    } : null,
    events: city.events.slice(0, 12),
    ledger: city.ledger.filter(entry => entry.ownerId === player?.id).slice(0, 12),
  };
}

function send(ws, value) {
  if (ws.readyState !== WebSocket.OPEN || ws.bufferedAmount > 64 * 1024) return;
  ws.send(JSON.stringify(value));
}

function broadcast() {
  for (const ws of websocketServer.clients) {
    if (ws.readyState === WebSocket.OPEN && ws.clientId) send(ws, snapshotFor(city.clients.get(ws.clientId)));
  }
}

function addEvent(type, text) {
  city.events.unshift({ type, text, at: Date.now() });
  city.events = city.events.slice(0, 30);
}

function addLedger(ownerId, type, amount, reference) {
  city.ledger.unshift({ id: `tx_${Date.now()}_${randomBytes(3).toString('hex')}`, ownerId, type, amount, reference, at: Date.now() });
  city.ledger = city.ledger.slice(0, 300);
}

function cleanText(value, max = 32) {
  return typeof value === 'string' ? value.trim().slice(0, max) : '';
}

function validDistrict(value) {
  return ['Town Square', 'Residential', 'Commercial', 'Industrial', 'Civic', 'Park District'].includes(value);
}

function applyAction(client, message) {
  const player = city.clients.get(client.id);
  if (!player || typeof message !== 'object') return { ok: false, code: 'INVALID_SESSION' };
  const actionId = cleanText(message.actionId, 80);
  const actionType = cleanText(message.actionType, 24);
  if (!actionId || !actionType) return { ok: false, code: 'INVALID_ACTION' };
  const recent = city.seenActions.get(player.id) || new Set();
  if (recent.has(actionId)) return { ok: true, duplicate: true };
  if (recent.size >= 128) recent.clear();
  recent.add(actionId);
  city.seenActions.set(player.id, recent);

  if (actionType === 'travel') {
    const district = cleanText(message.district, 32);
    if (!validDistrict(district)) return { ok: false, code: 'INVALID_DESTINATION' };
    player.location = district;
    addEvent('movement', `${player.displayName} tiba di ${district}.`);
    return { ok: true };
  }

  if (actionType === 'work') {
    if (player.location !== 'Commercial') return { ok: false, code: 'WRONG_LOCATION' };
    const wage = 120;
    player.wallet += wage;
    player.reputation = Math.min(100, player.reputation + 1);
    player.needs.income = Math.min(100, player.needs.income + 22);
    addLedger(player.id, 'WAGE', wage, 'Commercial / shift toko');
    addEvent('economy', `${player.displayName} menyelesaikan shift toko.`);
    return { ok: true, reward: wage };
  }

  if (actionType === 'buy') {
    if (player.location !== 'Commercial' || player.wallet < 40) return { ok: false, code: 'INSUFFICIENT_FUNDS_OR_LOCATION' };
    player.wallet -= 40;
    player.inventory['Roti artisan'] = (player.inventory['Roti artisan'] || 0) + 1;
    addLedger(player.id, 'PURCHASE', -40, 'Commercial / Roti artisan');
    return { ok: true, item: 'Roti artisan' };
  }

  if (actionType === 'produce') {
    if (player.location !== 'Industrial' || player.wallet < 30) return { ok: false, code: 'INSUFFICIENT_FUNDS_OR_LOCATION' };
    player.wallet -= 30;
    player.inventory['Komponen kota'] = (player.inventory['Komponen kota'] || 0) + 1;
    addLedger(player.id, 'PRODUCTION', -30, 'Industrial / workshop');
    addEvent('business', `${player.displayName} menjalankan produksi workshop.`);
    return { ok: true, item: 'Komponen kota' };
  }

  if (actionType === 'social') {
    if (!['Town Square', 'Residential', 'Park District'].includes(player.location)) return { ok: false, code: 'WRONG_LOCATION' };
    player.reputation = Math.min(100, player.reputation + 2);
    player.needs.social = Math.min(100, player.needs.social + 6);
    addEvent('social', `${player.displayName} membangun relasi baru di ${player.location}.`);
    return { ok: true };
  }

  if (actionType === 'rest') {
    player.needs.rest = Math.min(100, player.needs.rest + 12);
    player.needs.recreation = Math.min(100, player.needs.recreation + 10);
    return { ok: true };
  }

  return { ok: false, code: 'ACTION_NOT_ALLOWED' };
}

function advanceSimulation() {
  const now = Date.now();
  const elapsedHours = Math.min(MAX_CATCHUP_HOURS, Math.max(0, (now - city.lastTickAt) / 3600000));
  city.lastTickAt = now;
  city.simulationHours += elapsedHours;
  city.tick += 1;
  for (const player of city.clients.values()) {
    player.needs.rest = Math.max(0, player.needs.rest - elapsedHours * 2);
    player.needs.income = Math.min(100, player.needs.income + elapsedHours * 2);
    const passive = Math.floor(elapsedHours * 9);
    if (passive > 0) {
      player.wallet += passive;
      addLedger(player.id, 'OFFLINE_PROGRESS', passive, `${elapsedHours.toFixed(2)} jam catch-up`);
    }
  }
  if (city.tick % 30 === 0) addEvent('simulation', 'Tick kota selesai; kebutuhan AI dan event terjadwal diperbarui.');
  broadcast();
}

const httpServer = createServer((request, response) => {
  const url = new URL(request.url || '/', `http://${request.headers.host || 'localhost'}`);
  if (url.pathname === '/healthz') {
    json(response, 200, { ok: true, marker: MARKER, clients: city.clients.size, simulationHours: Number(city.simulationHours.toFixed(2)), uptime: process.uptime() });
    return;
  }
  if (url.pathname === '/api/world') {
    json(response, 200, { data: { marker: MARKER, simulationHours: city.simulationHours, residents: publicResidents(), events: city.events.slice(0, 12) }, error: null, requestId: `req_${Date.now()}` });
    return;
  }
  json(response, 404, { data: null, error: { code: 'NOT_FOUND', message: 'Route tidak ditemukan.' }, requestId: `req_${Date.now()}` });
});

const websocketServer = new WebSocketServer({ noServer: true, maxPayload: MAX_PAYLOAD });
httpServer.on('upgrade', (request, socket, head) => {
  const url = new URL(request.url || '/', `http://${request.headers.host || 'localhost'}`);
  if (url.pathname !== '/ws' || websocketServer.clients.size >= MAX_CLIENTS) { socket.destroy(); return; }
  websocketServer.handleUpgrade(request, socket, head, ws => websocketServer.emit('connection', ws, url));
});

websocketServer.on('connection', (ws, url) => {
  const id = `resident_${randomBytes(6).toString('hex')}`;
  const player = {
    id,
    displayName: cleanText(url.searchParams.get('name'), 24) || 'Penghuni baru',
    location: 'Town Square',
    wallet: 480,
    reputation: 12,
    inventory: { 'Roti artisan': 2, 'Kartu transit': 1 },
    needs: { social: 62, rest: 78, income: 44, recreation: 56, work: 68 },
  };
  city.clients.set(id, player);
  city.seenActions.set(id, new Set());
  ws.clientId = id;
  ws.actionWindowAt = Date.now();
  ws.actionCount = 0;
  send(ws, { type: 'welcome', marker: MARKER, protocol: 'city-v1', residentId: id, authoritative: true, limits: { maxActionPerMinute: MAX_ACTIONS_PER_MINUTE } });
  send(ws, snapshotFor(player));
  addEvent('arrival', `${player.displayName} memasuki kota.`);

  ws.on('message', raw => {
    if (Date.now() - ws.actionWindowAt >= 60000) { ws.actionWindowAt = Date.now(); ws.actionCount = 0; }
    if (++ws.actionCount > MAX_ACTIONS_PER_MINUTE) { send(ws, { type: 'error', marker: MARKER, code: 'RATE_LIMITED' }); return; }
    try {
      const message = JSON.parse(raw.toString());
      if (message?.type !== 'action') { send(ws, { type: 'error', marker: MARKER, code: 'ACTION_REQUIRED' }); return; }
      const result = applyAction({ id }, message);
      send(ws, { type: 'action_result', marker: MARKER, actionId: cleanText(message.actionId, 80), ...result });
      if (result.ok) broadcast();
    } catch {
      send(ws, { type: 'error', marker: MARKER, code: 'INVALID_JSON' });
    }
  });
  ws.on('close', () => { city.clients.delete(id); city.seenActions.delete(id); addEvent('departure', `${player.displayName} meninggalkan kota.`); });
});

setInterval(advanceSimulation, SNAPSHOT_MS).unref();
httpServer.listen(PORT, HOST, () => console.log(JSON.stringify({ ok: true, marker: MARKER, host: HOST, port: PORT })));
