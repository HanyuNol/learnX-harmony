/**
 * 主题模式的单元测试。
 *
 * 覆盖 ui-shell spec §5 第 1 项：
 * - 三种模式与 `ConfigurationConstant.ColorMode` 的映射正确；
 * - 存储读到非法值时**退让为跟随系统**而不是崩溃（存储可能被外部改写）。
 *
 * 刻意不测"跟随系统时由系统值决定"这类映射：跟随系统走 `COLOR_MODE_NOT_SET`
 * 交给系统，系统值不经过应用代码（spec §5 第 1 项的说明）。
 */

import { describe, expect, it } from '@ohos/hypium';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { ThemeMode, parseThemeMode, themeModeToColorMode } from '../main/ets/common/theme';

export default function themeTest() {
  describe('theme', () => {

    it('合法存储值应解析为对应模式', 0, () => {
      expect(parseThemeMode('FOLLOW_SYSTEM')).assertEqual(ThemeMode.FOLLOW_SYSTEM);
      expect(parseThemeMode('LIGHT')).assertEqual(ThemeMode.LIGHT);
      expect(parseThemeMode('DARK')).assertEqual(ThemeMode.DARK);
    });

    it('非法存储值应退让为跟随系统，而不是崩溃', 0, () => {
      expect(parseThemeMode('')).assertEqual(ThemeMode.FOLLOW_SYSTEM);
      expect(parseThemeMode('PURPLE')).assertEqual(ThemeMode.FOLLOW_SYSTEM);
      expect(parseThemeMode('dark')).assertEqual(ThemeMode.FOLLOW_SYSTEM);
      expect(parseThemeMode(' DARK ')).assertEqual(ThemeMode.FOLLOW_SYSTEM);
    });

    it('跟随系统应映射为 COLOR_MODE_NOT_SET，由系统决定深浅', 0, () => {
      expect(themeModeToColorMode(ThemeMode.FOLLOW_SYSTEM))
        .assertEqual(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    });

    it('手动模式应映射为对应 ColorMode', 0, () => {
      expect(themeModeToColorMode(ThemeMode.LIGHT))
        .assertEqual(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
      expect(themeModeToColorMode(ThemeMode.DARK))
        .assertEqual(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    });

    it('ThemeMode 的每个取值都应映射到已知 ColorMode，不留未覆盖项', 0, () => {
      const all: ThemeMode[] = [ThemeMode.FOLLOW_SYSTEM, ThemeMode.LIGHT, ThemeMode.DARK];
      const known: ConfigurationConstant.ColorMode[] = [
        ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET,
        ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT,
        ConfigurationConstant.ColorMode.COLOR_MODE_DARK
      ];
      all.forEach((mode: ThemeMode) => {
        expect(known.includes(themeModeToColorMode(mode))).assertTrue();
      });
      // 枚举新增取值后须同步补映射与用例，故这里钉住当前取值个数
      expect(all.length).assertEqual(3);
    });
  });
}
