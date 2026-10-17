/*
 * YaoCore C-01 foundation host tests.
 * Producer: agent:implementation-engineer | Task: T-06 / wp-012-foundation
 * Traceability: DES-A §3.2, §3.3, §3.4, §4, §18.6; D-019 host layer.
 *
 * Public test data only. No secrets, no device, no @ohos.*.
 */
import test from 'node:test';
import assert from 'node:assert/strict';

import {
  AppError,
  AppErrors,
  ErrorCategory,
  ErrorCatalog,
} from '../../main/ets/common/types/AppError.ets';
import { Result } from '../../main/ets/common/types/Result.ets';
import {
  GatewayResultClassifier,
  GatewayResultCode,
} from '../../main/ets/common/types/GatewayResult.ets';
import { DateTimeUtil } from '../../main/ets/common/utils/DateTimeUtil.ets';
import { BytesUtil } from '../../main/ets/common/utils/BytesUtil.ets';
import { Base64Url } from '../../main/ets/common/utils/Base64Url.ets';
import { Utf8 } from '../../main/ets/common/utils/Utf8.ets';
import { JsonAtom } from '../../main/ets/common/utils/JsonAtom.ets';
import { JsonParser, JsonLimits } from '../../main/ets/common/utils/JsonParser.ets';
import { JsonCanonicalizer } from '../../main/ets/common/utils/JsonCanonicalizer.ets';
import { HttpHeaders } from '../../main/ets/common/types/HttpHeaders.ets';
import { NameValue } from '../../main/ets/common/types/NameValue.ets';
import { SecureBytes } from '../../main/ets/common/types/SecureBytes.ets';
import { UuidUtil } from '../../main/ets/common/utils/UuidUtil.ets';
import { IpAddressUtil } from '../../main/ets/common/utils/IpAddressUtil.ets';

const expectCode = (fn, code) => {
  assert.throws(fn, (error) => {
    assert.ok(error instanceof AppError, `expected AppError, got ${error}`);
    assert.equal(error.code, code, `expected ${code}, got ${error.code}`);
    return true;
  });
};

test('C01_AppError_catalogCarriesCategoryRetryableAndI18nKey', () => {
  const error = AppErrors.protocol('PROTOCOL_INVALID_JSON', 'payload');
  assert.ok(error instanceof AppError);
  assert.equal(error.code, 'PROTOCOL_INVALID_JSON');
  assert.equal(error.category, ErrorCategory.PROTOCOL);
  assert.equal(error.retryable, false);
  assert.equal(error.i18nKey, 'errors.app.protocol_invalid_json');
  assert.deepEqual(error.details.map((item) => [item.name, item.value]), [['field', 'payload']]);

  const timeout = AppErrors.of('TIMESTAMP_OUT_OF_WINDOW');
  assert.equal(timeout.category, ErrorCategory.SECURITY);
  assert.equal(timeout.retryable, true);
  assert.equal(timeout.i18nKey, 'errors.app.timestamp_out_of_window');

  const http = ErrorCatalog.resolve('HTTP_503');
  assert.equal(http.i18nKey, 'errors.app.http_error');
  assert.equal(http.retryable, true);
  assert.equal(ErrorCatalog.resolve('HTTP_404').retryable, false);
  assert.equal(ErrorCatalog.resolve('PROVISIONING_WIFI_AUTH_ERROR').i18nKey,
    'provisioning.error.auth_error');
  assert.equal(ErrorCatalog.resolve('INVITE_VERSION_UNSUPPORTED').i18nKey,
    'errors.app.invite_invalid');
  assert.equal(ErrorCatalog.resolve('INVITE_AEAD_FAILED').i18nKey,
    'errors.app.invite_invalid');
  assert.equal(ErrorCatalog.resolve('UNKNOWN_FUTURE_CODE').category, ErrorCategory.INTERNAL);
});

test('C01_Result_neverSwallowsAppError', () => {
  const success = Result.ok(5);
  assert.equal(success.ok, true);
  assert.equal(success.value, 5);
  assert.equal(success.error, undefined);

  const failure = Result.fail(AppErrors.protocol('PROTOCOL_MISSING_FIELD', 'x'));
  assert.equal(failure.ok, false);
  assert.equal(failure.value, undefined);
  assert.equal(failure.error.code, 'PROTOCOL_MISSING_FIELD');
});

test('C01_DateTimeUtil_roundTripsSecondsAndValidatesCalendar', () => {
  assert.equal(DateTimeUtil.formatUtcCompact(0), '19700101T000000Z');
  assert.equal(DateTimeUtil.parseUtcCompact('19700101T000000Z'), 0);
  assert.equal(DateTimeUtil.formatUtcCompact(1234), '19700101T000001Z');
  assert.equal(DateTimeUtil.parseUtcCompact(DateTimeUtil.formatUtcCompact(1234)), 1000);
  assert.equal(DateTimeUtil.formatUtcCompact(Date.UTC(2024, 1, 29, 23, 59, 59)),
    '20240229T235959Z');
  assert.equal(DateTimeUtil.parseUtcCompact('20240229T235959Z'),
    Date.UTC(2024, 1, 29, 23, 59, 59));
  assert.equal(DateTimeUtil.parseUtcCompact('20000229T000000Z'),
    Date.UTC(2000, 1, 29, 0, 0, 0));

  for (const invalid of [
    '20230229T000000Z',
    '20261301T000000Z',
    '20260132T000000Z',
    '20260101T240000Z',
    '20260101T006000Z',
    '20260101T000060Z',
    '2026-01-01T000000Z',
    '20260101T000000',
    '20260101T000000Z ',
  ]) {
    expectCode(() => DateTimeUtil.parseUtcCompact(invalid), 'PROTOCOL_INVALID_TIMESTAMP');
  }
  expectCode(() => DateTimeUtil.formatUtcCompact(Number.NaN), 'PROTOCOL_INVALID_TIMESTAMP');
});

test('C01_DateTimeUtil_windowIsInclusiveAt120000ms', () => {
  const now = 1700000000000;
  assert.equal(DateTimeUtil.isWithinWindow(now, now, 120000), true);
  assert.equal(DateTimeUtil.isWithinWindow(now, now + 120000, 120000), true);
  assert.equal(DateTimeUtil.isWithinWindow(now, now - 120000, 120000), true);
  assert.equal(DateTimeUtil.isWithinWindow(now, now + 120001, 120000), false);
  assert.equal(DateTimeUtil.isWithinWindow(now, now - 120001, 120000), false);
  assert.equal(DateTimeUtil.isWithinWindow(now, now, 0), true);
  assert.equal(DateTimeUtil.isWithinWindow(now, now + 1, 0), false);
});

test('C01_DateTimeUtil_requestIdUsesMillisAndSeq', () => {
  const id = DateTimeUtil.formatRequestId(1729000000000, 7);
  assert.equal(id, 'req-1729000000000-7');
  assert.match(id, /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,126}$/);
  expectCode(() => DateTimeUtil.formatRequestId(1729000000000, -1), 'PROTOCOL_VALUE_OUT_OF_RANGE');
  expectCode(() => DateTimeUtil.formatRequestId(1729000000000, 2147483648),
    'PROTOCOL_VALUE_OUT_OF_RANGE');
  expectCode(() => DateTimeUtil.formatRequestId(Number.NaN, 1), 'PROTOCOL_VALUE_OUT_OF_RANGE');
});

test('C01_BytesUtil_hexRoundTripsAndStrictLowerRejectsUppercase', () => {
  assert.equal(BytesUtil.hexLower(new Uint8Array([])), '');
  assert.equal(BytesUtil.hexLower(new Uint8Array([0x00, 0x0f, 0xff])), '000fff');
  assert.deepEqual(Array.from(BytesUtil.hexToBytes('00ffAB')), [0x00, 0xff, 0xab]);
  assert.deepEqual(Array.from(BytesUtil.hexToBytesStrictLower('00ffab')), [0x00, 0xff, 0xab]);
  expectCode(() => BytesUtil.hexToBytesStrictLower('00FF'), 'SECRET_ENCODING_INVALID');
  expectCode(() => BytesUtil.hexToBytes('abc'), 'SECRET_ENCODING_INVALID');
  expectCode(() => BytesUtil.hexToBytes('zz'), 'SECRET_ENCODING_INVALID');

  const source = new Uint8Array([1, 2, 3]);
  const copy = BytesUtil.copyOf(source);
  copy[0] = 9;
  assert.equal(source[0], 1);
  BytesUtil.zeroize(copy);
  assert.deepEqual(Array.from(copy), [0, 0, 0]);
  assert.deepEqual(Array.from(BytesUtil.concat([new Uint8Array([1]), new Uint8Array([2, 3])])),
    [1, 2, 3]);
});

test('C01_Utf8_isStrictAndRoundTripsUnicode', () => {
  assert.equal(Utf8.decode(Utf8.encode('YaoCore 制冷 😀')), 'YaoCore 制冷 😀');
  assert.deepEqual(Array.from(Utf8.encode('A')), [0x41]);
  assert.deepEqual(Array.from(Utf8.encode('é')), [0xc3, 0xa9]);
  expectCode(() => Utf8.encode('\ud800'), 'PROTOCOL_INVALID_JSON');
  expectCode(() => Utf8.encode('\udc00'), 'PROTOCOL_INVALID_JSON');
  expectCode(() => Utf8.decode(new Uint8Array([0xc0, 0x80])), 'PROTOCOL_INVALID_JSON');
  expectCode(() => Utf8.decode(new Uint8Array([0xe2, 0x82])), 'PROTOCOL_INVALID_JSON');
  expectCode(() => Utf8.decode(new Uint8Array([0xed, 0xa0, 0x80])), 'PROTOCOL_INVALID_JSON');
  expectCode(() => Utf8.decode(new Uint8Array([0xf5, 0x80, 0x80, 0x80])), 'PROTOCOL_INVALID_JSON');
});

test('C01_Base64Url_isUnpaddedAndStrict', () => {
  assert.equal(Base64Url.encode(new Uint8Array([])), '');
  assert.equal(Base64Url.encode(BytesUtil.utf8('f')), 'Zg');
  assert.equal(Base64Url.encode(BytesUtil.utf8('fo')), 'Zm8');
  assert.equal(Base64Url.encode(BytesUtil.utf8('foo')), 'Zm9v');
  assert.equal(Base64Url.encode(new Uint8Array([0xfb, 0xff])), '-_8');
  assert.deepEqual(Array.from(Base64Url.decode('-_8')), [0xfb, 0xff]);
  assert.equal(BytesUtil.fromUtf8(Base64Url.decode(Base64Url.encode(BytesUtil.utf8('YaoCore')))),
    'YaoCore');
  assert.equal(Base64Url.encode(new Uint8Array([])), '');
  expectCode(() => Base64Url.decode(''), 'SECRET_ENCODING_INVALID');
  assert.equal(Base64Url.isValid(''), false);
  assert.equal(Base64Url.isValid('Zm9v'), true);
  assert.equal(Base64Url.isValid('Zm9v='), false);
  assert.equal(Base64Url.isValid('a'), false);
  assert.equal(Base64Url.isValid('ab'), false);
  expectCode(() => Base64Url.decode('a+b/'), 'SECRET_ENCODING_INVALID');
});

test('C01_JsonAtom_matchesCanonicalValueRules', () => {
  assert.equal(JsonAtom.encode(undefined), '');
  assert.equal(JsonAtom.encode('制冷'), '"制冷"');
  assert.equal(JsonAtom.encode('a"b\\c\n'), '"a\\"b\\\\c\\n"');
  assert.equal(JsonAtom.encode(true), 'true');
  assert.equal(JsonAtom.encode(false), 'false');
  assert.equal(JsonAtom.encode(24), '24');
  assert.equal(JsonAtom.encode(24.5), '24.5');
  expectCode(() => JsonAtom.encode(Number.NaN), 'PROTOCOL_INVALID_TYPE');
  expectCode(() => JsonAtom.encode(Number.POSITIVE_INFINITY), 'PROTOCOL_INVALID_TYPE');
  expectCode(() => JsonAtom.encode(null), 'PROTOCOL_INVALID_TYPE');
});

test('C01_JsonParser_rejectsMalformedOrAmbiguousInput', () => {
  expectCode(() => JsonParser.parse('{"a":1,"a":2}'), 'PROTOCOL_DUPLICATE_KEY');
  expectCode(() => JsonParser.parse('{"a":1} trailing'), 'PROTOCOL_INVALID_JSON');
  expectCode(() => JsonParser.parse('NaN'), 'PROTOCOL_INVALID_JSON');
  expectCode(() => JsonParser.parse('Infinity'), 'PROTOCOL_INVALID_JSON');
  expectCode(() => JsonParser.parse('01'), 'PROTOCOL_INVALID_JSON');
  expectCode(() => JsonParser.parse('"line\nbreak"'), 'PROTOCOL_INVALID_JSON');
  expectCode(() => JsonParser.parse('"\\ud800"'), 'PROTOCOL_INVALID_JSON');
  expectCode(() => JsonParser.parse('"\\udc00"'), 'PROTOCOL_INVALID_JSON');
  expectCode(() => JsonParser.parse('"\\uZZZZ"'), 'PROTOCOL_INVALID_JSON');
  expectCode(() => JsonParser.parse('[[[[1]]]]', new JsonLimits(65536, 3, 8192)),
    'PROTOCOL_BODY_TOO_LARGE');
  expectCode(() => JsonParser.parse('{"a":1}', new JsonLimits(4, 16, 8192)),
    'PROTOCOL_BODY_TOO_LARGE');
  expectCode(() => JsonParser.parse('"abc"', new JsonLimits(65536, 16, 2)),
    'PROTOCOL_BODY_TOO_LARGE');

  const node = JsonParser.parse('{"b":1,"a":[true,null,"x"]}');
  assert.deepEqual(node.keys(), ['b', 'a']);
  assert.equal(node.get('b').numberValue, 1);
  assert.equal(node.get('a').arrayValue.length, 3);
  assert.equal(node.get('a').arrayValue[0].booleanValue, true);
  assert.equal(node.get('a').arrayValue[1].kind, 'NULL');
  assert.equal(node.get('a').arrayValue[2].stringValue, 'x');
  expectCode(() => node.require('missing'), 'PROTOCOL_MISSING_FIELD');
});

test('C01_JsonCanonicalizer_isCompactAndSupportsSortedKeys', () => {
  const node = JsonParser.parse('{"b":1,"a":{"d":true,"c":"x"}}');
  assert.equal(JsonCanonicalizer.stringify(node, false), '{"b":1,"a":{"d":true,"c":"x"}}');
  assert.equal(JsonCanonicalizer.stringifySorted(node), '{"a":{"c":"x","d":true},"b":1}');
  assert.equal(JsonCanonicalizer.stringify(JsonParser.parse('"a\\"b"'), false), '"a\\"b"');
});

test('C01_HttpHeaders_areCaseInsensitiveAndLastWins', () => {
  const headers = HttpHeaders.from([
    new NameValue('Content-Type', 'application/json'),
    new NameValue('X-Test', 'first'),
    new NameValue('x-test', 'second'),
  ]);
  assert.equal(headers.get('content-type'), 'application/json');
  assert.equal(headers.get('X-TEST'), 'second');
  assert.equal(headers.has('x-test'), true);
  assert.equal(headers.entries().length, 3);
  expectCode(() => headers.require('Missing'), 'PROTOCOL_MISSING_FIELD');

  const map = new Map();
  map.set('A', '1');
  const fromMap = HttpHeaders.fromMap(map);
  assert.equal(fromMap.get('a'), '1');
});

test('C01_GatewayResultClassifier_separatesGatewayNamespace', () => {
  assert.equal(GatewayResultClassifier.classify(0).success, true);
  assert.equal(GatewayResultClassifier.classify(0).known, true);
  assert.equal(GatewayResultClassifier.classify(1004).stableName, 'bad_signature');
  assert.equal(GatewayResultClassifier.classify(1004).success, false);
  assert.equal(GatewayResultClassifier.classify(1007).retryable, true);
  assert.equal(GatewayResultClassifier.classify(1008).retryable, true);
  assert.equal(GatewayResultClassifier.classify(1005).retryable, false);
  const unknown = GatewayResultClassifier.classify(9999, 'whatever');
  assert.equal(unknown.known, false);
  assert.equal(unknown.success, false);
  assert.equal(unknown.retryable, false);
  assert.equal(unknown.stableName, 'unknown_9999');
  assert.equal(unknown.i18nKey, 'errors.gateway.unknown');
  assert.equal(GatewayResultClassifier.classify(GatewayResultCode.SUCCESS).success, true);
});

test('C01_IpAddressUtil_validatesLanAddresses', () => {
  assert.equal(IpAddressUtil.isValidIpv4('192.168.1.10'), true);
  assert.equal(IpAddressUtil.isValidIpv4('10.0.0.1'), true);
  assert.equal(IpAddressUtil.isValidIpv4('256.0.0.1'), false);
  assert.equal(IpAddressUtil.isValidIpv4('192.168.01.1'), false);
  assert.equal(IpAddressUtil.isValidIpv4('192.168.1'), false);
  assert.equal(IpAddressUtil.isAllowedLanIpv4('192.168.1.10'), true);
  assert.equal(IpAddressUtil.isAllowedLanIpv4('0.0.0.0'), false);
  assert.equal(IpAddressUtil.isAllowedLanIpv4('127.0.0.1'), false);
  assert.equal(IpAddressUtil.isAllowedLanIpv4('169.254.1.1'), false);
  assert.equal(IpAddressUtil.isAllowedLanIpv4('224.0.0.1'), false);
  assert.equal(IpAddressUtil.isAllowedLanIpv4('255.255.255.255'), false);
  assert.equal(IpAddressUtil.isValidPort(1), true);
  assert.equal(IpAddressUtil.isValidPort(65535), true);
  assert.equal(IpAddressUtil.isValidPort(0), false);
  assert.equal(IpAddressUtil.format('192.168.1.10', 9200), '192.168.1.10:9200');
});

test('C01_SecureBytes_zeroizesAndRejectsUseAfterDestroy', () => {
  const secret = SecureBytes.fromHex('00112233');
  assert.equal(secret.length, 4);
  assert.equal(secret.toHex(), '00112233');
  secret.withView((view) => {
    assert.deepEqual(Array.from(view), [0x00, 0x11, 0x22, 0x33]);
  });
  secret.destroy();
  secret.destroy();
  expectCode(() => secret.withView(() => 1), 'SECRET_DESTROYED');
  expectCode(() => secret.toHex(), 'SECRET_DESTROYED');
});

test('C01_UuidUtil_usesInjectedIdPort', () => {
  const uuid = '123e4567-e89b-12d3-a456-426614174000';
  const ids = { newId: () => uuid };
  assert.equal(UuidUtil.newUuid(ids), uuid);
  assert.equal(UuidUtil.isValidUuid(uuid), true);
  assert.equal(UuidUtil.isValidUuid('not-a-uuid'), false);
  expectCode(() => UuidUtil.newUuid({ newId: () => 'bad' }), 'INTERNAL_ERROR');
});
