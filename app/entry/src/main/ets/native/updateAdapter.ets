/**
 * "检查更新"的出口（FR-28）。
 *
 * **有意不查 API**：应用的仓库是 **private**，匿名访问 releases API 只会拿到 404
 * （2026-09-29 实测：`curl https://api.github.com/repos/…/releases/latest` → `http=404`），
 * 也就是说"应用内自动比对版本"要么得把仓库公开、要么得往安装包里塞一个访问令牌——
 * 后者是**凭据进产物**，本项目明令不做。
 *
 * 故这里的"检查更新"= **把发布页交给系统浏览器**：用户在浏览器里（通常已登录）自己看有没有新版本。
 * 这条路与仓库可见性无关，也不需要任何凭据。取舍与后续选项见 `docs/specs/update-check.md`。
 *
 * 失败原样抛出（模拟器上可能没有浏览器），由调用方提示"请手动访问发布页"。
 */

import { common } from '@kit.AbilityKit';
import { openExternalUrl } from './linkAdapter';

/** 项目的发布页。仓库若将来转为公开，这里是唯一要改的地方 */
const RELEASES_URL: string = 'https://github.com/HanyuNol/learnX-harmony/releases';

/** 用系统浏览器打开项目的发布页 */
export async function openReleasesPage(context: common.UIAbilityContext): Promise<void> {
  await openExternalUrl(context, RELEASES_URL);
}
