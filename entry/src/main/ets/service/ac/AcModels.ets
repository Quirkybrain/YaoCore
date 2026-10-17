/*
 * YaoCore C-16 AC adapter value models.
 * Producer: agent:implementation-engineer | Task: T-14 / wp-055-cloud
 * Contract: DES-B §9.1, §9.3; CB §6.2/§6.3; ADR-001 §2
 *
 * Pure mapping only. No I/O, no repository, no I18nService call: labels are
 * returned as i18n keys and resolved by the presentation layer.
 *
 * DES-B nominally places this under `entry/src/main/ets/adapter/ac/**`.
 * T-14's delegated write scope is `entry/src/main/ets/service/**`, so the
 * adapter stays in service/ac as a recorded location exception.
 */
import { AppErrors } from '../../common/types/AppError';
import {
  DeviceAction,
  DeviceConstants
} from '../../common/constants/DeviceConstants';
import { AcMode } from '../../model/DeviceTypes';
import type { CommandValue } from '../../common/utils/JsonAtom';

export enum AcBrand {
  GREE = 'GREE',
  HAIER = 'HAIER',
  MIDEA = 'MIDEA',
  GENERIC = 'GENERIC'
}

export enum AcModeViewKind {
  STANDARD = 'STANDARD',
  NON_STANDARD = 'NON_STANDARD',
  UNKNOWN = 'UNKNOWN'
}

export class AcModeView {
  readonly raw: string;
  readonly mode?: AcMode;
  readonly kind: AcModeViewKind;
  readonly i18nKey: string;

  constructor(raw: string, kind: AcModeViewKind, i18nKey: string, mode?: AcMode) {
    this.raw = raw;
    this.kind = kind;
    this.i18nKey = i18nKey;
    this.mode = mode;
  }
}

export class AcCommand {
  readonly action: DeviceAction;
  readonly value?: CommandValue;

  constructor(action: DeviceAction, value?: CommandValue) {
    this.action = action;
    this.value = value;
  }
}

export class AcCapabilities {
  readonly brand: AcBrand;
  readonly supportedModes: ReadonlyArray<AcMode>;
  readonly minTargetTemperature: number;
  readonly maxTargetTemperature: number;
  readonly supportsColor: boolean;
  readonly supportsFanSpeed: boolean;

  constructor(brand: AcBrand, supportedModes: ReadonlyArray<AcMode>,
    minTargetTemperature: number = DeviceConstants.DEFAULT_TARGET_TEMP_MIN,
    maxTargetTemperature: number = DeviceConstants.DEFAULT_TARGET_TEMP_MAX,
    supportsColor: boolean = false, supportsFanSpeed: boolean = false) {
    if (supportedModes.length === 0 || minTargetTemperature < 16 ||
      maxTargetTemperature > 30 || minTargetTemperature > maxTargetTemperature) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    this.brand = brand;
    this.supportedModes = supportedModes;
    this.minTargetTemperature = minTargetTemperature;
    this.maxTargetTemperature = maxTargetTemperature;
    this.supportsColor = supportsColor;
    this.supportsFanSpeed = supportsFanSpeed;
  }
}

export class AcViewState {
  readonly power?: boolean;
  readonly targetTemperature?: number;
  readonly mode: AcModeView;
  readonly brand: AcBrand;
  readonly brandI18nKey: string;
  readonly isReadOnly: boolean;

  constructor(power: boolean | undefined, targetTemperature: number | undefined,
    mode: AcModeView, brand: AcBrand, brandI18nKey: string, isReadOnly: boolean) {
    this.power = power;
    this.targetTemperature = targetTemperature;
    this.mode = mode;
    this.brand = brand;
    this.brandI18nKey = brandI18nKey;
    this.isReadOnly = isReadOnly;
  }
}

export class AcVocabulary {
  static readonly MODES: ReadonlyArray<AcMode> = [
    AcMode.AUTO, AcMode.COOL, AcMode.HEAT, AcMode.DRY,
    AcMode.FAN, AcMode.ECO, AcMode.SLEEP
  ];

  static fromRaw(raw: string): AcMode | undefined {
    if (raw === AcMode.AUTO) {
      return AcMode.AUTO;
    }
    if (raw === AcMode.COOL) {
      return AcMode.COOL;
    }
    if (raw === AcMode.HEAT) {
      return AcMode.HEAT;
    }
    if (raw === AcMode.DRY) {
      return AcMode.DRY;
    }
    if (raw === AcMode.FAN) {
      return AcMode.FAN;
    }
    if (raw === AcMode.ECO) {
      return AcMode.ECO;
    }
    if (raw === AcMode.SLEEP) {
      return AcMode.SLEEP;
    }
    return undefined;
  }

  static isStandard(raw: string): boolean {
    return DeviceConstants.isAcMode(raw);
  }

  static view(raw: string | undefined): AcModeView {
    if (raw === undefined || raw.trim().length === 0) {
      return new AcModeView('', AcModeViewKind.UNKNOWN, 'ac.mode.unknown');
    }
    const mode = AcVocabulary.fromRaw(raw.trim().toUpperCase());
    if (mode !== undefined) {
      return new AcModeView(raw, AcModeViewKind.STANDARD, AcVocabulary.i18nKey(mode), mode);
    }
    return new AcModeView(raw, AcModeViewKind.NON_STANDARD, 'ac.mode.unknown');
  }

  static i18nKey(mode: AcMode): string {
    return 'ac.mode.' + String(mode).toLowerCase();
  }

  static brandI18nKey(brand: AcBrand): string {
    return 'brand.' + String(brand).toLowerCase();
  }
}
