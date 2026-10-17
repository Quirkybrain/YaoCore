/*
 * YaoCore C-04 device-side crypto vector tests.
 * Producer: agent:implementation-engineer | Task: T-07 / wp-016-security
 * Contract: DES-A §7.4 (device/ohosTest), §7.1.4; RFC 7748; RFC 5869;
 *           NIST SP 800-38A/F.5.5; NIST GCM test case 13.
 *
 * STATUS: BLOCKED — no device/emulator and no signing config in this
 * environment. This suite is COMPILED_ONLY until a device runner exists; it
 * must never be reported as PASS from the host Node runner.
 *
 * PUBLIC TEST DATA ONLY.
 */
import { describe, expect, it } from '@ohos/hypium';
import { CryptoService } from '../../../../main/ets/service/crypto/CryptoService';
import { OhosCryptoProvider } from '../../../../main/ets/service/crypto/OhosCryptoProvider';
import { X25519KeyCodec } from '../../../../main/ets/service/crypto/X25519KeyCodec';
import { BytesUtil } from '../../../../main/ets/common/utils/BytesUtil';

const provider: OhosCryptoProvider = new OhosCryptoProvider();
const crypto: CryptoService = new CryptoService(provider);

export default function securityDeviceTest() {
  describe('BLOCKED_ON_DEVICE_RUNNER C04 cryptoFramework vectors', () => {
    it('C04_sha256AndHmacMatchPublicVectors', 0, async () => {
      const digest = await crypto.sha256(BytesUtil.utf8('abc'));
      expect(BytesUtil.hexLower(digest)).assertEqual(
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
      const mac = await crypto.hmacSha256(BytesUtil.utf8('Jefe'),
        BytesUtil.utf8('what do ya want for nothing?'));
      expect(BytesUtil.hexLower(mac)).assertEqual(
        '5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843');
    });

    it('C04_hkdfMatchesRfc5869Case1', 0, async () => {
      const ikm = new Uint8Array(22).fill(0x0b);
      const salt = BytesUtil.hexToBytes('000102030405060708090a0b0c');
      const info = BytesUtil.hexToBytes('f0f1f2f3f4f5f6f7f8f9');
      const okm = await crypto.hkdfSha256(ikm, salt, info, 42);
      expect(BytesUtil.hexLower(okm)).assertEqual(
        '3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf' +
        '34007208d5b887185865');
    });

    it('C04_pbkdf2At120kMatchesPublicVector', 0, async () => {
      const salt = BytesUtil.hexToBytes('000102030405060708090a0b0c0d0e0f');
      const derived = await crypto.pbkdf2Sha256(BytesUtil.utf8('password'), salt, 120000, 32);
      expect(BytesUtil.hexLower(derived)).assertEqual(
        '0a300026cc0ba55a240b894dd629b07d0fc4e091922bc91b7d711b092183a4f0');
    });

    it('C04_x25519Rfc7748SharedSecretAndCodecRoundTrip', 0, async () => {
      const alicePrivateRaw = BytesUtil.hexToBytes(
        '77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a');
      const bobPublicRaw = BytesUtil.hexToBytes(
        'de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f');
      const privateHandle = await crypto.importX25519PrivateRaw(alicePrivateRaw);
      const shared = await crypto.computeX25519(privateHandle, bobPublicRaw);
      expect(BytesUtil.hexLower(shared)).assertEqual(
        '4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742');

      const publicDer = X25519KeyCodec.rawToDerPublicKey(bobPublicRaw);
      expect(publicDer.length).assertEqual(44);
      expect(BytesUtil.hexLower(X25519KeyCodec.derToRawPublicKey(publicDer)))
        .assertEqual(BytesUtil.hexLower(bobPublicRaw));
      const privateDer = X25519KeyCodec.rawToDerPrivateKey(alicePrivateRaw);
      expect(privateDer.length).assertEqual(48);
      expect(BytesUtil.hexLower(X25519KeyCodec.derToRawPrivateKey(privateDer)))
        .assertEqual(BytesUtil.hexLower(alicePrivateRaw));
    });

    it('C04_aes256CtrContinuousStreamMatchesNistSp80038aF55', 0, async () => {
      const key = BytesUtil.hexToBytes(
        '603deb1015ca71be2b73aef0857d77811f352c073b6108d72d9810a30914dff4');
      const iv = BytesUtil.hexToBytes('f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff');
      const stream = await crypto.createAesCtrStream(key, iv);
      const first = await stream.process(
        BytesUtil.hexToBytes('6bc1bee22e409f96e93d7e117393172a'));
      expect(BytesUtil.hexLower(first)).assertEqual(
        '601ec313775789a5b7a7f504bbf3d228');
      const second = await stream.process(
        BytesUtil.hexToBytes('ae2d8a571e03ac9c9eb76fac45af8e51'));
      expect(BytesUtil.hexLower(second)).assertEqual(
        'f443e3ca4d62b59aca84e990cacaf5c5');
      const third = await stream.process(
        BytesUtil.hexToBytes('30c81c46a35ce411e5fbc1191a0a52ef'));
      expect(BytesUtil.hexLower(third)).assertEqual(
        '2b0930daa23de94ce87017ba2d84988d');
      expect(stream.bytesProcessed).assertEqual(48);
      stream.destroy();
      expect(stream.state).assertEqual('DESTROYED');
    });

    it('C04_aes256GcmZeroVectorAndTagMismatch', 0, async () => {
      const key = new Uint8Array(32);
      const iv = new Uint8Array(12);
      const aad = new Uint8Array(0);
      const plaintext = new Uint8Array(16);
      const sealed = await crypto.encryptAesGcm(key, iv, aad, plaintext);
      expect(BytesUtil.hexLower(sealed.ciphertext)).assertEqual(
        'cea7403d4d606b6e074ec5d3baf39d18');
      expect(BytesUtil.hexLower(sealed.tag)).assertEqual(
        '530f8afbc74536b9a963b4f1c4cb738b');
      const opened = await crypto.decryptAesGcm(key, iv, aad, sealed.ciphertext, sealed.tag);
      expect(opened.length).assertEqual(16);

      const tampered = new Uint8Array(sealed.tag);
      tampered[0] = tampered[0] ^ 0xff;
      let code: string = '';
      try {
        await crypto.decryptAesGcm(key, iv, aad, sealed.ciphertext, tampered);
      } catch (error) {
        code = String((error as Error).message);
      }
      expect(code).assertEqual('CRYPTO_TAG_MISMATCH');
    });

    it('C04_x25519RejectsWrongRawLength', 0, async () => {
      let code: string = '';
      try {
        await crypto.importX25519PublicRaw(new Uint8Array(31));
      } catch (error) {
        code = String((error as Error).message);
      }
      expect(code).assertEqual('CRYPTO_INVALID_KEY');
    });
  });
}
