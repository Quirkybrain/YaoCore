/*
 * YaoCore C-04 crypto failure classifier (R-01).
 * Producer: agent:implementation-engineer | Task: wp-018-fix-t07
 * Contract: DES-A §7.2 (DES-A-C04-ERR)
 *
 * Pure, host-loadable classification of platform failures into the frozen
 * CryptoProviderError kinds. Keeping it free of @ohos imports lets the Node
 * host suite assert each stage without a device:
 *
 * - CREATE          primitive/algorithm creation or initialisation failure
 *                   (createMd/createMac/createKdf/createCipher/createRandom/
 *                   createAsyKeyGenerator/createKeyAgreement) -> UNAVAILABLE
 * - KEY_CONVERSION  key material conversion/DER wrapping/export
 *                   (convertKeySync, getEncoded, X25519 DER codec) -> INVALID_KEY
 * - OPERATION       platform operation failure (init/update/final/generate)
 *                   -> OPERATION_FAILED
 * - GCM_DECRYPT_FINAL  authenticated GCM decryption: only the platform crypto
 *                   operation failure (17630001) is an authentication/tag
 *                   mismatch; parameter/call failures stay OPERATION_FAILED.
 *
 * An existing CryptoProviderError keeps its own kind (no reclassification).
 */
import { CryptoErrorKind, CryptoProviderError } from './CryptoProvider';

export enum CryptoFailureStage {
  CREATE = 'CREATE',
  KEY_CONVERSION = 'KEY_CONVERSION',
  OPERATION = 'OPERATION',
  GCM_DECRYPT_FINAL = 'GCM_DECRYPT_FINAL'
}

/** cryptoFramework.Result.ERR_CRYPTO_OPERATION (GCM tag verification failure). */
const AUTH_TAG_PLATFORM_CODE: number = 17630001;

interface PlatformErrorLike {
  code?: number;
}

export function classifyCryptoFailure(stage: CryptoFailureStage,
  error: Error): CryptoErrorKind {
  if (error instanceof CryptoProviderError) {
    return error.kind;
  }
  if (stage === CryptoFailureStage.CREATE) {
    return CryptoErrorKind.UNAVAILABLE;
  }
  if (stage === CryptoFailureStage.KEY_CONVERSION) {
    return CryptoErrorKind.INVALID_KEY;
  }
  if (stage === CryptoFailureStage.GCM_DECRYPT_FINAL &&
    platformErrorCode(error) === AUTH_TAG_PLATFORM_CODE) {
    return CryptoErrorKind.AUTH_TAG;
  }
  return CryptoErrorKind.OPERATION_FAILED;
}

function platformErrorCode(error: Error): number {
  const candidate = error as PlatformErrorLike;
  if (typeof candidate.code === 'number') {
    return candidate.code;
  }
  return -1;
}
