// 通过 GitHub Git Data API (api.github.com) 推送本地提交历史
// 用途：当本机到 github.com:443 的直连被阻断、而 api.github.com 仍可达时，
// 用它把本地提交原样推上去。见 docs/OPERATIONS.md §6.2。
//
// 特性：提交 message 取自 `git cat-file commit` 的原始字节，因此远端 SHA 与本地逐位一致，
// 不会制造"远端历史被改写"的隐患。
//
// 用法：GH_TOKEN="$(gh auth token)" node scripts/push-via-api.mjs
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

// 仓库根 = 本脚本所在目录的上一级
const REPO_DIR = resolve(dirname(fileURLToPath(import.meta.url)), '..');

const REPO = 'HanyuNol/learnX-harmony';
const API = 'https://api.github.com';
const TOKEN = process.env.GH_TOKEN;

if (!TOKEN) {
  console.error('缺少 GH_TOKEN。用法：GH_TOKEN="$(gh auth token)" node scripts/push-via-api.mjs');
  process.exit(1);
}

const git = (args, encoding = 'utf8') =>
  execFileSync('git', args, { cwd: REPO_DIR, encoding, maxBuffer: 64 * 1024 * 1024 });

async function api(method, path, body) {
  const res = await fetch(API + path, {
    method,
    headers: {
      Authorization: `Bearer ${TOKEN}`,
      Accept: 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
      'User-Agent': 'learnx-harmony-push',
      ...(body ? { 'Content-Type': 'application/json' } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`${method} ${path} -> ${res.status}\n${text.slice(0, 400)}`);
  return text ? JSON.parse(text) : null;
}

const AUTHOR = {
  name: git(['config', 'user.name']).trim(),
  email: git(['config', 'user.email']).trim(),
};

// 空仓库无法直接写 Git 数据（409 Git Repository is empty）。
// 先用 Contents API 建一个占位提交让仓库非空，稍后把 main 强制指向真实提交，
// 占位提交被孤立、不进入历史。
async function ensureRepoNonEmpty() {
  try {
    await api('GET', `/repos/${REPO}/git/ref/heads/main`);
    console.log('仓库已有 main 分支，跳过占位提交');
    return;
  } catch (e) {
    if (!/409|404/.test(String(e.message))) throw e;
  }
  console.log('空仓库：创建占位提交…');
  await api('PUT', `/repos/${REPO}/contents/.init-placeholder`, {
    message: 'chore: 初始化仓库',
    content: Buffer.from('placeholder\n', 'utf8').toString('base64'),
  });
  console.log('占位提交已创建');
}

await ensureRepoNonEmpty();

// 本地提交，从旧到新
const logRaw = git(['log', '--reverse', '--format=%H%x00%s%x00%aI']).trim();
const commits = logRaw
  .split('\n')
  .filter(Boolean)
  .map(line => {
    const [sha, subject, date] = line.split('\0');
    return { sha, subject, date };
  });

console.log(`本地提交数：${commits.length}`);
for (const c of commits) console.log(`  ${c.sha.slice(0, 8)} ${c.subject}`);

// 本地 blob sha -> GitHub blob sha，避免重复上传
const blobCache = new Map();

async function uploadBlob(localSha) {
  if (blobCache.has(localSha)) return blobCache.get(localSha);
  const buf = git(['cat-file', 'blob', localSha], 'buffer');
  const { sha } = await api('POST', `/repos/${REPO}/git/blobs`, {
    content: buf.toString('base64'),
    encoding: 'base64',
  });
  blobCache.set(localSha, sha);
  return sha;
}

let parentSha = null;
let i = 0;
for (const c of commits) {
  i++;
  // git ls-tree -r <sha>  -> "<mode> <type> <sha>\t<path>"
  const lines = git(['ls-tree', '-r', c.sha]).trim().split('\n').filter(Boolean);
  const tree = [];
  for (const line of lines) {
    const [meta, path] = line.split('\t');
    const [mode, type, lsha] = meta.split(/\s+/);
    if (type !== 'blob') throw new Error(`非 blob 条目：${line}`);
    tree.push({ path, mode, type: 'blob', sha: await uploadBlob(lsha) });
  }
  console.log(`[${i}/${commits.length}] ${c.subject}：${tree.length} 个文件`);

  const treeRes = await api('POST', `/repos/${REPO}/git/trees`, { tree });

  // 必须用提交对象的原始字节取 message：`git log --format=%B` 会多带一个换行，
  // 导致提交 SHA 与本地不一致（tree 完全相同，仅 message 尾部差一个 \n）。
  const rawObject = git(['cat-file', 'commit', c.sha]);
  const message = rawObject.slice(rawObject.indexOf('\n\n') + 2);
  const author = { ...AUTHOR, date: c.date };
  const commitRes = await api('POST', `/repos/${REPO}/git/commits`, {
    message,
    tree: treeRes.sha,
    author,
    committer: author,
    parents: parentSha ? [parentSha] : [],
  });
  console.log(`    -> 远端提交 ${commitRes.sha.slice(0, 8)}`);
  parentSha = commitRes.sha;
}

// 更新/创建 main 分支引用（强制指向真实历史，丢弃占位提交）
try {
  await api('POST', `/repos/${REPO}/git/refs`, {
    ref: 'refs/heads/main',
    sha: parentSha,
  });
  console.log('已创建 refs/heads/main');
} catch (e) {
  if (String(e.message).includes('422')) {
    await api('PATCH', `/repos/${REPO}/git/refs/heads/main`, { sha: parentSha, force: true });
    console.log('已强制更新 refs/heads/main（占位提交已孤立）');
  } else {
    throw e;
  }
}

// 立即回收被孤立的占位提交，避免它继续挂在仓库对象里
await api('DELETE', `/repos/${REPO}/git/refs/heads/.init`).catch(() => {});

// 复核
const remote = await api('GET', `/repos/${REPO}/commits?sha=main`);
console.log('\n远端历史（新->旧）：');
for (const c of remote) {
  console.log(`  ${c.sha.slice(0, 8)} ${c.commit.message.split('\n')[0]}`);
}
