/**
 * 错误四分类的单元测试。
 *
 * 覆盖 spec §5 第 4 项：为四类输入断言归类正确，且**互不串台**——
 * 尤其网络不可达不得被归为应用缺陷（NFR-NET）。
 */

import { describe, expect, it } from '@ohos/hypium';
import { FailReason, AuthError } from '../main/ets/model/auth';
import {
  apiChanged,
  authFailed,
  firstFailure,
  fromStatusCode,
  networkUnreachable,
  normalize,
  parseFailed
} from '../main/ets/common/errors';

/** 模拟平台 BusinessError 的最小形状 */
interface FakeBusinessError {
  code: number;
  message: string;
}

export default function errorsTest() {
  describe('errors', () => {

    it('扇出全失败时必须抛"已归一的错误"：裸 Error 会让四分类退化成解析失败', 0, () => {
      // 这条钉住 2026-09-28 审查的 🔴：作业/文件仓储原先在全失败时抛 `new Error(...)`，
      // 而 normalize 对**没有平台错误码**的异常一律归为 PARSE_FAILED——
      // 于是"登录失效/断网"被显示成"服务端返回的内容无法识别"。
      const bare: AuthError = normalize(new Error('全部课程的文件都加载失败'), '加载文件');
      expect(bare.reason).assertEqual(FailReason.PARSE_FAILED);

      // 正确做法：把单课里已归一的错误交给 firstFailure，全失败时抛它
      const kept: AuthError = firstFailure([authFailed('会话已失效')], '加载文件');
      expect(kept.reason).assertEqual(FailReason.AUTH_FAILED);
      expect(kept.reason === FailReason.PARSE_FAILED).assertFalse();
    });

    it('firstFailure 空列表也要给"已归一的"错误，绝不返回裸 Error', 0, () => {
      const fallback: AuthError = firstFailure([], '加载文件');
      expect(fallback instanceof AuthError).assertTrue();
      expect(fallback.reason === FailReason.PARSE_FAILED).assertFalse();
    });

    it('多个失败时取第一个（保留该次失败的分类）', 0, () => {
      const first: AuthError = firstFailure(
        [networkUnreachable('断网'), apiChanged('语义变更')], '加载文件');
      expect(first.reason).assertEqual(FailReason.NETWORK_UNREACHABLE);
    });

    it('网络类错误码应归为网络不可达', 0, () => {
      const timeout: FakeBusinessError = { code: 2300028, message: 'timeout' };
      const cannotResolve: FakeBusinessError = { code: 2300006, message: 'resolve failed' };
      const cannotConnect: FakeBusinessError = { code: 2300007, message: 'connect failed' };

      expect(normalize(timeout, 'GET x').reason).assertEqual(FailReason.NETWORK_UNREACHABLE);
      expect(normalize(cannotResolve, 'GET x').reason).assertEqual(FailReason.NETWORK_UNREACHABLE);
      expect(normalize(cannotConnect, 'GET x').reason).assertEqual(FailReason.NETWORK_UNREACHABLE);
    });

    it('401/403 应归为认证失败，而非网络或应用缺陷', 0, () => {
      expect(fromStatusCode(401, 'x').reason).assertEqual(FailReason.AUTH_FAILED);
      expect(fromStatusCode(403, 'x').reason).assertEqual(FailReason.AUTH_FAILED);
    });

    it('其余非 2xx 应归为接口语义变更', 0, () => {
      expect(fromStatusCode(404, 'x').reason).assertEqual(FailReason.API_CHANGED);
      expect(fromStatusCode(500, 'x').reason).assertEqual(FailReason.API_CHANGED);
    });

    it('已是 AuthError 的应原样透传，不丢失分类', 0, () => {
      const original: AuthError = apiChanged('页面结构变了');
      const normalized: AuthError = normalize(original, '外层');
      expect(normalized.reason).assertEqual(FailReason.API_CHANGED);
      expect(normalized.detail).assertEqual('页面结构变了');
    });

    it('未归类的平台错误码应归为接口语义变更并保留原因', 0, () => {
      const unknown: FakeBusinessError = { code: 2300999, message: 'unknown' };
      expect(normalize(unknown, 'GET x').reason).assertEqual(FailReason.API_CHANGED);
    });

    it('无错误码的异常应归为解析失败', 0, () => {
      expect(normalize(new Error('bad payload'), '解析').reason).assertEqual(FailReason.PARSE_FAILED);
    });

    it('四类构造器应产出互不相同的分类', 0, () => {
      const reasons: FailReason[] = [
        networkUnreachable('a').reason,
        authFailed('b').reason,
        apiChanged('c').reason,
        parseFailed('d').reason
      ];
      const unique: FailReason[] = [];
      for (const reason of reasons) {
        if (!unique.includes(reason)) {
          unique.push(reason);
        }
      }
      expect(unique.length).assertEqual(4);
    });
  });
}
