#!/usr/bin/env node
/**
 * 版本号同步：把 `VERSION`（版本唯一来源，见 docs/CONTRIBUTING.md）写进应用包。
 *
 * 为什么需要它：`docs/CONTRIBUTING.md` 声明"版本号唯一来源是根 `VERSION`，
 * 构建把它注入 `app/AppScope/app.json5`"，但此前**没有任何脚本真的读 `VERSION`**
 * （2026-09-28 发版时发现：文档写了、实现没有）——于是版本号实际靠手改，两处极易不同步。
 *
 * 用法：改完 `VERSION` 后跑 `node scripts/sync-version.mjs`，它会：
 *   1. 校验 VERSION 是 `X.Y.Z`；
 *   2. 按 `major×1000000 + minor×1000 + patch` 推出 versionCode
 *      （HarmonyOS 要求升级包 versionCode 严格递增）；
 *   3. 把两者写进 `app/AppScope/app.json5`（只改这两行，不动其它字段与格式）。
 *
 * 退出码非 0 表示没写成（格式不对、文件里找不到对应行）——**不静默**。
 */

import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const VERSION_FILE = join(root, 'VERSION');
const APP_FILE = join(root, 'app/AppScope/app.json5');

const version = readFileSync(VERSION_FILE, 'utf8').trim();
const matched = /^(\d+)\.(\d+)\.(\d+)$/.exec(version);
if (matched === null) {
  console.error(`VERSION 不是 X.Y.Z 形态：${JSON.stringify(version)}`);
  process.exit(1);
}
const [, major, minor, patch] = matched;
const versionCode = Number(major) * 1000000 + Number(minor) * 1000 + Number(patch);

let app = readFileSync(APP_FILE, 'utf8');
const codePattern = /"versionCode":\s*\d+,/;
const namePattern = /"versionName":\s*"[^"]*"/;
if (!codePattern.test(app) || !namePattern.test(app)) {
  console.error(`app.json5 里找不到 versionCode / versionName 行：${APP_FILE}`);
  process.exit(1);
}
app = app.replace(codePattern, `"versionCode": ${versionCode},`);
app = app.replace(namePattern, `"versionName": "${version}"`);
writeFileSync(APP_FILE, app);

console.log(`版本已同步：VERSION=${version} → versionName=${version}、versionCode=${versionCode}`);
