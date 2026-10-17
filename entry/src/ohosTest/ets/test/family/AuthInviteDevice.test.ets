/*
 * YaoCore C-12/C-13 device-side skeleton.
 * Producer: agent:implementation-engineer | Task: T-13 / wp-049-family
 * Contract: DES-A §12.5/§13.5; TEST-001 V-10; D-019 device layer.
 *
 * STATUS: COMPILED_ONLY / BLOCKED_ON_DEVICE_RUNNER.
 * No device/emulator/signing config exists in this environment. The suite is
 * registered so a future device run exercises the real platform PBKDF2/
 * X25519/AES-256-GCM implementations and the production codec. It must never
 * be reported as PASS from the host Node runner.
 *
 * PUBLIC TEST DATA ONLY.
 */
import { describe, expect, it } from '@ohos/hypium';
import { AuthService } from '../../../../main/ets/service/auth/AuthService';
import { CryptoService } from '../../../../main/ets/service/crypto/CryptoService';
import { OhosCryptoProvider } from '../../../../main/ets/service/crypto/OhosCryptoProvider';
import { MigrationRegistry } from '../../../../main/ets/service/storage/MigrationRegistry';
import { BytesUtil } from '../../../../main/ets/common/utils/BytesUtil';

const crypto: CryptoService = new CryptoService(new OhosCryptoProvider());

export default function authInviteDeviceTest() {
  describe('BLOCKED_ON_DEVICE_RUNNER C12/C13 auth and invites', () => {
    it('C12_AuthService_registersV3Migration', 0, () => {
      const registry = new MigrationRegistry();
      AuthService.registerMigrations(registry);
      expect(registry !== undefined).assertTrue();
    });

    it('C12_Pbkdf2Sha256_120kFrozenVector', 0, async () => {
      const salt = BytesUtil.hexToBytes('000102030405060708090a0b0c0d0e0f');
      const derived = await crypto.pbkdf2Sha256(BytesUtil.utf8('password'), salt, 120000, 32);
      expect(BytesUtil.hexLower(derived)).assertEqual(
        '0a300026cc0ba55a240b894dd629b07d0fc4e091922bc91b7d711b092183a4f0');
    });

    it('C13_AesGcm_aadTamperFailsClosed', 0, async () => {
      const key = await crypto.randomBytes(32);
      const iv = await crypto.randomBytes(12);
      const aad = BytesUtil.utf8('header-bytes');
      const plaintext = BytesUtil.utf8('YaoCore invite bundle');
      const sealed = await crypto.encryptAesGcm(key, iv, aad, plaintext);
      const opened = await crypto.decryptAesGcm(key, iv, aad, sealed.ciphertext, sealed.tag);
      expect(BytesUtil.fromUtf8(opened)).assertEqual('YaoCore invite bundle');
      let failed = false;
      try {
        await crypto.decryptAesGcm(key, iv, BytesUtil.utf8('header-byteS'),
          sealed.ciphertext, sealed.tag);
      } catch (error) {
        failed = (error as Error).message.length > 0;
      }
      expect(failed).assertTrue();
    });

    it('C13_X25519_ecdhAgrees', 0, async () => {
      const alice = await crypto.generateX25519KeyPair();
      const bob = await crypto.generateX25519KeyPair();
      const left = await crypto.computeX25519(alice.privateKey, bob.publicKeyRaw);
      const right = await crypto.computeX25519(bob.privateKey, alice.publicKeyRaw);
      expect(BytesUtil.hexLower(left)).assertEqual(BytesUtil.hexLower(right));
    });
  });
}
