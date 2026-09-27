#!/usr/bin/env node
/**
 * 文案键一致性检查（提交前门，见 docs/specs/ui-shell.md §5 第 2 项）。
 *
 * 为什么需要它：`$r('app.string.' + key)` 传变量时是**运行时**解析资源 id，
 * 写错键不会编译报错、也不会回落，只会显示不出文案；而缺 `en_US` 键同样不报错，
 * 系统静默回落 `base`（中文），表现为"英文界面里混着中文"。
 * 编译期给不了这两类保证，所以由本脚本兜住：
 *
 *   1. `base` 与 `en_US` 两份 string.json 的键集合必须一致（缺一即漏翻译）；
 *   2. 代码里声明的文案键（common/texts.ets 的 static readonly 字符串）必须都在两份里存在。
 *
 * 退出码非 0 即视为不通过。用法：node scripts/check-l10n.mjs
 */

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const BASE = join(root, 'app/entry/src/main/resources/base/element/string.json');
const EN = join(root, 'app/entry/src/main/resources/en_US/element/string.json');
const TEXTS = join(root, 'app/entry/src/main/ets/common/texts.ets');

/** 读取 string.json 的键集合 */
function readKeys(path) {
  const parsed = JSON.parse(readFileSync(path, 'utf8'));
  if (!Array.isArray(parsed.string)) {
    throw new Error(`${path} 结构不符：缺少 string 数组`);
  }
  return new Set(parsed.string.map((entry) => entry.name));
}

/**
 * 从 texts.ets 抽出声明的键值。
 * 只认 `static readonly NAME: string = 'literal';` 这一种写法——约定如此，
 * 换成别的写法（拼接、计算）本脚本会漏检，故 texts.ets 里只允许字面量。
 */
function readDeclaredKeys(path) {
  const source = readFileSync(path, 'utf8');
  const keys = new Set();
  const pattern = /static\s+readonly\s+\w+\s*:\s*string\s*=\s*'([^']*)'/g;
  let match;
  while ((match = pattern.exec(source)) !== null) {
    if (match[1].length > 0) {
      keys.add(match[1]);
    }
  }
  return keys;
}

const problems = [];

const baseKeys = readKeys(BASE);
const enKeys = readKeys(EN);
const declared = readDeclaredKeys(TEXTS);

// 1) 两份资源键集合一致
for (const key of baseKeys) {
  if (!enKeys.has(key)) {
    problems.push(`en_US 缺少键（会回落成中文）：${key}`);
  }
}
for (const key of enKeys) {
  if (!baseKeys.has(key)) {
    problems.push(`base 缺少键（en_US 多出）：${key}`);
  }
}

// 2) 代码声明的键必须都在资源里
for (const key of declared) {
  if (!baseKeys.has(key)) {
    problems.push(`代码引用的键在 base 资源里不存在：${key}`);
  }
  if (!enKeys.has(key)) {
    problems.push(`代码引用的键在 en_US 资源里不存在：${key}`);
  }
}

// 3) 反向提示：资源里定义了但代码没用到的键（不算失败，但值得清理）
const unused = [...baseKeys].filter((key) => !declared.has(key));

if (problems.length > 0) {
  console.error('文案键检查未通过：');
  for (const problem of problems) {
    console.error(`  ✗ ${problem}`);
  }
  console.error(`\nbase ${baseKeys.size} 键 / en_US ${enKeys.size} 键 / 代码声明 ${declared.size} 键`);
  process.exit(1);
}

console.log(`文案键检查通过：base ${baseKeys.size} 键、en_US ${enKeys.size} 键、代码声明 ${declared.size} 键，键集合一致。`);
if (unused.length > 0) {
  console.log(`提示（不算失败）：资源里未被 texts.ets 声明的键 ${unused.length} 个 —— 多为框架键，若非框架键请清理：${unused.join(', ')}`);
}
