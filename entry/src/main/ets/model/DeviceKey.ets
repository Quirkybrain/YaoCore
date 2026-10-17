/*
 * YaoCore C-02 two-level device identity.
 * Producer: agent:implementation-engineer | Task: T-06 / wp-012-foundation
 * Contract: DES-A §5.1.1/§5.3 invariant 1
 *
 * globalId is a derived value only. Persist gatewayId and deviceId separately;
 * never parse globalId back into its parts.
 */
import { AppErrors } from '../common/types/AppError';
import { ProtocolConstants } from '../common/constants/ProtocolConstants';

export class DeviceKey {
  readonly gatewayId: string;
  readonly deviceId: string;

  constructor(gatewayId: string, deviceId: string) {
    this.gatewayId = DeviceKey.validateId(gatewayId, 'gatewayId');
    this.deviceId = DeviceKey.validateId(deviceId, 'deviceId');
  }

  globalId(): string {
    return this.gatewayId + ':' + this.deviceId;
  }

  equals(other: DeviceKey): boolean {
    return this.gatewayId === other.gatewayId && this.deviceId === other.deviceId;
  }

  private static validateId(value: string, field: string): string {
    if (value.length === 0 || value.length > ProtocolConstants.MAX_DEVICE_ID_LENGTH) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', field);
    }
    // v1 forbids ':' in gateway/device identifiers (ADR-001 §5).
    if (value.indexOf(':') >= 0 || !ProtocolConstants.DEVICE_ID_PATTERN.test(value)) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', field);
    }
    return value;
  }
}
