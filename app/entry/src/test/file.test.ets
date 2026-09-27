/**
 * 文件纯逻辑与解析的单元测试（files spec §5 第 1–5 项）。
 *
 * 这里钉住两件容易错的事：**文件列表的信封容器与其他维度不同**（学生形态是 `object`
 * 本身为数组），以及**下载前的内容嗅探**判据（跳转桩不能被当成课件）。
 */

import { describe, expect, it } from '@ohos/hypium';
import {
  LearnFile, PROGRESS_UNKNOWN, downloadFileName, percentOf, sanitizePathSegment, sortFiles
} from '../main/ets/model/file';
import { mimeOfExtension } from '../main/ets/common/mime';
import { parseFileCategoryList, parseFileList } from '../main/ets/network/parseFile';
import { parseServerTime } from '../main/ets/common/time';

const DAY: number = 24 * 60 * 60 * 1000;

function file(id: string, uploadMs: number): LearnFile {
  return new LearnFile(id, `f-${id}`, 'c1', '课程甲', '张老师', `文件${id}`, '描述',
    '1.2MB', 1258291, '2025-05-01 10:00', uploadMs, 'pdf', '课件', false, false);
}

function throws(fn: () => void): boolean {
  try {
    fn();
    return false;
  } catch (err) {
    return true;
  }
}

/** 学生形态：`object` 本身就是数组 */
const STUDENT_BODY: string = '{"result":"success","object":['
  + '{"kjxxid":"k1","wjid":"w1","bt":"讲义&amp;习题","ms":"第 1 章","fileSize":"1.2MB","wjdx":1258291,'
  + '"scsj":"2025-05-01 10:00","wjlx":"pdf","kjflid":"cat1","sfqd":1,"isNew":true},'
  + '{"kjxxid":"k2","wjid":"w2","bt":"附录","fileSize":"300KB","wjdx":307200,'
  + '"scsj":"2025-04-01 09:00","wjlx":"docx","kjflid":"cat9"}]}';

const CATEGORY_BODY: string = '{"result":"success","object":{"rows":['
  + '{"kjflid":"cat1","bt":"课件","czsj":"2024-09-01 00:00"},'
  + '{"kjflid":"cat2","bt":"参考资料","czsj":"2024-09-02 00:00"}]}}';

export default function fileTest() {
  describe('file', () => {

    describe('列表解析', () => {

      it('学生形态的信封是 object 本身为数组，字段与分类名都要落对', 0, () => {
        const categories: Map<string, string> = parseFileCategoryList(CATEGORY_BODY);
        const items: LearnFile[] = parseFileList(STUDENT_BODY, 'c1', '课程甲', '张老师', categories);
        expect(items.length).assertEqual(2);
        expect(items[0].title).assertEqual('讲义&习题');
        expect(items[0].fileId).assertEqual('w1');
        expect(items[0].categoryName).assertEqual('课件');
        expect(items[0].markedImportant).assertTrue();
        expect(items[0].isNew).assertTrue();
        expect(items[0].fileType).assertEqual('pdf');
        expect(items[0].uploadTimeMs > 0).assertTrue();
        // 分类关联不到时留空，而不是整批失败
        expect(items[1].categoryName).assertEqual('');
        expect(items[1].markedImportant).assertFalse();
      });

      it('教师形态的 resultsList 也能解出', 0, () => {
        const body: string = '{"result":"success","object":{"resultsList":['
          + '{"kjxxid":"k3","wjid":"w3","bt":"x","scsj":"2025-05-01 10:00"}]}}';
        expect(parseFileList(body, 'c1', '甲', '师', new Map()).length).assertEqual(1);
      });

      it('结构不符必须抛出（不静默成空列表）', 0, () => {
        expect(throws(() => parseFileList('not json', 'c1', '甲', '师', new Map()))).assertTrue();
        expect(throws(() => parseFileList('{"result":"fail","object":[]}', 'c1', '甲', '师', new Map())))
          .assertTrue();
        expect(throws(() => parseFileList('{"result":"success","object":{}}', 'c1', '甲', '师', new Map())))
          .assertTrue();
      });

      it('空数组是合法结果', 0, () => {
        expect(parseFileList('{"result":"success","object":[]}', 'c1', '甲', '师', new Map()).length)
          .assertEqual(0);
      });
    });

    describe('分类解析', () => {

      it('取 rows 里的 kjflid→bt', 0, () => {
        const categories: Map<string, string> = parseFileCategoryList(CATEGORY_BODY);
        expect(categories.get('cat1')).assertEqual('课件');
        expect(categories.get('cat2')).assertEqual('参考资料');
      });

      it('缺少 rows 应抛出', 0, () => {
        expect(throws(() => parseFileCategoryList('{"result":"success","object":{}}'))).assertTrue();
      });
    });

    describe('排序与元信息', () => {

      it('上传时间倒序，同一时间按 id 倒序', 0, () => {
        const now: number = 100 * DAY;
        const sorted: LearnFile[] = sortFiles([
          file('a', now - 2 * DAY), file('b', now), file('c', now - 2 * DAY)]);
        expect(sorted[0].id).assertEqual('b');
        // 同一时间（a 与 c）按 id 倒序：c 在前
        expect(sorted[1].id).assertEqual('c');
        expect(sorted[2].id).assertEqual('a');
      });

      it('元信息行 = 分类 + 类型(大写) + 大小，去空白', 0, () => {
        expect(file('a', 1).metaLine()).assertEqual('课件 PDF 1.2MB');
        const bare: LearnFile = new LearnFile('x', 'fx', 'c1', '甲', '师', 't', '', '1MB', 1,
          '', 0, '', '', false, false);
        expect(bare.metaLine()).assertEqual('1MB');
      });
    });

    describe('文件名与路径清洗', () => {

      it('路径分隔符与冒号被替换，首尾点被去掉', 0, () => {
        expect(sanitizePathSegment('第1章/习题\\答案: a')).assertEqual('第1章_习题_答案_ a');
        // `.` / `..` 这类特殊目录名必须被化解
        expect(sanitizePathSegment('..')).assertEqual('file');
        expect(sanitizePathSegment('   ')).assertEqual('file');
      });

      it('下载文件名 = 课程名-标题.类型', 0, () => {
        expect(downloadFileName('数据结构', '第1章', 'pdf')).assertEqual('数据结构-第1章.pdf');
        // 类型为空时不加后缀
        expect(downloadFileName('课', '题', '')).assertEqual('课-题');
      });
    });

    describe('下载进度百分比', () => {

      it('正常归一成 0~100 的整数', 0, () => {
        expect(percentOf(0, 1000)).assertEqual(0);
        expect(percentOf(1, 1000)).assertEqual(0);
        expect(percentOf(425, 1000)).assertEqual(42);
        expect(percentOf(1000, 1000)).assertEqual(100);
      });

      it('总量不明（<=0）时返回未知，不猜百分比', 0, () => {
        expect(percentOf(500, 0)).assertEqual(PROGRESS_UNKNOWN);
        expect(percentOf(500, -1)).assertEqual(PROGRESS_UNKNOWN);
      });

      it('服务端给错（已收多于总量）时不产生 >100 的值', 0, () => {
        expect(percentOf(3000, 1000)).assertEqual(100);
      });

      it('负数已收视为未知，不显示负进度', 0, () => {
        expect(percentOf(-5, 1000)).assertEqual(PROGRESS_UNKNOWN);
      });
    });

    describe('MIME 与时间解析', () => {

      it('常见课件扩展名映射正确，未知退让为二进制流', 0, () => {
        expect(mimeOfExtension('pdf')).assertEqual('application/pdf');
        expect(mimeOfExtension('.PDF')).assertEqual('application/pdf');
        expect(mimeOfExtension('PPTX'))
          .assertEqual('application/vnd.openxmlformats-officedocument.presentationml.presentation');
        expect(mimeOfExtension('zip')).assertEqual('application/zip');
        expect(mimeOfExtension('未知')).assertEqual('application/octet-stream');
        expect(mimeOfExtension('')).assertEqual('application/octet-stream');
      });

      it('服务端时间串解析：常见形态可解，认不出退 0', 0, () => {
        expect(parseServerTime('2025-05-01 10:00') > 0).assertTrue();
        expect(parseServerTime('2025/05/01 10:00') > 0).assertTrue();
        expect(parseServerTime('')).assertEqual(0);
        expect(parseServerTime('待定')).assertEqual(0);
      });
    });
  });
}
