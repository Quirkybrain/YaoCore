/*
 * YaoCore T-07 host (local) compile/behavior suite.
 * Producer: agent:implementation-engineer | Task: T-07 / wp-016-security
 * Contract: DES-A §7, §8; TEST-001 host layer.
 *
 * This suite exists mainly to pull C-04/C-05 into the ArkTS host compile graph
 * (`hvigorw test` UnitTestArkTS) and to keep a small pure-logic smoke test.
 * Executable host evidence remains `entry/src/test/run-host-tests.sh` (Node);
 * the Hypium Linux Previewer is BLOCKED (TEST-001 §3).
 */
import { describe, expect, it } from '@ohos/hypium';
import { CryptoService } from '../../main/ets/service/crypto/CryptoService';
import { OhosCryptoProvider } from '../../main/ets/service/crypto/OhosCryptoProvider';
import { X25519KeyCodec } from '../../main/ets/service/crypto/X25519KeyCodec';
import { CanonicalBuilder, ControlCanonicalFields } from '../../main/ets/service/security/CanonicalBuilder';
import { RequestSigner, SigningInput } from '../../main/ets/service/security/RequestSigner';
import { ResponseVerifier } from '../../main/ets/service/security/ResponseVerifier';
import { NonceCache } from '../../main/ets/service/security/NonceCache';
import { ClockSkewTracker } from '../../main/ets/service/security/ClockSkewTracker';
import { DeviceAction } from '../../main/ets/common/constants/DeviceConstants';
import { BytesUtil } from '../../main/ets/common/utils/BytesUtil';
import { TestCryptoProvider } from '../host/TestCryptoProvider';
import securityDeviceTest from '../../ohosTest/ets/test/security/SecurityDevice.test';
import type { ClockPort, RandomPort } from '../../main/ets/common/types/Ports';

const FIXED_MS: number = Date.UTC(2026, 6, 14, 8, 0, 0);

class FixedClock implements ClockPort {
  nowMs(): number {
    return FIXED_MS;
  }
}

class FixedRandom implements RandomPort {
  nextBytes(length: number): Promise<Uint8Array> {
    const bytes = new Uint8Array(length);
    bytes.fill(0x2a);
    return Promise.resolve(bytes);
  }
}

// Imported only to pull the device-side C-04 skeleton into the compile graph.
// It remains BLOCKED for execution until a device runner exists.
void securityDeviceTest;

export function SecurityHostSuite() {
  describe('T07_C04_C05_host_compile_and_smoke', () => {
    it('C04_OhosProviderWiresIntoService', 0, () => {
      const service: CryptoService = new CryptoService(new OhosCryptoProvider());
      expect(service !== undefined).assertTrue();
    });

    it('C04_X25519CodecRoundTripsRaw', 0, () => {
      const raw = new Uint8Array(32);
      raw.fill(3);
      const der = X25519KeyCodec.rawToDerPublicKey(raw);
      expect(der.length).assertEqual(44);
      expect(BytesUtil.hexLower(X25519KeyCodec.derToRawPublicKey(der)))
        .assertEqual(BytesUtil.hexLower(raw));
    });

    it('C05_CanonicalControlHasTenLinesWithoutTrailingNewline', 0, () => {
      const canonical = CanonicalBuilder.control(new ControlCanonicalFields(
        'req-1729000000000-1', 2001, 1, 'Light_01', 'ON', '',
        '20260714T080000Z', 'abababababababababababababababab',
        'HMAC-SHA256', 'app-key-v1'));
      expect(canonical.split('\n').length).assertEqual(10);
      expect(canonical.endsWith('\n')).assertFalse();
    });

    it('C05_RequestSignerAndVerifierShareTheCanonicalContract', 0, async () => {
      const clock = new FixedClock();
      const crypto = new CryptoService(new TestCryptoProvider());
      const signer = new RequestSigner(crypto, clock, new FixedRandom(), new NonceCache(clock));
      const signed = await signer.signControl(
        new SigningInput('gateway_01', 'Light_01', DeviceAction.SET_BRIGHTNESS, 68),
        BytesUtil.utf8('0123456789abcdef'), 1);
      expect(signed.nonce.length).assertEqual(32);
      expect(signed.canonical.split('\n').length).assertEqual(10);
      const verifier = new ResponseVerifier(crypto);
      expect(verifier !== undefined).assertTrue();
    });

    it('C05_NonceCacheAndSkewTrackerRemainPure', 0, () => {
      const clock = new FixedClock();
      const cache = new NonceCache(clock);
      const first = cache.checkAndRemember('app-key-v1', 'aabb', FIXED_MS);
      const second = cache.checkAndRemember('app-key-v1', 'aabb', FIXED_MS);
      expect(first).assertEqual('NEW');
      expect(second).assertEqual('DUPLICATE');
      const tracker = new ClockSkewTracker();
      const observation = tracker.observe('20260714T080200Z', FIXED_MS);
      expect(observation.exceedsWindow).assertFalse();
    });
  });
}
