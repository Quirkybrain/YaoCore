/*
 * YaoCore C-19 GATT endpoint discovery map.
 * Producer: agent:implementation-engineer | Task: T-12 / wp-040-ble
 * Contract: DES-A §16.2; BLE设计 §2-21-45; project-constraints PR-12
 *
 * Endpoint names come exclusively from the User Characteristic Description
 * descriptor (0x2901). Characteristic order/UUID is never guessed. Every
 * protocomm endpoint characteristic must support read+write with response.
 */
import { AppErrors } from '../../common/types/AppError';
import { NameValue } from '../../common/types/NameValue';
import { Utf8 } from '../../common/utils/Utf8';
import { BleCharacteristicRef } from './BleProvisioningPorts';

const REQUIRED_ENDPOINTS: ReadonlyArray<string> = [
  'proto-ver', 'prov-session', 'prov-scan', 'prov-config', 'prov-ctrl', 'yaocore-id'
];
const KNOWN_ENDPOINTS: ReadonlyArray<string> = [
  'proto-ver', 'prov-session', 'prov-scan', 'prov-config', 'prov-ctrl', 'yaocore-id',
  'yaocore-done'
];

function incomplete(field: string): never {
  throw AppErrors.of('PROVISIONING_GATT_INCOMPLETE', [new NameValue('field', field)]);
}

export class GattEndpointMap {
  static readonly SERVICE_UUID: string = '7a6e0001-4d7b-4f67-9a21-6d13c52ae3b8';
  static readonly USER_DESCRIPTION_UUID: string = '00002901-0000-1000-8000-00805f9b34fb';
  static readonly PROTO_VER: string = 'proto-ver';
  static readonly PROV_SESSION: string = 'prov-session';
  static readonly PROV_SCAN: string = 'prov-scan';
  static readonly PROV_CONFIG: string = 'prov-config';
  static readonly PROV_CTRL: string = 'prov-ctrl';
  static readonly YAOCORE_ID: string = 'yaocore-id';
  static readonly YAOCORE_DONE: string = 'yaocore-done';

  private readonly characteristics: Map<string, BleCharacteristicRef> =
    new Map<string, BleCharacteristicRef>();

  private constructor(characteristics: Map<string, BleCharacteristicRef>) {
    this.characteristics = characteristics;
  }

  /**
   * Builds the endpoint map. `descriptors` is keyed by
   * `${serviceUuid}|${characteristicUuid}` (the caller may also key by
   * characteristic UUID alone). Missing/empty descriptor values, duplicate
   * endpoint names, and characteristics without read+write fail closed.
   */
  static build(characteristics: ReadonlyArray<BleCharacteristicRef>,
    descriptors: Map<string, Uint8Array>): GattEndpointMap {
    if (characteristics.length === 0) {
      incomplete('characteristics');
    }
    const byEndpoint = new Map<string, BleCharacteristicRef>();
    for (let index = 0; index < characteristics.length; index++) {
      const characteristic = characteristics[index];
      if (!characteristic.canRead || !characteristic.canWrite) {
        incomplete('characteristicProperties');
      }
      const key = characteristic.serviceUuid + '|' + characteristic.characteristicUuid;
      let raw = descriptors.get(key);
      if (raw === undefined) {
        raw = descriptors.get(characteristic.characteristicUuid);
      }
      if (raw === undefined || raw.length === 0) {
        incomplete('userDescription');
      }
      const endpoint = GattEndpointMap.normalizeEndpoint(raw);
      if (endpoint.length === 0) {
        incomplete('userDescription');
      }
      if (byEndpoint.has(endpoint)) {
        incomplete('duplicateEndpoint');
      }
      byEndpoint.set(endpoint, characteristic);
    }
    for (let index = 0; index < REQUIRED_ENDPOINTS.length; index++) {
      if (!byEndpoint.has(REQUIRED_ENDPOINTS[index])) {
        incomplete(REQUIRED_ENDPOINTS[index]);
      }
    }
    return new GattEndpointMap(byEndpoint);
  }

  get(endpoint: string): BleCharacteristicRef {
    const characteristic = this.characteristics.get(endpoint);
    if (characteristic === undefined) {
      incomplete(endpoint);
    }
    return characteristic;
  }

  has(endpoint: string): boolean {
    return this.characteristics.has(endpoint);
  }

  endpoints(): ReadonlyArray<string> {
    const result: string[] = [];
    this.characteristics.forEach((_value: BleCharacteristicRef, key: string) => {
      result.push(key);
    });
    result.sort();
    return result;
  }

  /** `yaocore-done` is optional for old firmware (BLE设计 §2-41). */
  requiresDoneEndpoint(): boolean {
    return this.characteristics.has(GattEndpointMap.YAOCORE_DONE);
  }

  static knownEndpoints(): ReadonlyArray<string> {
    return KNOWN_ENDPOINTS;
  }

  private static normalizeEndpoint(raw: Uint8Array): string {
    let text: string;
    try {
      text = Utf8.decode(raw);
    } catch (error) {
      incomplete('userDescriptionUtf8');
    }
    let withoutNul = '';
    for (let index = 0; index < text.length; index++) {
      if (text.charCodeAt(index) !== 0) {
        withoutNul += text.charAt(index);
      }
    }
    return withoutNul.trim();
  }
}
