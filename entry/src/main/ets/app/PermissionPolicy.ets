/*
 * YaoCore C-28 permission policy (pure decisions).
 * Producer: agent:implementation-engineer | Task: T-17 / wp-067-ui-shell
 * Contract: DES-B §17.1.6, §17.2; DES-B-C28-API; SC-11
 *
 * Pure mapping consumed by PermissionGate (platform) and host tests.
 * v1 manifest declaration is exactly INTERNET (system_grant) and
 * ACCESS_BLUETOOTH (user_grant). CAMERA/LOCATION are intentionally NOT
 * declared/guessed; their state is UNAVAILABLE until a later task proves the
 * ScanKit/BLE requirement on a device (DES-B §17.1.6).
 */
import { AppError, AppErrors } from '../common/types/AppError';

export enum PermissionKind {
  INTERNET = 'INTERNET',
  BLUETOOTH = 'BLUETOOTH',
  CAMERA = 'CAMERA',
  NOTIFICATIONS = 'NOTIFICATIONS',
  LOCATION_OPTIONAL = 'LOCATION_OPTIONAL'
}

export enum PermissionState {
  GRANTED = 'GRANTED',
  DENIED = 'DENIED',
  NOT_DETERMINED = 'NOT_DETERMINED',
  UNAVAILABLE = 'UNAVAILABLE'
}

export class PermissionResult {
  readonly kind: PermissionKind;
  readonly state: PermissionState;
  readonly canOpenSettings: boolean;
  readonly error?: AppError;

  constructor(kind: PermissionKind, state: PermissionState, canOpenSettings: boolean,
    error?: AppError) {
    this.kind = kind;
    this.state = state;
    this.canOpenSettings = canOpenSettings;
    this.error = error;
  }
}

export interface PermissionPort {
  ensure(kind: PermissionKind): Promise<PermissionResult>;
  check(kind: PermissionKind): Promise<PermissionState>;
  openSettings(): Promise<void>;
  requiredForProvisioning(): ReadonlyArray<PermissionKind>;
}

export class PermissionPolicy {
  static readonly INTERNET: string = 'ohos.permission.INTERNET';
  static readonly ACCESS_BLUETOOTH: string = 'ohos.permission.ACCESS_BLUETOOTH';

  /** Permissions declared in entry/src/main/module.json5 (v1). */
  static manifestPermissions(): ReadonlyArray<string> {
    return [PermissionPolicy.INTERNET, PermissionPolicy.ACCESS_BLUETOOTH];
  }

  static requiredForProvisioning(): ReadonlyArray<PermissionKind> {
    // DES-B §17.1.6: BLE scan/connect/provisioning only. No location guess.
    return [PermissionKind.BLUETOOTH];
  }

  static permissionName(kind: PermissionKind): string {
    switch (kind) {
      case PermissionKind.INTERNET:
        return PermissionPolicy.INTERNET;
      case PermissionKind.BLUETOOTH:
        return PermissionPolicy.ACCESS_BLUETOOTH;
      case PermissionKind.CAMERA:
        return 'ohos.permission.CAMERA';
      default:
        return '';
    }
  }

  static isDeclared(kind: PermissionKind): boolean {
    return kind === PermissionKind.INTERNET || kind === PermissionKind.BLUETOOTH;
  }

  static isSystemGrant(kind: PermissionKind): boolean {
    return kind === PermissionKind.INTERNET;
  }

  static isRuntimeRequestable(kind: PermissionKind): boolean {
    return kind === PermissionKind.BLUETOOTH;
  }

  /** abilityAccessCtrl.PermissionStatus numeric values (API 20+). */
  static stateFromSelfStatus(status: number): PermissionState {
    if (status === 0) {
      return PermissionState.GRANTED;
    }
    if (status === -1) {
      return PermissionState.DENIED;
    }
    if (status === 1) {
      return PermissionState.NOT_DETERMINED;
    }
    return PermissionState.UNAVAILABLE;
  }

  /** PermissionRequestResult.authResults values: 0 granted, negative denied. */
  static stateFromRequestResult(authResult: number): PermissionState {
    if (authResult === 0) {
      return PermissionState.GRANTED;
    }
    if (authResult < 0) {
      return PermissionState.DENIED;
    }
    return PermissionState.UNAVAILABLE;
  }

  static canOpenSettings(state: PermissionState): boolean {
    return state === PermissionState.DENIED;
  }

  static errorFor(kind: PermissionKind, state: PermissionState): AppError | undefined {
    if (state === PermissionState.GRANTED) {
      return undefined;
    }
    if (kind === PermissionKind.INTERNET) {
      // INTERNET is system_grant; a denied state means the manifest is wrong.
      return AppErrors.of('CONFIGURATION_ERROR', []);
    }
    return AppErrors.of('PROVISIONING_PERMISSION_DENIED', []);
  }

  static resultFor(kind: PermissionKind, state: PermissionState): PermissionResult {
    return new PermissionResult(kind, state, PermissionPolicy.canOpenSettings(state),
      PermissionPolicy.errorFor(kind, state));
  }
}
