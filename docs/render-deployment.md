# AI Living City — deployment boundary

Proyek ini memiliki dua jalur deployment:

- **Client game**: Godot Web export yang dapat disajikan sebagai static site di Vercel atau Render Static Site.
- **City service**: `server/city_server.mjs`, Node.js + `ws`, untuk health check, snapshot kota, aksi terbatas, idempotency key, rate limit, dan simulation tick. Service ini cocok sebagai Render Web Service.

## Render Web Service

Gunakan repository proyek ini, branch `main`, region `Singapore`, runtime `Node`, dan konfigurasi berikut:

```text
Build Command: pnpm install --dir server --frozen-lockfile
Start Command: node server/city_server.mjs
Health Check Path: /healthz
```

Render mengisi `PORT` secara otomatis. `HOST` default service adalah `0.0.0.0`. Aksi client yang didukung service city adalah `travel`, `work`, `buy`, `produce`, `social`, dan `rest`; seluruh perubahan state divalidasi server-side dan aksi berulang dengan `actionId` diabaikan.

## Batasan prototype

Service ini adalah boundary authoritative yang siap diuji, bukan klaim production readiness. State saat ini berada di memori proses; restart menghapus penghuni sementara dan ledger. Untuk rilis publik PRD, pindahkan state kritis ke PostgreSQL/Supabase, tambahkan authentication, RLS, persistent ledger, scheduled worker, backup/restore, observability, dan WSS dengan origin allowlist.

Client saat ini tetap menggunakan simulasi lokal agar vertical slice dapat dimainkan tanpa endpoint eksternal. Integrasi WebSocket dapat ditambahkan pada adapter network tanpa memindahkan aturan ekonomi ke frontend.
