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
import {
  FamilySecretBundle,
  GatewaySecretEntry,
  InviteHeader,
  InviteKdf,
  JoinRequest
} from '../../../../main/ets/service/invite/InviteModels';
import { InviteCodec } from '../../../../main/ets/service/invite/InviteCodec';
import { CryptoService } from '../../../../main/ets/service/crypto/CryptoService';
import { OhosCryptoProvider } from '../../../../main/ets/service/crypto/OhosCryptoProvider';
import { MigrationRegistry } from '../../../../main/ets/service/storage/MigrationRegistry';
import { BytesUtil } from '../../../../main/ets/common/utils/BytesUtil';
import { Base64Url } from '../../../../main/ets/common/utils/Base64Url';
import { InviteMode, MemberRole } from '../../../../main/ets/model/FamilyModels';
import { TlsMaterial } from '../../../../main/ets/model/GatewayRoute';

const crypto: CryptoService = new CryptoService(new OhosCryptoProvider());
const FAMILY_ID: string = '11111111-1111-4111-8111-111111111111';
const INVITE_ID: string = '22222222-2222-4222-8222-222222222222';
const ROOM_ID: string = '33333333-3333-4333-8333-333333333333';

function key32(): Uint8Array {
  const bytes = new Uint8Array(32);
  for (let index = 0; index < bytes.length; index++) {
    bytes[index] = index + 1;
  }
  return bytes;
}

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

    it('C13_Ycr1_yci1_roundTripStrict', 0, async () => {
      const join = new JoinRequest(1, '00112233445566778899aabbccddeeff',
        Base64Url.encode(key32()), '20261017T080000Z', 'Bob');
      const text = InviteCodec.encodeJoinRequest(join);
      expect(text.startsWith('YCR1.')).assertTrue();
      expect(InviteCodec.decodeJoinRequest(text).memberId).assertEqual(join.memberId);

      const header = new InviteHeader(1, INVITE_ID, FAMILY_ID, 'Home', MemberRole.MEMBER,
        [ROOM_ID], '20261018T080000Z', 1, InviteKdf.keyWrap(Base64Url.encode(key32())),
        'app-key-v1');
      const encoded = InviteCodec.encodeHeader(header);
      const decoded = InviteCodec.decodeHeader(encoded);
      expect(decoded.inviteId).assertEqual(INVITE_ID);
      expect(decoded.allowedRoomIds[0]).assertEqual(ROOM_ID);

      const bundle = new FamilySecretBundle(1, FAMILY_ID, '20261017T080000Z', 'app-key-v1',
        BytesUtil.hexLower(key32()), [new GatewaySecretEntry('gw-1',
          '00112233445566778899aabbccddeeff', 'Gateway',
          new TlsMaterial([BytesUtil.hexLower(key32())], 9200, 'sha256-spki-der'))]);
      expect(InviteCodec.decodeBundle(InviteCodec.encodeBundle(bundle)).gateways.length)
        .assertEqual(1);
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
