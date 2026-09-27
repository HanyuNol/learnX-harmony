/**
 * 通知纯逻辑的单元测试（notices spec §5 第 1–4 项）。
 *
 * 覆盖：响应解析（Base64 正文、HTML 实体、字段缺失退让、结构不符抛错）、
 * 两次批次合并后的排序、摘要去标签与截断、未读筛选。
 */

import { describe, expect, it } from '@ohos/hypium';
import { Notice, NoticeFilter, filterNotices, sortNotices, summarize } from '../main/ets/model/notice';
import { parseNoticeList } from '../main/ets/network/parseNotice';

/** 上游学生形态的最小样本：正文是 Base64（"你好" 的 UTF-8） */
const ONE_NOTICE: string = '{"result":"success","object":{"aaData":[{' +
  '"ggid":"gg1","bt":"关于选课 &amp; 退课","ggnr":"5L2g5aW9","sfyd":"否",' +
  '"fbrxm":"教务","fbsj":"2026-09-01 10:00:00","sfqd":"1","fjmc":"附件.pdf"}]}}';

function notice(id: string, publishTime: number, hasRead: boolean): Notice {
  return new Notice(id, 'c1', '课程甲', '标题', '正文', hasRead, false, publishTime, '发布者', 'url', '');
}

export default function noticeTest() {
  describe('notice', () => {

    describe('排序', () => {

      it('应按发布时间倒序，同一时间按 id 倒序', 0, () => {
        const sorted: Notice[] = sortNotices([
          notice('a', 100, false), notice('c', 300, false),
          notice('b', 300, false), notice('d', 200, false)]);
        expect(sorted[0].id).assertEqual('c');
        expect(sorted[1].id).assertEqual('b');
        expect(sorted[2].id).assertEqual('d');
        expect(sorted[3].id).assertEqual('a');
      });
    });

    describe('摘要', () => {

      it('应去标签、压缩空白并截断', 0, () => {
        expect(summarize('<p>第一段</p>\n\n  <b>第二段</b>')).assertEqual('第一段 第二段');
        const long: string = '啊'.repeat(100);
        const short: string = summarize(long);
        expect(short.length < long.length).assertTrue();
      });

      it('空正文应返回空串，而不是抛错', 0, () => {
        expect(summarize('')).assertEqual('');
      });
    });

    describe('未读筛选', () => {

      it('未读筛选只留未读项，全部筛选原样返回', 0, () => {
        const items: Notice[] = [notice('a', 1, true), notice('b', 2, false)];
        expect(filterNotices(items, NoticeFilter.UNREAD).length).assertEqual(1);
        expect(filterNotices(items, NoticeFilter.UNREAD)[0].id).assertEqual('b');
        expect(filterNotices(items, NoticeFilter.ALL).length).assertEqual(2);
      });
    });

    describe('响应解析', () => {

      it('应解出字段、Base64 正文与 HTML 实体', 0, () => {
        const list: Notice[] = parseNoticeList(ONE_NOTICE, 'c1', '课程甲');
        expect(list.length).assertEqual(1);
        expect(list[0].id).assertEqual('gg1');
        expect(list[0].title).assertEqual('关于选课 & 退课');
        expect(list[0].content).assertEqual('你好');
        expect(list[0].hasRead).assertFalse();
        expect(list[0].markedImportant).assertTrue();
        // url 是客户端按 (courseId, noticeId) 拼的，响应里没有该字段
        expect(list[0].url.includes('beforeViewXs')).assertTrue();
        expect(list[0].url.includes('id=gg1')).assertTrue();
        expect(list[0].publisher).assertEqual('教务');
        expect(list[0].attachmentName).assertEqual('附件.pdf');
        expect(list[0].courseId).assertEqual('c1');
        expect(list[0].courseName).assertEqual('课程甲');
        expect(list[0].publishTime > 0).assertTrue();
      });

      it('空列表是合法结果', 0, () => {
        expect(parseNoticeList('{"result":"success","object":{"aaData":[]}}', 'c1', '甲').length).assertEqual(0);
      });

      it('退让容器 resultsList 可用，且字段缺失的项不应让整批失败', 0, () => {
        const list: Notice[] = parseNoticeList('{"result":"success","object":{"resultsList":[{"ggid":"x"}]}}', 'c1', '甲');
        expect(list.length).assertEqual(1);
        expect(list[0].title).assertEqual('');
        expect(list[0].hasRead).assertFalse();
        expect(list[0].publishTime).assertEqual(0);
      });

      it('坏 JSON 或缺少结果容器都应抛错', 0, () => {
        const bad: string[] = ['[', '{"result":"success","object":{}}',
          '{"result":"success","object":{"aaData":{}}}', '{"result":"fail","object":{"aaData":[]}}'];
        bad.forEach((body: string) => {
          let threw: boolean = false;
          try {
            parseNoticeList(body, 'c1', '甲');
          } catch (err) {
            threw = true;
          }
          expect(threw).assertTrue();
        });
      });
    });
  });
}
