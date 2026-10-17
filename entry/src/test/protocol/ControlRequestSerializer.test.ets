/*
 * YaoCore Hypium host suite: C-03 ControlRequestSerializer.
 * Producer: agent:implementation-engineer | Task: T-06 / wp-012-foundation
 * Traceability: DES-A §6.1.3/§18.1; V-01.
 *
 * HMAC is T-07; this suite uses a public vector signature only.
 */
import { describe, expect, it } from '@ohos/hypium';
import { ControlRequestSerializer } from '../../main/ets/service/protocol/ControlRequestSerializer';
import { Utf8 } from '../../main/ets/common/utils/Utf8';
import type { ControlRequestDto } from '../../main/ets/service/protocol/dto/ControlRequestDto';

const REQUEST: ControlRequestDto = {
  request_id: 'req-20260714-0001',
  cmd_id: 2001,
  seq: 10086,
  target: 'Light_01',
  payload: {
    action: 'SET_BRIGHTNESS',
    value: 68
  },
  timestamp: '20260714T080000Z',
  nonce: '9f2a7c001122',
  alg: 'HMAC-SHA256',
  key_id: 'app-key-v1',
  sign: '3555f16eeee3c30e0f79e967357f057d9a5387a8bf13aa2f8a32e80e944fbaae'
};

export function ControlRequestSerializerSuite(): void {
  describe('C03 ControlRequestSerializer', () => {
    it('C03_ControlRequestSerializer_emitsFixedFieldOrder', 0, () => {
      const text: string = Utf8.decode(ControlRequestSerializer.serialize(REQUEST));
      expect(text.indexOf('"request_id"') < text.indexOf('"cmd_id"')).assertTrue();
      expect(text.indexOf('"payload"') < text.indexOf('"timestamp"')).assertTrue();
      expect(text.indexOf('"sign"') > text.indexOf('"key_id"')).assertTrue();
      expect(text.endsWith('\n')).assertFalse();
      expect(text.includes('"value":68')).assertTrue();
    });

    it('C03_ControlRequestSerializer_rejectsUppercaseSign', 0, () => {
      const bad: ControlRequestDto = {
        request_id: 'req-20260714-0001',
        cmd_id: 2001,
        seq: 10086,
        target: 'Light_01',
        payload: {
          action: 'SET_BRIGHTNESS',
          value: 68
        },
        timestamp: '20260714T080000Z',
        nonce: '9f2a7c001122',
        alg: 'HMAC-SHA256',
        key_id: 'app-key-v1',
        sign: 'A'.repeat(64)
      };
      let code: string = '';
      try {
        ControlRequestSerializer.serialize(bad);
      } catch (error) {
        code = (error as Error).message;
      }
      expect(code).assertEqual('PROTOCOL_INVALID_IDENTIFIER');
    });
  });
}
