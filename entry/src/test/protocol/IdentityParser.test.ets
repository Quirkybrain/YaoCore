/*
 * YaoCore Hypium host suite: C-03 IdentityParser.
 * Producer: agent:implementation-engineer | Task: T-06 / wp-012-foundation
 * Traceability: DES-A §6.1.5; PR-07; SEC-N21.
 */
import { describe, expect, it } from '@ohos/hypium';
import { IdentityParser } from '../../main/ets/service/protocol/IdentityParser';
import { Utf8 } from '../../main/ets/common/utils/Utf8';
import { IdentityVersion } from '../../main/ets/model/ProvisioningModels';

const VALID: string = '{"protocolVersion":"2.0","serviceId":"YaoCoreGateway",' +
  '"gatewayId":"gateway_01","gatewayName":"YaoCore Gateway"}';

const EXTRA: string = '{"protocolVersion":"2.0","serviceId":"YaoCoreGateway",' +
  '"gatewayId":"gateway_01","gatewayName":"YaoCore Gateway","extra":true}';

export function IdentityParserSuite(): void {
  describe('C03 IdentityParser', () => {
    it('C03_IdentityParser_v20AcceptsFourFields', 0, () => {
      const dto = IdentityParser.parseV20(Utf8.encode(VALID));
      expect(dto.protocolVersion).assertEqual('2.0');
      expect(dto.serviceId).assertEqual('YaoCoreGateway');
      expect(dto.gatewayId).assertEqual('gateway_01');
    });

    it('C03_IdentityParser_v20ExtraFieldFailsClosed', 0, () => {
      let code: string = '';
      try {
        IdentityParser.parseV20(Utf8.encode(EXTRA));
      } catch (error) {
        code = (error as Error).message;
      }
      expect(code).assertEqual('PROVISIONING_IDENTITY_INVALID');
    });

    it('C03_IdentityParser_serializesGetIdentity', 0, () => {
      expect(Utf8.decode(IdentityParser.serializeRequest(IdentityVersion.V20)))
        .assertEqual('{"op":"get_identity","protocolVersion":"2.0"}');
    });
  });
}
