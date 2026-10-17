/*
 * YaoCore C-15 shadow DTO adapter.
 * Producer: agent:implementation-engineer | Task: T-14 / wp-055-cloud
 * Contract: DES-B §8.1.5, §8.4; A-CB-1
 *
 * Reuses the C-03 strict state-report mapper for the three accepted shapes
 * (SERVICES/SHADOW/DEVICES). The mapper already rejects unknown shapes,
 * non-object properties, invalid event_time and future clock skew. This
 * adapter adds the 64 KiB body cap, SHA-256 diagnostics and the PB-02
 * DeviceInventoryJson fail-closed split: a malformed inventory never blocks
 * completion of the built-in fixed-property path.
 */
import { AppError } from '../../common/types/AppError';
import { NameValue } from '../../common/types/NameValue';
import { BytesUtil } from '../../common/utils/BytesUtil';
import type { LoggerPort } from '../../common/types/Ports';
import type { CryptoPort } from '../crypto/CryptoPort';
import { InventoryDeviceState } from '../../model/CloudModels';
import {
  ShadowMapContext,
  StateReportMapper
} from '../protocol/StateReportMapper';
import { ShadowSnapshot, DeviceInventoryLimits } from './CloudModels';
import { CloudErrors } from './CloudErrors';
import { DeviceInventoryParser } from './DeviceInventoryParser';

const MAX_SHADOW_BODY_BYTES: number = 65536;
const INVENTORY_PROPERTY: string = 'DeviceInventoryJson';

export class ShadowDtoAdapter {
  static async map(body: Uint8Array, gatewayDeviceId: string, receivedAtMs: number,
    crypto: CryptoPort, logger: LoggerPort): Promise<ShadowSnapshot> {
    if (body.length > MAX_SHADOW_BODY_BYTES) {
      throw CloudErrors.shadowInvalid('body');
    }
    const rawSha256 = BytesUtil.hexLower(await crypto.sha256(body));
    const mapped = StateReportMapper.map(body,
      new ShadowMapContext(gatewayDeviceId, receivedAtMs, rawSha256));
    let inventory: ReadonlyArray<InventoryDeviceState> = [];
    let inventoryUnsupported = false;
    let inventoryError: AppError | undefined = undefined;
    let inventoryText: string | undefined = undefined;
    for (let index = 0; index < mapped.properties.length; index++) {
      const property = mapped.properties[index];
      if (property.name === INVENTORY_PROPERTY) {
        inventoryText = property.value;
      } else if (property.name.startsWith('DeviceInventory')) {
        // Other page names are not part of the v1 completion contract.
        logger.warn('cloud.inventory', 'CLOUD_INVENTORY_PAGE_UNSUPPORTED',
          [new NameValue('field', property.name)]);
      }
    }
    if (inventoryText !== undefined) {
      const unknownFields: string[] = [];
      try {
        inventory = DeviceInventoryParser.parse(inventoryText,
          DeviceInventoryLimits.defaults(), unknownFields);
        for (let index = 0; index < unknownFields.length; index++) {
          logger.warn('cloud.inventory', 'CLOUD_INVENTORY_FIELD_IGNORED',
            [new NameValue('field', unknownFields[index])]);
        }
      } catch (error) {
        if (error instanceof AppError) {
          inventoryUnsupported = true;
          inventoryError = error;
          logger.warn('cloud.inventory', 'CLOUD_INVENTORY_UNSUPPORTED',
            [new NameValue('code', error.code)]);
        } else {
          inventoryUnsupported = true;
          inventoryError = CloudErrors.inventoryUnsupported(INVENTORY_PROPERTY);
          logger.warn('cloud.inventory', 'CLOUD_INVENTORY_UNSUPPORTED',
            [new NameValue('code', 'CLOUD_INVENTORY_UNSUPPORTED')]);
        }
      }
    }
    return new ShadowSnapshot(mapped.gatewayDeviceId, mapped.eventTime, mapped.properties,
      mapped.devices, inventory, receivedAtMs, rawSha256, mapped.shape, inventoryUnsupported,
      inventoryError);
  }
}
