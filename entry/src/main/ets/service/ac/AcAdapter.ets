/*
 * YaoCore C-16 AC adapter interface.
 * Producer: agent:implementation-engineer | Task: T-14 / wp-055-cloud
 * Contract: DES-B §9.1
 *
 * Synchronous pure mapping. Implementations must not import repositories,
 * network transports or I18nService.
 */
import type { AcMode } from '../../model/DeviceTypes';
import type { DeviceStatePatch } from '../../model/DeviceState';
import type {
  AcBrand,
  AcCapabilities,
  AcCommand,
  AcModeView,
  AcViewState
} from './AcModels';

export interface AcAdapter {
  readonly brand: AcBrand;
  readonly capabilities: AcCapabilities;

  power(on: boolean): AcCommand;
  setTargetTemperature(celsius: number): AcCommand;
  setMode(mode: AcMode): AcCommand;

  normalizeInboundMode(raw: string): AcModeView;
  normalizeInboundTemperature(raw: number): number;
  toViewState(patch: DeviceStatePatch): AcViewState;
}
