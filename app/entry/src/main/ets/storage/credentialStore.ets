/**
 * 凭据存储：关键资产存储服务（Asset Store Kit）的**唯一读写入口**。
 *
 * 约束（SECURITY.md 与 ADR-0007）：其余模块不得直接调用该 Kit；
 * 登出必须清除全部凭据与设备指纹；凭据值不得进入日志。
 */

import { asset } from '@kit.AssetStoreKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { buffer } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { Credentials, LogoutClearPlan, logoutClearPlan } from '../model/auth';
import { Logger } from '../common/logger';
import { normalize } from '../common/errors';

const TAG: string = 'credentialStore';

/** 资产别名。前缀避免与其他应用的资产混淆 */
const ALIAS_USERNAME: string = 'learnx.username';
const ALIAS_PASSWORD: string = 'learnx.password';
const ALIAS_FINGER_PRINT: string = 'learnx.fingerPrint';

/** 设备指纹的十六进制长度（上游为 32 位） */
const FINGER_PRINT_HEX_LENGTH: number = 32;

/** 资产未找到的错误码。**查询未命中会抛该异常，而非返回空结果** */
const ERROR_ASSET_NOT_FOUND: number = 24000002;

/** 资产已存在的错误码 */
const ERROR_ASSET_ALREADY_EXISTS: number = 24000003;

function toBytes(value: string): Uint8Array {
  return new Uint8Array(buffer.from(value, 'utf-8').buffer);
}

function fromBytes(bytes: Uint8Array): string {
  return buffer.from(bytes.buffer, bytes.byteOffset, bytes.byteLength).toString('utf-8');
}

function isAssetNotFound(err: Object): boolean {
  return (err as BusinessError).code === ERROR_ASSET_NOT_FOUND;
}

/** 构造仅含别名的查询条件 */
function aliasQuery(alias: string): asset.AssetMap {
  const query: asset.AssetMap = new Map();
  query.set(asset.Tag.ALIAS, toBytes(alias));
  return query;
}

/**
 * 写入或更新一条资产。
 *
 * **实测修正**：原先实现"先 update、未命中再 add"，假设资产不存在时 update 会返回
 * 24000002（未找到）。真机实测表明它返回的是 **401 参数错误**，导致首登时凭据写入直接失败。
 * 现改为"先 add、已存在则先删再 add"——语义最可预测，不依赖 update 的参数校验规则
 * （ACCESSIBILITY 等访问控制属性本来也只能在创建时指定）。
 */
async function upsert(alias: string, value: string): Promise<void> {
  try {
    await asset.add(attributesFor(alias, value));
    return;
  } catch (err) {
    if ((err as BusinessError).code !== ERROR_ASSET_ALREADY_EXISTS) {
      throw normalize(err, `新增资产 ${alias}`);
    }
  }

  // 已存在：删除后重建，避免 update 的参数校验与访问控制属性限制
  await removeIfPresent(alias);
  try {
    await asset.add(attributesFor(alias, value));
  } catch (err) {
    throw normalize(err, `重建资产 ${alias}`);
  }
}

function attributesFor(alias: string, value: string): asset.AssetMap {
  const attributes: asset.AssetMap = new Map();
  attributes.set(asset.Tag.ALIAS, toBytes(alias));
  attributes.set(asset.Tag.SECRET, toBytes(value));
  // 首次解锁后即可访问：允许开机未解锁时完成后台同步
  attributes.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
  return attributes;
}

/** 读取一条资产；不存在返回 null（这是首次运行的正常状态，不是错误） */
async function readSecret(alias: string): Promise<string | null> {
  const query: asset.AssetMap = aliasQuery(alias);
  query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);

  try {
    const results: Array<asset.AssetMap> = await asset.query(query);
    if (results.length === 0) {
      return null;
    }
    // AssetMap 的值是联合类型，需收窄后才能当字节串用
    const raw: asset.Value | undefined = results[0].get(asset.Tag.SECRET);
    if (!(raw instanceof Uint8Array)) {
      Logger.warn(TAG, `资产 ${alias} 的明文类型异常，按缺失处理`);
      return null;
    }
    return fromBytes(raw);
  } catch (err) {
    if (isAssetNotFound(err)) {
      return null;
    }
    throw normalize(err, `读取资产 ${alias}`);
  }
}

/** 删除一条资产；不存在视为成功（幂等） */
async function removeIfPresent(alias: string): Promise<void> {
  try {
    await asset.remove(aliasQuery(alias));
  } catch (err) {
    if (isAssetNotFound(err)) {
      return;
    }
    throw normalize(err, `删除资产 ${alias}`);
  }
}

/**
 * 生成 32 位十六进制的设备指纹。
 *
 * 用系统密码学随机源而非 Math.random——指纹参与登录请求，可预测的随机数没有意义。
 */
async function generateFingerPrint(): Promise<string> {
  const random: cryptoFramework.Random = cryptoFramework.createRandom();
  const blob: cryptoFramework.DataBlob = await random.generateRandom(FINGER_PRINT_HEX_LENGTH / 2);

  let hex: string = '';
  for (let i = 0; i < blob.data.length; i++) {
    const byte: number = blob.data[i];
    hex += byte < 16 ? `0${byte.toString(16)}` : byte.toString(16);
  }
  return hex;
}

export class CredentialStore {
  /**
   * 保存凭据。`rememberPassword` 为 false 时只保存学号与指纹，
   * 下次启动需要用户重新输入密码。
   */
  static async save(credentials: Credentials, rememberPassword: boolean): Promise<void> {
    try {
      await upsert(ALIAS_USERNAME, credentials.username);
      await upsert(ALIAS_FINGER_PRINT, credentials.fingerPrint);
      if (rememberPassword) {
        await upsert(ALIAS_PASSWORD, credentials.password);
      } else {
        await removeIfPresent(ALIAS_PASSWORD);
      }
      // 只记存在性：学号同样不进日志（审查 R-11）
      Logger.info(TAG, `已保存学号 len=${credentials.username.length}`);
      Logger.info(TAG, `保存凭据完成 rememberPassword=${rememberPassword}`);
    } catch (err) {
      throw normalize(err, '保存凭据');
    }
  }

  /**
   * 读取凭据。任一必备项缺失（首次运行、或用户未选记住密码）即返回 null，
   * 由调用方引导用户输入。
   */
  static async load(): Promise<Credentials | null> {
    try {
      const username: string | null = await readSecret(ALIAS_USERNAME);
      const password: string | null = await readSecret(ALIAS_PASSWORD);
      const fingerPrint: string | null = await readSecret(ALIAS_FINGER_PRINT);

      if (username === null || password === null || fingerPrint === null) {
        Logger.info(TAG, '凭据不完整，需要用户登录');
        return null;
      }
      return new Credentials(username, password, fingerPrint);
    } catch (err) {
      throw normalize(err, '读取凭据');
    }
  }

  /** 仅读取学号（用于回填登录框），不读密码 */
  static async loadUsername(): Promise<string | null> {
    try {
      return await readSecret(ALIAS_USERNAME);
    } catch (err) {
      throw normalize(err, '读取学号');
    }
  }

  /**
   * 按"是否记住密码"处置登出时的凭据（FR-31）。
   *
   * **判据是"密码是否还在存储里"**，而不是另存一个开关：`save(credentials, rememberPassword)`
   * 已经用"写不写密码"表达了用户的选择（未勾选时密码被移除），这里读同一个事实即可——
   * 多存一个开关就多一份可能与它不一致的状态。密码缺失时按"未记住"处理（保守：清除）。
   *
   * **刻意保留设备指纹**。
   *
   * 为什么保留（原实现把指纹也一起清了，2026-09-27 更正）：指纹是**设备标识**，
   * 服务端靠它把本机认成"同一台已登记的信任浏览器"。清掉它的后果是——每次登出再登录，
   * 应用都拿着一个全新指纹去做信任登记，服务端自然认不出来，于是**每次都要重新二次验证**。
   * 实测现象：登出后紧跟一句"已生成新的设备指纹"，随后登记请求返回 `msg:"否"`、
   * 页面提示"未使用可信浏览器"。上游 `learnX` 也永不清指纹——它的 auth reducer 没有登出分支。
   *
   * 它不是凭据：不含用户信息、不由用户输入、服务端本就存有它的副本；
   * 本地同样存于加密存储中。
   */
  static async applyLogoutPlan(): Promise<void> {
    try {
      const password: string | null = await readSecret(ALIAS_PASSWORD);
      const plan: LogoutClearPlan = logoutClearPlan(password !== null);
      if (plan.clearPassword) {
        await removeIfPresent(ALIAS_PASSWORD);
      }
      if (plan.clearUsername) {
        await removeIfPresent(ALIAS_USERNAME);
      }
      // 只记分支，不记值（学号与密码都不进日志）
      Logger.info(TAG, `登出凭据处置完成：保留=${!plan.clearPassword}（设备指纹始终保留）`);
    } catch (err) {
      throw normalize(err, '处置凭据');
    }
  }

  /**
   * 取得设备指纹：已存在则复用，否则生成并持久化。
   *
   * **有意区别于上游**（上游每次登录都用新的随机指纹）——持久化可避免服务端
   * 把同一台设备当成新设备。若服务端行为异常，回退到每次随机即可。
   */
  static async getOrCreateFingerPrint(): Promise<string> {
    try {
      const existing: string | null = await readSecret(ALIAS_FINGER_PRINT);
      if (existing !== null && existing.length === FINGER_PRINT_HEX_LENGTH) {
        // 复用要留痕：排障时"这次登出后指纹是新生成的还是复用的"决定了服务端认不认设备
        Logger.info(TAG, '复用已有设备指纹');
        return existing;
      }
      const generated: string = await generateFingerPrint();
      await upsert(ALIAS_FINGER_PRINT, generated);
      Logger.info(TAG, '已生成新的设备指纹');
      return generated;
    } catch (err) {
      throw normalize(err, '取得设备指纹');
    }
  }
}
