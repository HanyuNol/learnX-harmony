/**
 * 课程：类型与**纯逻辑**（显示名回退、排序、学期归属判定）。
 *
 * 单独成模块的理由同 `model/semester.ets`：课程端点要会话，设备验收必须登录后才能跑，
 * 而"字段怎么回退、列表怎么排、什么时候该重取"这些判断可以在这里穷举测试。
 *
 * 字段语义对齐上游 `thu-learn-lib@4.0.0` 的 `CourseInfo`（`src/types.ts:76-90`）与其映射
 * （`src/index.ts:373-385`）。**不取** `timeAndLocation`：上游为它每门课再发一次请求，
 * 而本项目列表与详情都不展示它（courses spec §2「不做」）。
 */

/** 显示名为空时的占位。用破折号而不是中文，免去一处不必要的多语言负担 */
const PLACEHOLDER_NAME: string = '—';

export class Course {
  /** 课程 id（上游 `wlkcid`） */
  readonly id: string;
  /** 课程名（上游 `zywkcm`，已解码 HTML 实体） */
  readonly name: string;
  /** 中文名（上游 `kcm`） */
  readonly chineseName: string;
  /** 英文名（上游 `ywkcm`） */
  readonly englishName: string;
  /** 教师名（上游 `jsm`；教师形态下服务端不给，退让为空串） */
  readonly teacherName: string;
  /** 课程号（上游 `kch`） */
  readonly courseNumber: string;
  /** 教师工号（上游 `jsh`）。当前界面不显示；留着将来按教师筛选时有数据可用 */
  readonly teacherNumber: string;
  /** 课程序号（上游 `kxh`） */
  readonly courseIndex: number;

  constructor(id: string, name: string, chineseName: string, englishName: string,
              teacherName: string, courseNumber: string, teacherNumber: string, courseIndex: number) {
    this.id = id;
    this.name = name;
    this.chineseName = chineseName;
    this.englishName = englishName;
    this.teacherName = teacherName;
    this.courseNumber = courseNumber;
    this.teacherNumber = teacherNumber;
    this.courseIndex = courseIndex;
  }

  /**
   * 列表/详情里显示的课程名。
   *
   * 回退链 `name` → `chineseName` → `courseNumber`：三者在真实数据里都可能缺
   * （`name` 是解码后的 `zywkcm`，服务端偶发给空），回退到最后一个非空者，
   * 保证不出现空白行；三者皆空时给一个可识别的占位而不是空串。
   */
  displayName(): string {
    if (this.name.length > 0) {
      return this.name;
    }
    if (this.chineseName.length > 0) {
      return this.chineseName;
    }
    if (this.courseNumber.length > 0) {
      return this.courseNumber;
    }
    return PLACEHOLDER_NAME;
  }
}

/**
 * 按 id 升序排序（对齐上游 `actions/courses.ts`）。
 *
 * 排序是为了**同一份数据每次顺序一致**——服务端不保证顺序，界面若随响应顺序抖动，
 * 用户会觉得"课程在乱跳"。升序也比"按 id 降序"稳：新学期的课程 id 前缀不同，
 * 但同一学期内 id 是稳定标识。
 */
export function sortCourses(courses: Course[]): Course[] {
  const sorted: Course[] = courses.slice();
  sorted.sort((left: Course, right: Course): number => {
    if (left.id === right.id) {
      return 0;
    }
    return left.id < right.id ? -1 : 1;
  });
  return sorted;
}

/**
 * 已加载的课程列表是否相对请求的学期**过期**（需要重取）。
 *
 * 三条规则，各有理由：
 * - 请求学期为空 → **不算过期**（学期还没定，本就不该发请求，也不需要重取）；
 * - 尚未加载过（已加载学期为空）→ **过期**（必须触发一次加载）；
 * - 两者不同 → 过期（否则会把上个学期的课程留在界面上）。
 */
export function isCourseListStale(loadedSemesterId: string, requestedSemesterId: string): boolean {
  if (requestedSemesterId.length === 0) {
    return false;
  }
  return loadedSemesterId !== requestedSemesterId;
}
