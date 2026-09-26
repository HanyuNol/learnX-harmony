/**
 * SM2 加密：把密码转成统一身份认证服务端可接受的提交值。
 *
 * 纯格式逻辑（坐标补零、裸拼接、公钥解析）在 sm2Format.ets——那里不依赖系统能力，
 * 可离线单元测试。本文件只负责调用平台的加密框架。
 */

import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { buffer } from '@kit.ArkTS';
import { Logger } from '../common/logger';
import { normalize } from '../common/errors';
import { buildRawCipherHex, parsePublicKeyHex, Sm2PublicKey } from './sm2Format';

const TAG: string = 'sm2';

/** SM2 曲线在框架中的名称（OpenSSL NID 命名） */
const SM2_CURVE_NAME: string = 'NID_sm2';

/** SM2 加密算法串。必须用 SM3 摘要——Code Linter 的安全规则禁止 SM2_256|SHA1 与 SM2_256|MD5 */
const SM2_CIPHER_ALG: string = 'SM2_256|SM3';

/**
 * 用页面给出的公钥加密明文，返回服务端可接受的提交值。
 *
 * 平台异常一律在此归一为 AuthError，不让加密框架的错误码泄漏到上层。
 */
export async function encryptPassword(plainText: string, publicKeyHex: string): Promise<string> {
  try {
    const publicKey: Sm2PublicKey = parsePublicKeyHex(publicKeyHex);
    Logger.secret(TAG, '待加密明文长度', plainText);

    const commonParams: cryptoFramework.ECCCommonParamsSpec =
      cryptoFramework.ECCKeyUtil.genECCCommonParamsSpec(SM2_CURVE_NAME);

    const pubKeySpec: cryptoFramework.ECCPubKeySpec = {
      params: commonParams,
      pk: { x: publicKey.x, y: publicKey.y } as cryptoFramework.Point,
      algName: 'SM2',
      specType: cryptoFramework.AsyKeySpecType.PUBLIC_KEY_SPEC
    };

    const generator: cryptoFramework.AsyKeyGeneratorBySpec =
      cryptoFramework.createAsyKeyGeneratorBySpec(pubKeySpec);
    const pubKey: cryptoFramework.PubKey = await generator.generatePubKey();

    const cipher: cryptoFramework.Cipher = cryptoFramework.createCipher(SM2_CIPHER_ALG);
    await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, pubKey, null);

    const plainBlob: cryptoFramework.DataBlob = {
      data: new Uint8Array(buffer.from(plainText, 'utf-8').buffer)
    };
    const encrypted: cryptoFramework.DataBlob = await cipher.doFinal(plainBlob);

    // 框架输出 ASN.1(DER)，需拆出分量后按服务端要求的裸格式重组
    const spec: cryptoFramework.SM2CipherTextSpec =
      cryptoFramework.SM2CryptoUtil.getCipherTextSpec(encrypted, 'C1C3C2');

    return buildRawCipherHex(spec.xCoordinate, spec.yCoordinate, spec.cipherTextData, spec.hashData);
  } catch (err) {
    throw normalize(err, 'SM2 加密密码');
  }
}
