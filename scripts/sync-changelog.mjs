/**
 * 把仓库根的 `CHANGELOG.md` 同步进打包资源（`resources/rawfile/CHANGELOG.md`）。
 *
 * ## 为什么需要它
 *
 * "更新日志"页（FR-28）读的是**包内**那一份：应用要能离线看到"这个版本改了什么"，
 * 而仓库对匿名用户不可见（private），联网取根本取不到。
 * 于是仓库根的那份是唯一真源，rawfile 里那份是**构建产物**——两者必须由脚本对齐，
 * 否则会出现"日志里少了刚发的这一版"（不报错，只是少了一段，很难注意到）。
 *
 * 与 `sync-version.mjs` 同一性质：**改版/发版前必跑**。
 *
 * 用法：`node scripts/sync-changelog.mjs`
 */

import { copyFileSync, readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const source = join(root, 'CHANGELOG.md');
const target = join(root, 'app', 'entry', 'src', 'main', 'resources', 'rawfile', 'CHANGELOG.md');

const content = readFileSync(source, 'utf8');
if (content.trim().length === 0) {
  console.error('✗ CHANGELOG.md 是空的，拒绝同步（空日志会让更新日志页显示"读不到"）');
  process.exit(1);
}

// 统一成 LF：rawfile 会原样进包，CRLF 会让 Markdown 的围栏/标题判定多出尾部 \r
writeFileSync(target, content.replace(/\r\n/g, '\n'), 'utf8');

const versions = content.match(/^## /gm)?.length ?? 0;
console.log(`✓ 已同步 CHANGELOG.md → resources/rawfile/CHANGELOG.md（${content.length} 字符，${versions} 个版本段）`);
