#!/usr/bin/env node
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const skipped = new Set(['.git', '.godot', 'dist', 'test-output', 'captures']);
function walk(directory) {
  return readdirSync(directory, { withFileTypes: true }).flatMap(entry => {
    const path = join(directory, entry.name);
    return entry.isDirectory() ? (skipped.has(entry.name) ? [] : walk(path)) : [relative(root, path)];
  });
}
const files = walk(root);
const sources = new Map(files
  .filter(path => !/^(test|tools)\//.test(path) && /\.(gd|gdshader|tscn|tres|godot)$/.test(path))
  .map(path => [path, readFileSync(join(root, path), 'utf8')]));
const classes = new Map();
for (const [path, source] of sources) {
  const match = source.match(/^class_name (\w+)/m);
  if (match) classes.set(match[1], path);
}
const reached = new Set();
const referencedAssets = new Set();
const pending = ['project.godot'];
while (pending.length) {
  const path = pending.pop();
  if (reached.has(path)) continue;
  reached.add(path);
  const source = sources.get(path);
  assert.ok(source !== undefined, `Missing runtime source: ${path}`);
  for (const match of source.matchAll(/["']\*?res:\/\/([^"']+)["']/g)) {
    const target = match[1];
    assert.ok(existsSync(join(root, target)), `Missing resource ${target} referenced by ${path}`);
    if (sources.has(target)) pending.push(target);
    if (target.startsWith('assets/template/') && !sources.has(target)) referencedAssets.add(target);
  }
  for (const [name, target] of classes) {
    if (new RegExp(`\\b${name}\\b`).test(source)) pending.push(target);
  }
}
for (const path of sources.keys()) assert.ok(reached.has(path), `Unreachable runtime source: ${path}`);

const manifest = JSON.parse(readFileSync(join(root, 'assets.lock.json'), 'utf8'));
for (const [path, entry] of Object.entries(manifest.assets)) {
  assert.ok(referencedAssets.has(path), `Unreferenced manifest asset: ${path}`);
  const bytes = readFileSync(join(root, path));
  assert.equal(bytes.length, entry.size, `Asset size changed: ${path}`);
  assert.equal(`sha256:${createHash('sha256').update(bytes).digest('hex')}`, entry.sha256, `Asset hash changed: ${path}`);
}
for (const path of referencedAssets) assert.ok(manifest.assets[path], `Resource absent from manifest: ${path}`);
for (const path of files) {
  if (path.startsWith('assets/template/') && /\.(png|jpe?g|webp|svg|ogg|wav|mp3|m4a|ttf|otf|woff2?)$/i.test(path)) {
    assert.ok(manifest.assets[path], `Stranded media: ${path}`);
  }
  if (/\.(import|uid)$/.test(path)) {
    const source = path.replace(/\.(import|uid)$/, '');
    assert.ok(existsSync(join(root, source)), `Orphaned sidecar: ${path}`);
  }
}
console.log(`[resource-audit] PASS: ${reached.size} reachable runtime sources, ${referencedAssets.size} referenced and verified assets, no orphaned sidecars`);
