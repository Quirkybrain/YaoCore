/*
 * YaoCore C-16 generic AC adapter.
 * Producer: agent:implementation-engineer | Task: T-14 / wp-055-cloud
 * Contract: DES-B §9.1, §9.2, §9.3; CB §6.3
 *
 * Outbound vocabulary is always the canonical 7 values. Unknown inbound modes
 * are preserved verbatim as NON_STANDARD and can never be sent back because
 * setMode() accepts only AcMode and validates the 7-value vocabulary at
 * runtime too.
 */
import { AppErrors } from '../../common/types/AppError';
import { DeviceAction, DeviceConstants } from '../../common/constants/DeviceConstants';
import { AcMode } from '../../model/DeviceTypes';
import type { DeviceStatePatch } from '../../model/DeviceState';
import type { AcAdapter } from './AcAdapter';
import {
  AcBrand,
  AcCapabilities,
  AcCommand,
  AcModeView,
  AcModeViewKind,
  AcViewState,
  AcVocabulary
} from './AcModels';

export class GenericAcAdapter implements AcAdapter {
  readonly brand: AcBrand;
  readonly capabilities: AcCapabilities;

  constructor(brand: AcBrand = AcBrand.GENERIC) {
    this.brand = brand;
    this.capabilities = new AcCapabilities(brand, AcVocabulary.MODES,
      DeviceConstants.DEFAULT_TARGET_TEMP_MIN, DeviceConstants.DEFAULT_TARGET_TEMP_MAX,
      false, false);
  }

  power(on: boolean): AcCommand {
    return new AcCommand(on ? DeviceAction.TURN_ON : DeviceAction.TURN_OFF);
  }

  setTargetTemperature(celsius: number): AcCommand {
    if (typeof celsius !== 'number' || !Number.isFinite(celsius)) {
      throw AppErrors.protocol('PROTOCOL_INVALID_TYPE', 'targetTemperature');
    }
    if (celsius < DeviceConstants.DEFAULT_TARGET_TEMP_MIN ||
      celsius > DeviceConstants.DEFAULT_TARGET_TEMP_MAX) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'targetTemperature');
    }
    return new AcCommand(DeviceAction.SET_TARGET_TEMPERATURE, celsius);
  }

  setMode(mode: AcMode): AcCommand {
    // Runtime defence: JS callers can bypass the compile-time AcMode union.
    if (!AcVocabulary.isStandard(String(mode))) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'mode');
    }
    return new AcCommand(DeviceAction.SET_MODE, String(mode));
  }

  normalizeInboundMode(raw: string): AcModeView {
    if (typeof raw !== 'string') {
      throw AppErrors.protocol('PROTOCOL_INVALID_TYPE', 'mode');
    }
    const trimmed = raw.trim();
    if (trimmed.length === 0) {
      return new AcModeView('', AcModeViewKind.UNKNOWN, 'ac.mode.unknown');
    }
    const exact = AcVocabulary.fromRaw(trimmed.toUpperCase());
    if (exact !== undefined) {
      return new AcModeView(raw, AcModeViewKind.STANDARD,
        AcVocabulary.i18nKey(exact), exact);
    }
    const alias = this.aliasMode(trimmed);
    if (alias !== undefined) {
      return new AcModeView(raw, AcModeViewKind.STANDARD,
        AcVocabulary.i18nKey(alias), alias);
    }
    return new AcModeView(raw, AcModeViewKind.NON_STANDARD, 'ac.mode.unknown');
  }

  normalizeInboundTemperature(raw: number): number {
    if (typeof raw !== 'number' || !Number.isFinite(raw)) {
      throw AppErrors.protocol('PROTOCOL_INVALID_TYPE', 'targetTemperature');
    }
    if (raw < DeviceConstants.DEFAULT_TARGET_TEMP_MIN ||
      raw > DeviceConstants.DEFAULT_TARGET_TEMP_MAX) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'targetTemperature');
    }
    return raw;
  }

  toViewState(patch: DeviceStatePatch): AcViewState {
    const mode = AcVocabulary.view(patch.mode);
    return new AcViewState(patch.powerStatus, patch.targetTemperature, mode, this.brand,
      AcVocabulary.brandI18nKey(this.brand), !patch.isOnline);
  }

  /** Brand-specific inbound alias hook; generic has none. */
  protected aliasMode(raw: string): AcMode | undefined {
    return undefined;
  }
}
