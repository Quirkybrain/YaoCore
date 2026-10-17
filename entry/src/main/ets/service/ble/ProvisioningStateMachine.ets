/*
 * YaoCore C-19 provisioning state machine.
 * Producer: agent:implementation-engineer | Task: T-12 / wp-040-ble
 * Contract: DES-A §16.9; BLE设计 §7-161-165
 *
 * Pure transition table. Illegal transitions are CONFIGURATION_ERROR; they
 * never silently advance the flow. `FAIL` is a T-12 extension for transport/
 * GATT/MTU failures that have no dedicated DES-A event; all DES-A events are
 * preserved verbatim.
 */
import { AppErrors } from '../../common/types/AppError';
import { ProvisioningState } from './BleProvisioningPorts';

export enum ProvisioningEvent {
  START = 'START',
  PERMISSION_GRANTED = 'PERMISSION_GRANTED',
  PERMISSION_DENIED = 'PERMISSION_DENIED',
  BLUETOOTH_OFF = 'BLUETOOTH_OFF',
  DEVICE_FOUND = 'DEVICE_FOUND',
  SCAN_TIMEOUT = 'SCAN_TIMEOUT',
  CONNECTED = 'CONNECTED',
  DISCOVERED = 'DISCOVERED',
  CAPABILITY_OK = 'CAPABILITY_OK',
  CAPABILITY_FAILED = 'CAPABILITY_FAILED',
  SECURITY_OK = 'SECURITY_OK',
  SECURITY_FAILED = 'SECURITY_FAILED',
  IDENTITY_OK = 'IDENTITY_OK',
  IDENTITY_FAILED = 'IDENTITY_FAILED',
  AP_SELECTED = 'AP_SELECTED',
  CREDENTIALS_SENT = 'CREDENTIALS_SENT',
  WIFI_CONNECTED = 'WIFI_CONNECTED',
  WIFI_FAILED = 'WIFI_FAILED',
  BINDING_OK = 'BINDING_OK',
  BINDING_FAILED = 'BINDING_FAILED',
  CANCEL = 'CANCEL',
  RESET = 'RESET',
  FAIL = 'FAIL'
}

function isTerminal(state: ProvisioningState): boolean {
  return state === ProvisioningState.BOUND || state === ProvisioningState.FAILED ||
    state === ProvisioningState.CANCELLED;
}

function illegal(state: ProvisioningState, event: ProvisioningEvent): never {
  throw AppErrors.of('CONFIGURATION_ERROR', []);
}

export class ProvisioningStateMachine {
  private stateValue: ProvisioningState = ProvisioningState.IDLE;

  get state(): ProvisioningState {
    return this.stateValue;
  }

  transition(event: ProvisioningEvent): ProvisioningState {
    const current = this.stateValue;
    if (event === ProvisioningEvent.RESET) {
      this.stateValue = ProvisioningState.IDLE;
      return this.stateValue;
    }
    if (event === ProvisioningEvent.CANCEL) {
      if (isTerminal(current)) {
        illegal(current, event);
      }
      this.stateValue = ProvisioningState.CANCELLED;
      return this.stateValue;
    }
    if (event === ProvisioningEvent.FAIL) {
      if (isTerminal(current)) {
        illegal(current, event);
      }
      this.stateValue = ProvisioningState.FAILED;
      return this.stateValue;
    }
    if (current === ProvisioningState.IDLE && event === ProvisioningEvent.START) {
      this.stateValue = ProvisioningState.PERMISSION;
      return this.stateValue;
    }
    if (current === ProvisioningState.PERMISSION &&
      event === ProvisioningEvent.PERMISSION_GRANTED) {
      this.stateValue = ProvisioningState.SCANNING;
      return this.stateValue;
    }
    if (current === ProvisioningState.PERMISSION &&
      (event === ProvisioningEvent.PERMISSION_DENIED ||
        event === ProvisioningEvent.BLUETOOTH_OFF)) {
      this.stateValue = ProvisioningState.FAILED;
      return this.stateValue;
    }
    if (current === ProvisioningState.SCANNING && event === ProvisioningEvent.DEVICE_FOUND) {
      this.stateValue = ProvisioningState.CONNECTING;
      return this.stateValue;
    }
    if (current === ProvisioningState.SCANNING && event === ProvisioningEvent.SCAN_TIMEOUT) {
      this.stateValue = ProvisioningState.FAILED;
      return this.stateValue;
    }
    if (current === ProvisioningState.CONNECTING && event === ProvisioningEvent.CONNECTED) {
      this.stateValue = ProvisioningState.DISCOVERING;
      return this.stateValue;
    }
    if (current === ProvisioningState.DISCOVERING && event === ProvisioningEvent.DISCOVERED) {
      this.stateValue = ProvisioningState.CAPABILITY_CHECK;
      return this.stateValue;
    }
    if (current === ProvisioningState.CAPABILITY_CHECK &&
      event === ProvisioningEvent.CAPABILITY_OK) {
      this.stateValue = ProvisioningState.SECURITY_HANDSHAKE;
      return this.stateValue;
    }
    if (current === ProvisioningState.CAPABILITY_CHECK &&
      event === ProvisioningEvent.CAPABILITY_FAILED) {
      this.stateValue = ProvisioningState.FAILED;
      return this.stateValue;
    }
    if (current === ProvisioningState.SECURITY_HANDSHAKE &&
      event === ProvisioningEvent.SECURITY_OK) {
      this.stateValue = ProvisioningState.SECURE_IDENTITY;
      return this.stateValue;
    }
    if (current === ProvisioningState.SECURITY_HANDSHAKE &&
      event === ProvisioningEvent.SECURITY_FAILED) {
      this.stateValue = ProvisioningState.FAILED;
      return this.stateValue;
    }
    if (current === ProvisioningState.SECURE_IDENTITY &&
      event === ProvisioningEvent.IDENTITY_OK) {
      this.stateValue = ProvisioningState.AP_SCANNING;
      return this.stateValue;
    }
    if (current === ProvisioningState.SECURE_IDENTITY &&
      event === ProvisioningEvent.IDENTITY_FAILED) {
      this.stateValue = ProvisioningState.FAILED;
      return this.stateValue;
    }
    if (current === ProvisioningState.AP_SCANNING && event === ProvisioningEvent.AP_SELECTED) {
      this.stateValue = ProvisioningState.SENDING_CREDENTIALS;
      return this.stateValue;
    }
    if (current === ProvisioningState.SENDING_CREDENTIALS &&
      event === ProvisioningEvent.CREDENTIALS_SENT) {
      this.stateValue = ProvisioningState.WAITING_FOR_WIFI;
      return this.stateValue;
    }
    if (current === ProvisioningState.WAITING_FOR_WIFI &&
      event === ProvisioningEvent.WIFI_CONNECTED) {
      this.stateValue = ProvisioningState.DISCOVERING_ON_LAN;
      return this.stateValue;
    }
    if (current === ProvisioningState.WAITING_FOR_WIFI &&
      event === ProvisioningEvent.WIFI_FAILED) {
      this.stateValue = ProvisioningState.FAILED;
      return this.stateValue;
    }
    if (current === ProvisioningState.DISCOVERING_ON_LAN &&
      event === ProvisioningEvent.BINDING_OK) {
      this.stateValue = ProvisioningState.BOUND;
      return this.stateValue;
    }
    if (current === ProvisioningState.DISCOVERING_ON_LAN &&
      event === ProvisioningEvent.BINDING_FAILED) {
      this.stateValue = ProvisioningState.FAILED;
      return this.stateValue;
    }
    illegal(current, event);
  }

  reset(): void {
    this.stateValue = ProvisioningState.IDLE;
  }
}
