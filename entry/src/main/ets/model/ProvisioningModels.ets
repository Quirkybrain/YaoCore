/*
 * YaoCore C-02/C-19 provisioning models.
 * Producer: agent:implementation-engineer | Task: T-06 / wp-012-foundation
 * Extended: T-23 / wp-090-ports (2026-10-18) — BLE provisioning DTO/enums moved
 * out of service/ble/BleProvisioningPorts.ets (DES-A §27.6.3 P2).
 * Contract: DES-A §5.1.6, §16.1
 */
import { AppErrors } from '../common/types/AppError';
import type { AppError } from '../common/types/AppError';
import { ProtocolConstants } from '../common/constants/ProtocolConstants';
import { DateTimeUtil } from '../common/utils/DateTimeUtil';
import { IpAddressUtil } from '../common/utils/IpAddressUtil';
import { Utf8 } from '../common/utils/Utf8';

export enum IdentityVersion {
  V20 = '2.0',
  V21 = '2.1'
}

export class ProvisioningTlsMaterial {
  readonly pins: ReadonlyArray<string>;
  readonly port: number;
  readonly pinAlg: string;

  constructor(pins: ReadonlyArray<string>, port: number, pinAlg: string) {
    if (!IpAddressUtil.isValidPort(port)) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'port');
    }
    if (pins.length < 1 || pins.length > ProtocolConstants.MAX_PIN_COUNT) {
      throw AppErrors.of('TLS_PIN_CONFIG_INVALID', []);
    }
    for (let index = 0; index < pins.length; index++) {
      if (!ProtocolConstants.PIN_PATTERN.test(pins[index])) {
        throw AppErrors.of('TLS_PIN_CONFIG_INVALID', []);
      }
    }
    if (pinAlg !== 'sha256-spki-der') {
      throw AppErrors.of('TLS_PIN_CONFIG_INVALID', []);
    }
    this.pins = pins;
    this.port = port;
    this.pinAlg = pinAlg;
  }
}

export class BleProvisioningIdentity {
  readonly version: IdentityVersion;
  readonly gatewayId: string;
  readonly gatewayName: string;
  readonly tls?: ProvisioningTlsMaterial;

  constructor(version: IdentityVersion, gatewayId: string, gatewayName: string,
    tls?: ProvisioningTlsMaterial) {
    if (gatewayId.length === 0 || gatewayId.length > ProtocolConstants.MAX_DEVICE_ID_LENGTH ||
      gatewayId.indexOf(':') >= 0 || !ProtocolConstants.DEVICE_ID_PATTERN.test(gatewayId)) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'gatewayId');
    }
    if (gatewayName.length === 0 ||
      gatewayName.length > ProtocolConstants.MAX_GATEWAY_NAME_LENGTH) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'gatewayName');
    }
    if (version === IdentityVersion.V20 && tls !== undefined) {
      throw AppErrors.of('PROVISIONING_IDENTITY_INVALID', []);
    }
    this.version = version;
    this.gatewayId = gatewayId;
    this.gatewayName = gatewayName;
    this.tls = tls;
  }
}

export class BleProvisioningResult {
  readonly identity: BleProvisioningIdentity;
  readonly ip: string;
  readonly port: number;
  readonly boardLedConfirmed: boolean;
  readonly credentialDraftId: string;
  readonly completedAt: string;

  constructor(identity: BleProvisioningIdentity, ip: string, port: number, boardLedConfirmed: boolean,
    credentialDraftId: string, completedAt: string) {
    if (!IpAddressUtil.isValidIpv4(ip) || !IpAddressUtil.isValidPort(port)) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'address');
    }
    const expectedPort = identity.tls === undefined ? ProtocolConstants.DEFAULT_GATEWAY_PORT :
      identity.tls.port;
    if (port !== expectedPort) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    DateTimeUtil.parseUtcCompact(completedAt);
    this.identity = identity;
    this.ip = ip;
    this.port = port;
    this.boardLedConfirmed = boardLedConfirmed;
    this.credentialDraftId = credentialDraftId;
    this.completedAt = completedAt;
  }
}

// ---- C-19 provisioning transport/DTO models (T-23 migration) ---------------

export enum ProvisioningState {
  IDLE = 'IDLE',
  PERMISSION = 'PERMISSION',
  SCANNING = 'SCANNING',
  CONNECTING = 'CONNECTING',
  DISCOVERING = 'DISCOVERING',
  CAPABILITY_CHECK = 'CAPABILITY_CHECK',
  SECURITY_HANDSHAKE = 'SECURITY_HANDSHAKE',
  SECURE_IDENTITY = 'SECURE_IDENTITY',
  AP_SCANNING = 'AP_SCANNING',
  SENDING_CREDENTIALS = 'SENDING_CREDENTIALS',
  WAITING_FOR_WIFI = 'WAITING_FOR_WIFI',
  DISCOVERING_ON_LAN = 'DISCOVERING_ON_LAN',
  BOUND = 'BOUND',
  FAILED = 'FAILED',
  CANCELLED = 'CANCELLED'
}

/** Coarse progress stages retained for the T-11 listener surface. */

export enum BleProvisioningStage {
  CONNECTING = 'CONNECTING',
  SECURITY = 'SECURITY',
  IDENTITY = 'IDENTITY',
  WIFI_SCAN = 'WIFI_SCAN',
  WIFI_APPLY = 'WIFI_APPLY',
  WIFI_STATUS = 'WIFI_STATUS',
  DONE = 'DONE',
  BINDING_PROBE = 'BINDING_PROBE'
}

export class BleProvisioningDevice {
  readonly deviceId: string;
  readonly name: string;
  readonly rssi: number;
  readonly serviceUuids: ReadonlyArray<string>;

  constructor(deviceId: string, name: string, rssi: number,
    serviceUuids: ReadonlyArray<string> = []) {
    if (deviceId.length === 0 || !Number.isFinite(rssi) ||
      rssi < -127 || rssi > 20) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    this.deviceId = deviceId;
    this.name = name;
    this.rssi = rssi;
    this.serviceUuids = serviceUuids;
  }
}

/** Backwards-compatible T-11 name; same value object. */
export class BleScanDevice extends BleProvisioningDevice {
}

export class BleScanFilter {
  readonly serviceUuid: string;
  readonly namePrefix?: string;
  readonly timeoutMs: number;

  constructor(serviceUuid: string, namePrefix?: string, timeoutMs: number = 10000) {
    if (serviceUuid.length === 0 || !Number.isInteger(timeoutMs) || timeoutMs <= 0) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    this.serviceUuid = serviceUuid;
    this.namePrefix = namePrefix;
    this.timeoutMs = timeoutMs;
  }
}

export class WifiAp {
  readonly ssid: string;
  readonly bssid: string;
  readonly channel: number;
  readonly rssi: number;
  readonly auth: number;

  constructor(ssid: string, bssid: string, channel: number, rssi: number, auth: number) {
    if (ssid.length === 0 || !Number.isInteger(channel) || channel < 0 || channel > 196 ||
      !Number.isFinite(rssi) || !Number.isInteger(auth) || auth < 0 || auth > 7) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'wifiAp');
    }
    this.ssid = ssid;
    this.bssid = bssid;
    this.channel = channel;
    this.rssi = rssi;
    this.auth = auth;
  }
}

/** Progress event (DES-A §16.1.1). messageKey is an i18n key, never text. */

export class ProvisioningProgress {
  readonly state: ProvisioningState;
  readonly messageKey?: string;
  readonly apList?: ReadonlyArray<WifiAp>;
  readonly identity?: BleProvisioningIdentity;
  readonly error?: AppError;

  constructor(state: ProvisioningState, messageKey?: string, apList?: ReadonlyArray<WifiAp>,
    identity?: BleProvisioningIdentity, error?: AppError) {
    this.state = state;
    this.messageKey = messageKey;
    this.apList = apList;
    this.identity = identity;
    this.error = error;
  }
}

/**
 * Listener contract. `onStage` is the T-11-compatible coarse progress hook;
 * the DES-A §16.1 callbacks are optional so small consumers (and the mock)
 * only opt into what they render. The service never logs secrets here.
 */

export class BleProvisioningRequest {
  readonly ssid: string;
  readonly wifiPassword: Uint8Array;
  readonly pop: Uint8Array;
  readonly device?: BleProvisioningDevice;
  readonly credentialDraftId?: string;
  readonly familyId: string;
  readonly expectedGatewayId?: string;

  constructor(ssid: string, wifiPassword: Uint8Array, pop: Uint8Array,
    device?: BleProvisioningDevice, credentialDraftId?: string,
    familyId: string = '', expectedGatewayId?: string) {
    let ssidBytes: Uint8Array;
    try {
      ssidBytes = Utf8.encode(ssid);
    } catch (error) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'ssid');
    }
    if (ssidBytes.length === 0 || ssidBytes.length > 32) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'ssid');
    }
    if (wifiPassword.length > 64) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'wifiPassword');
    }
    if (pop.length === 0 || pop.length > 64) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'pop');
    }
    if (familyId.length > 63) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'familyId');
    }
    if (credentialDraftId !== undefined &&
      (credentialDraftId.length === 0 || credentialDraftId.length > 128)) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'credentialDraftId');
    }
    if (expectedGatewayId !== undefined) {
      if (expectedGatewayId.length === 0 ||
        expectedGatewayId.length > ProtocolConstants.MAX_DEVICE_ID_LENGTH ||
        expectedGatewayId.indexOf(':') >= 0 ||
        !ProtocolConstants.DEVICE_ID_PATTERN.test(expectedGatewayId)) {
        throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'expectedGatewayId');
      }
    }
    this.ssid = ssid;
    this.wifiPassword = wifiPassword;
    this.pop = pop;
    this.device = device;
    this.credentialDraftId = credentialDraftId;
    this.familyId = familyId;
    this.expectedGatewayId = expectedGatewayId;
  }
}

/**
 * F-07 / CQG-T18: pre-wifi handshake + AP scan request. The page can show the
 * real AP list in step 3 instead of collecting SSID blindly before the
 * aggregated provision() call. PoP is a caller-owned byte buffer; the service
 * copies and zeroizes it. The later provision() re-runs the same handshake.
 */

export class BleWifiScanRequest {
  readonly pop: Uint8Array;
  readonly device?: BleProvisioningDevice;
  readonly expectedGatewayId?: string;

  constructor(pop: Uint8Array, device?: BleProvisioningDevice,
    expectedGatewayId?: string) {
    if (pop.length === 0 || pop.length > 64) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'pop');
    }
    if (expectedGatewayId !== undefined) {
      if (expectedGatewayId.length === 0 ||
        expectedGatewayId.length > ProtocolConstants.MAX_DEVICE_ID_LENGTH ||
        expectedGatewayId.indexOf(':') >= 0 ||
        !ProtocolConstants.DEVICE_ID_PATTERN.test(expectedGatewayId)) {
        throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'expectedGatewayId');
      }
    }
    this.pop = pop;
    this.device = device;
    this.expectedGatewayId = expectedGatewayId;
  }
}

export class BleServiceRef {
  readonly uuid: string;

  constructor(uuid: string) {
    if (uuid.length === 0) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    this.uuid = uuid;
  }
}

export class BleCharacteristicRef {
  readonly serviceUuid: string;
  readonly characteristicUuid: string;
  readonly canRead: boolean;
  readonly canWrite: boolean;
  readonly canWriteNoResponse: boolean;

  constructor(serviceUuid: string, characteristicUuid: string, canRead: boolean,
    canWrite: boolean, canWriteNoResponse: boolean) {
    if (serviceUuid.length === 0 || characteristicUuid.length === 0) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    this.serviceUuid = serviceUuid;
    this.characteristicUuid = characteristicUuid;
    this.canRead = canRead;
    this.canWrite = canWrite;
    this.canWriteNoResponse = canWriteNoResponse;
  }
}

export class BleDescriptorRef {
  readonly serviceUuid: string;
  readonly characteristicUuid: string;
  readonly descriptorUuid: string;

  constructor(serviceUuid: string, characteristicUuid: string, descriptorUuid: string) {
    if (serviceUuid.length === 0 || characteristicUuid.length === 0 ||
      descriptorUuid.length === 0) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    this.serviceUuid = serviceUuid;
    this.characteristicUuid = characteristicUuid;
    this.descriptorUuid = descriptorUuid;
  }
}
