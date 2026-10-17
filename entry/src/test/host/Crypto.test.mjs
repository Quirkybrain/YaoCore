/*
 * YaoCore C-04 CryptoService host tests.
 * Producer: agent:implementation-engineer | Task: T-07 / wp-016-security
 * Traceability: DES-A §7.1, §7.2, §7.3; SC-15; RFC 7748; RFC 5869.
 *
 * PUBLIC TEST DATA ONLY. Product CryptoService runs over the independent
 * pure-TS TestCryptoProvider; Node crypto is a second oracle for SHA/HMAC/KDF
 * and for X25519 DER wrapping. Platform AES/X25519 execution remains
 * COMPILED_ONLY/device-BLOCKED (no device in this environment).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash, createHmac, createPrivateKey, createPublicKey, pbkdf2Sync } from 'node:crypto';

import { AppError } from '../../main/ets/common/types/AppError.ets';
import { CryptoService } from '../../main/ets/service/crypto/CryptoService.ets';
import {
  CryptoErrorKind,
  CryptoProviderError,
} from '../../main/ets/service/crypto/CryptoProvider.ets';
import { X25519KeyCodec } from '../../main/ets/service/crypto/X25519KeyCodec.ets';
import { TestCryptoProvider } from './TestCryptoProvider.ets';

const utf8 = (text) => new TextEncoder().encode(text);
const hex = (bytes) => Buffer.from(bytes).toString('hex');
const bytes = (value) => new Uint8Array(value);
const expectCode = (fn, code) => {
  assert.throws(fn, (error) => {
    assert.ok(error instanceof AppError, `expected AppError, got ${error}`);
    assert.equal(error.code, code, `expected ${code}, got ${error.code}`);
    return true;
  });
};
const expectCodeAsync = async (fn, code) => {
  await assert.rejects(fn, (error) => {
    assert.ok(error instanceof AppError, `expected AppError, got ${error}`);
    assert.equal(error.code, code, `expected ${code}, got ${error.code}`);
    return true;
  });
};

const service = new CryptoService(new TestCryptoProvider());
const b64url = (value) => Buffer.from(value).toString('base64url');

/** Fake provider for state/validation paths that need no real primitive. */
const fakeProvider = (overrides = {}) => {
  const fail = async () => {
    throw new CryptoProviderError(CryptoErrorKind.OPERATION_FAILED);
  };
  return {
    sha256: fail,
    hmacSha256: fail,
    hkdfSha256: fail,
    pbkdf2Sha256: fail,
    generateX25519KeyPair: fail,
    importX25519PrivateRaw: fail,
    importX25519PublicRaw: fail,
    exportX25519PublicRaw: fail,
    computeX25519: fail,
    createAesCtrStream: fail,
    encryptAesGcm: fail,
    decryptAesGcm: fail,
    randomBytes: fail,
    ...overrides,
  };
};

test('C04_CryptoService_sha256MatchesNodeOracle', async () => {
  for (const sample of ['', 'abc', '制冷', 'a'.repeat(1000)]) {
    const actual = hex(await service.sha256(utf8(sample)));
    const expected = createHash('sha256').update(sample, 'utf8').digest('hex');
    assert.equal(actual, expected, JSON.stringify(sample.slice(0, 12)));
  }
});

test('C04_CryptoService_hmacSha256MatchesNodeOracle', async () => {
  const cases = [
    ['YaoCore-Contract-Secret-v2', 'hello'],
    ['0123456789abcdef', ''],
    ['k'.repeat(100), 'long-key-hmac-block-boundary'],
  ];
  for (const [key, message] of cases) {
    const actual = hex(await service.hmacSha256(utf8(key), utf8(message)));
    const expected = createHmac('sha256', key).update(message, 'utf8').digest('hex');
    assert.equal(actual, expected);
  }
});

test('C04_CryptoService_hkdfSha256MatchesRfc5869Case1', async () => {
  const inputKeyMaterial = new Uint8Array(22).fill(0x0b);
  const salt = new Uint8Array([
    0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
    0x08, 0x09, 0x0a, 0x0b, 0x0c,
  ]);
  const info = new Uint8Array([
    0xf0, 0xf1, 0xf2, 0xf3, 0xf4, 0xf5, 0xf6, 0xf7, 0xf8, 0xf9,
  ]);
  const okm = await service.hkdfSha256(inputKeyMaterial, salt, info, 42);
  assert.equal(
    hex(okm),
    '3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf' +
      '34007208d5b887185865',
  );
});

test('C04_CryptoService_pbkdf2Sha256MatchesNodeOracleAtContractMinimum', async () => {
  const salt = new Uint8Array([
    0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
    0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f,
  ]);
  const actual = await service.pbkdf2Sha256(utf8('password'), salt, 120000, 32);
  const expected = pbkdf2Sync('password', Buffer.from(salt), 120000, 32, 'sha256');
  assert.equal(hex(actual), expected.toString('hex'));
});

test('C04_CryptoService_kdfParametersFailClosed', async () => {
  const salt16 = new Uint8Array(16);
  await expectCodeAsync(() => service.pbkdf2Sha256(utf8('p'), salt16, 119999, 32),
    'PROTOCOL_VALUE_OUT_OF_RANGE');
  await expectCodeAsync(() => service.pbkdf2Sha256(utf8('p'), salt16, 120000, 31),
    'PROTOCOL_VALUE_OUT_OF_RANGE');
  await expectCodeAsync(() => service.pbkdf2Sha256(utf8('p'), new Uint8Array(15), 120000, 32),
    'CRYPTO_INVALID_KEY');
  await expectCodeAsync(() => service.hkdfSha256(new Uint8Array(1), new Uint8Array(0),
    new Uint8Array(0), 0), 'PROTOCOL_VALUE_OUT_OF_RANGE');
  await expectCodeAsync(() => service.hkdfSha256(new Uint8Array(1), new Uint8Array(0),
    new Uint8Array(0), 8161), 'PROTOCOL_VALUE_OUT_OF_RANGE');
});

test('C04_X25519KeyCodec_wrapsRfc7748RawKeysAsValidDer', () => {
  const alicePrivate = new Uint8Array(Buffer.from(
    '77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a', 'hex'));
  const alicePublic = new Uint8Array(Buffer.from(
    '8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a', 'hex'));

  const publicDer = X25519KeyCodec.rawToDerPublicKey(alicePublic);
  assert.equal(hex(publicDer.subarray(0, 12)), '302a300506032b656e032100');
  assert.equal(publicDer.length, 44);

  const privateDer = X25519KeyCodec.rawToDerPrivateKey(alicePrivate);
  assert.equal(hex(privateDer.subarray(0, 16)), '302e020100300506032b656e04220420');
  assert.equal(privateDer.length, 48);

  // Independent oracle: Node must accept the wrappers and expose the same raw
  // bytes in JWK form.
  const publicKey = createPublicKey({ key: Buffer.from(publicDer), format: 'der', type: 'spki' });
  const publicJwk = publicKey.export({ format: 'jwk' });
  assert.equal(publicJwk.x, b64url(alicePublic));

  const privateKey = createPrivateKey({
    key: Buffer.from(privateDer), format: 'der', type: 'pkcs8',
  });
  const privateJwk = privateKey.export({ format: 'jwk' });
  assert.equal(privateJwk.d, b64url(alicePrivate));
  assert.equal(privateJwk.x, b64url(alicePublic));

  assert.equal(hex(X25519KeyCodec.derToRawPublicKey(publicDer)), hex(alicePublic));
  assert.equal(hex(X25519KeyCodec.derToRawPrivateKey(privateDer)), hex(alicePrivate));
});

test('C04_X25519KeyCodec_rejectsLengthPrefixAndTrailingData', () => {
  const raw = new Uint8Array(32).fill(7);
  const publicDer = X25519KeyCodec.rawToDerPublicKey(raw);
  const privateDer = X25519KeyCodec.rawToDerPrivateKey(raw);

  expectCode(() => X25519KeyCodec.rawToDerPublicKey(new Uint8Array(31)), 'CRYPTO_INVALID_KEY');
  expectCode(() => X25519KeyCodec.rawToDerPrivateKey(new Uint8Array(33)), 'CRYPTO_INVALID_KEY');
  expectCode(() => X25519KeyCodec.derToRawPublicKey(publicDer.subarray(0, 43)),
    'CRYPTO_INVALID_KEY');
  const trailing = new Uint8Array(publicDer.length + 1);
  trailing.set(publicDer);
  expectCode(() => X25519KeyCodec.derToRawPublicKey(trailing), 'CRYPTO_INVALID_KEY');
  const wrongPrefix = new Uint8Array(publicDer);
  wrongPrefix[0] = 0x31;
  expectCode(() => X25519KeyCodec.derToRawPublicKey(wrongPrefix), 'CRYPTO_INVALID_KEY');
  expectCode(() => X25519KeyCodec.derToRawPrivateKey(publicDer), 'CRYPTO_INVALID_KEY');
  expectCode(() => X25519KeyCodec.derToRawPublicKey(privateDer), 'CRYPTO_INVALID_KEY');
});

test('C04_CryptoService_x25519InputsAndZeroSharedSecretFailClosed', async () => {
  const valid = new Uint8Array(32).fill(1);
  await expectCodeAsync(() => service.importX25519PrivateRaw(new Uint8Array(31)),
    'CRYPTO_INVALID_KEY');
  await expectCodeAsync(() => service.importX25519PublicRaw(new Uint8Array(33)),
    'CRYPTO_INVALID_KEY');
  await expectCodeAsync(() => service.exportX25519PublicRaw({ algorithm: 'ED25519' }),
    'CRYPTO_INVALID_KEY');

  const handle = { algorithm: 'X25519' };
  await expectCodeAsync(() => service.computeX25519(handle, new Uint8Array(31)),
    'CRYPTO_INVALID_KEY');
  const zeroProvider = fakeProvider({
    computeX25519: async () => new Uint8Array(32),
  });
  await expectCodeAsync(() => new CryptoService(zeroProvider).computeX25519(handle, valid),
    'CRYPTO_INVALID_KEY');
  const unavailable = fakeProvider({
    importX25519PublicRaw: async () => {
      throw new CryptoProviderError(CryptoErrorKind.UNAVAILABLE);
    },
  });
  await expectCodeAsync(() => new CryptoService(unavailable).importX25519PublicRaw(valid),
    'CRYPTO_UNAVAILABLE');
});

test('C04_CryptoService_constantTimeEqualHandlesEveryShape', () => {
  const left = bytes([1, 2, 3, 4]);
  assert.equal(service.constantTimeEqual(left, bytes([1, 2, 3, 4])), true);
  assert.equal(service.constantTimeEqual(left, bytes([9, 2, 3, 4])), false);
  assert.equal(service.constantTimeEqual(left, bytes([1, 2, 3, 9])), false);
  assert.equal(service.constantTimeEqual(left, bytes([1, 2, 3])), false);
  assert.equal(service.constantTimeEqual(bytes([1, 2, 3]), left), false);
  assert.equal(service.constantTimeEqual(new Uint8Array(0), new Uint8Array(0)), true);
});

test('C04_CryptoService_ctrStreamIsContinuousAndTerminalOnFailure', async () => {
  const calls = [];
  const fake = fakeProvider({
    createAesCtrStream: async () => ({
      process: async (data) => {
        calls.push(Array.from(data));
        return new Uint8Array(data.length).fill(0xaa);
      },
      destroy: () => {
        calls.push('destroy');
      },
    }),
  });
  const ctrService = new CryptoService(fake);
  await expectCodeAsync(() => ctrService.createAesCtrStream(new Uint8Array(31), new Uint8Array(16)),
    'CRYPTO_INVALID_KEY');
  await expectCodeAsync(() => ctrService.createAesCtrStream(new Uint8Array(32), new Uint8Array(15)),
    'CRYPTO_INVALID_KEY');

  const stream = await ctrService.createAesCtrStream(new Uint8Array(32), new Uint8Array(16));
  assert.equal(stream.state, 'ACTIVE');
  assert.equal(stream.bytesProcessed, 0);
  const first = await stream.process(bytes([1, 2, 3]));
  assert.equal(first.length, 3);
  assert.equal(stream.bytesProcessed, 3);
  const second = await stream.process(bytes([4, 5]));
  assert.equal(second.length, 2);
  assert.equal(stream.bytesProcessed, 5);
  stream.destroy();
  assert.equal(stream.state, 'DESTROYED');
  await expectCodeAsync(() => stream.process(bytes([6])), 'CRYPTO_STREAM_BROKEN');
  assert.deepEqual(calls[0], [1, 2, 3]);
  assert.deepEqual(calls[1], [4, 5]);

  let destroyed = false;
  const failing = fakeProvider({
    createAesCtrStream: async () => ({
      process: async () => {
        throw new CryptoProviderError(CryptoErrorKind.OPERATION_FAILED);
      },
      destroy: () => {
        destroyed = true;
      },
    }),
  });
  const broken = await new CryptoService(failing)
    .createAesCtrStream(new Uint8Array(32), new Uint8Array(16));
  await expectCodeAsync(() => broken.process(bytes([1])), 'CRYPTO_OPERATION_FAILED');
  assert.equal(broken.state, 'BROKEN');
  assert.equal(destroyed, true);
  await expectCodeAsync(() => broken.process(bytes([2])), 'CRYPTO_STREAM_BROKEN');
  assert.equal(broken.bytesProcessed, 0);
});

test('C04_CryptoService_ctrRejectsOutputLengthMismatch', async () => {
  const bad = fakeProvider({
    createAesCtrStream: async () => ({
      process: async (data) => new Uint8Array(data.length + 1),
      destroy: () => {},
    }),
  });
  const stream = await new CryptoService(bad)
    .createAesCtrStream(new Uint8Array(32), new Uint8Array(16));
  await expectCodeAsync(() => stream.process(bytes([1, 2])), 'CRYPTO_OPERATION_FAILED');
  assert.equal(stream.state, 'BROKEN');
});

test('C04_CryptoService_gcmValidationAndTagMismatchFailClosed', async () => {
  const key = new Uint8Array(32).fill(3);
  const iv = new Uint8Array(12).fill(4);
  const aad = new Uint8Array(0);
  const plaintext = bytes([1, 2, 3, 4]);
  const good = fakeProvider({
    encryptAesGcm: async () => ({
      ciphertext: bytes([9, 8, 7, 6]),
      tag: new Uint8Array(16).fill(5),
    }),
    decryptAesGcm: async () => {
      throw new CryptoProviderError(CryptoErrorKind.AUTH_TAG);
    },
  });
  const gcmService = new CryptoService(good);
  const sealed = await gcmService.encryptAesGcm(key, iv, aad, plaintext);
  assert.equal(sealed.ciphertext.length, 4);
  assert.equal(sealed.tag.length, 16);
  await expectCodeAsync(() => gcmService.decryptAesGcm(key, iv, aad, sealed.ciphertext, sealed.tag),
    'CRYPTO_TAG_MISMATCH');
  await expectCodeAsync(() => gcmService.encryptAesGcm(new Uint8Array(31), iv, aad, plaintext),
    'CRYPTO_INVALID_KEY');
  await expectCodeAsync(() => gcmService.encryptAesGcm(key, new Uint8Array(11), aad, plaintext),
    'CRYPTO_INVALID_KEY');
  await expectCodeAsync(() => gcmService.decryptAesGcm(key, iv, aad, sealed.ciphertext,
    new Uint8Array(15)), 'CRYPTO_INVALID_KEY');

  const wrongLength = fakeProvider({
    encryptAesGcm: async () => ({
      ciphertext: bytes([1, 2, 3]),
      tag: new Uint8Array(16),
    }),
  });
  await expectCodeAsync(() => new CryptoService(wrongLength)
    .encryptAesGcm(key, iv, aad, plaintext), 'CRYPTO_OPERATION_FAILED');
});

test('C04_CryptoService_randomBytesContractIsExactAndNonZero', async () => {
  const valid = fakeProvider({ randomBytes: async (length) => new Uint8Array(length).fill(9) });
  const randomService = new CryptoService(valid);
  assert.equal((await randomService.randomBytes(16)).length, 16);
  await expectCodeAsync(() => randomService.randomBytes(0), 'PROTOCOL_VALUE_OUT_OF_RANGE');
  await expectCodeAsync(() => randomService.randomBytes(-1), 'PROTOCOL_VALUE_OUT_OF_RANGE');

  const short = fakeProvider({ randomBytes: async () => new Uint8Array(15) });
  await expectCodeAsync(() => new CryptoService(short).randomBytes(16), 'CRYPTO_OPERATION_FAILED');
  const zero = fakeProvider({ randomBytes: async (length) => new Uint8Array(length) });
  await expectCodeAsync(() => new CryptoService(zero).randomBytes(16), 'CRYPTO_OPERATION_FAILED');
  const broken = fakeProvider({
    randomBytes: async () => {
      throw new CryptoProviderError(CryptoErrorKind.UNAVAILABLE);
    },
  });
  await expectCodeAsync(() => new CryptoService(broken).randomBytes(16), 'CRYPTO_UNAVAILABLE');
});

test('C04_CryptoService_inputLengthMismatchFromProviderFailsClosed', async () => {
  const badSha = fakeProvider({ sha256: async () => new Uint8Array(31) });
  await expectCodeAsync(() => new CryptoService(badSha).sha256(utf8('x')),
    'CRYPTO_OPERATION_FAILED');
  const badHmac = fakeProvider({ hmacSha256: async () => new Uint8Array(33) });
  await expectCodeAsync(() => new CryptoService(badHmac).hmacSha256(utf8('k'), utf8('x')),
    'CRYPTO_OPERATION_FAILED');
  const unavailable = fakeProvider({
    sha256: async () => {
      throw new CryptoProviderError(CryptoErrorKind.UNAVAILABLE);
    },
  });
  await expectCodeAsync(() => new CryptoService(unavailable).sha256(utf8('x')),
    'CRYPTO_UNAVAILABLE');
});
