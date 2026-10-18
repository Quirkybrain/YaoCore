/*
 * YaoCore C-28 runtime permission gate.
 * Producer: agent:implementation-engineer | Task: T-17 / wp-067-ui-shell
 * Contract: DES-B §17.1.6, §17.2; DES-B-C28-API; CQG-T12 R-6
 *
 * module.json5 declares only:
 *   - ohos.permission.INTERNET        (system_grant; no runtime dialog)
 *   - ohos.permission.ACCESS_BLUETOOTH (user_grant; requested at provisioning)
 * CAMERA / APPROXIMATELY_LOCATION are NOT declared or guessed in v1. The
 * pure decisions live in PermissionPolicy so they are host-testable.
 */
import { abilityAccessCtrl, bundleManager, common, Permissions, Want } from '@kit.AbilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { AppErrors } from '../common/types/AppError';
import type { LoggerPort } from '../contracts/Ports';
import {
  PermissionKind,
  PermissionPolicy,
  PermissionResult,
  PermissionState
} from './PermissionPolicy';
import type { PermissionPort } from './PermissionPolicy';
import { PermissionKind as ViewModelPermissionKind } from '../contracts/PermissionPort';
import type { PermissionPort as ViewModelPermissionPort } from '../contracts/PermissionPort';

export class PermissionGate implements PermissionPort {
  private readonly context: common.UIAbilityContext;
  private readonly logger: LoggerPort;
  /**
   * F-03: API < 20 cannot report NOT_DETERMINED, so the action entry requests
   * once per process. This set prevents repeated permission dialogs after a
   * denial; the UI then offers "open settings" via canOpenSettings.
   */
  private readonly requestedInProcess: Set<PermissionKind> = new Set<PermissionKind>();

  constructor(context: common.UIAbilityContext, logger: LoggerPort) {
    this.context = context;
    this.logger = logger;
  }

  async ensure(kind: PermissionKind): Promise<PermissionResult> {
    if (kind === PermissionKind.INTERNET) {
      return new PermissionResult(kind, PermissionState.GRANTED, false);
    }
    if (!PermissionPolicy.isDeclared(kind)) {
      // Camera/location/notifications are explicitly not part of the v1
      // manifest; the caller must use the text/paste fallback or postpone.
      return PermissionPolicy.resultFor(kind, PermissionState.UNAVAILABLE);
    }
    const current = await this.check(kind);
    if (!PermissionPolicy.shouldRequestPermission(
      current, this.requestedInProcess.has(kind))) {
      if (current === PermissionState.NOT_DETERMINED) {
        // Already requested in this process and still not granted: report the
        // terminal state instead of opening another system dialog.
        return PermissionPolicy.resultFor(kind,
          PermissionPolicy.stateAfterSuppressedRequest());
      }
      return PermissionPolicy.resultFor(kind, current);
    }
    if (!PermissionPolicy.isRuntimeRequestable(kind)) {
      return PermissionPolicy.resultFor(kind, PermissionState.UNAVAILABLE);
    }
    this.requestedInProcess.add(kind);
    const permission = PermissionPolicy.permissionName(kind);
    try {
      const manager = abilityAccessCtrl.createAtManager();
      const response = await manager.requestPermissionsFromUser(this.context,
        [permission as Permissions]);
      const code = response.authResults.length === 0 ? -1 : response.authResults[0];
      const state = PermissionPolicy.stateFromRequestResult(code);
      return PermissionPolicy.resultFor(kind, state);
    } catch (error) {
      this.logger.warn('PermissionGate', 'request_failed');
      return new PermissionResult(kind, PermissionState.DENIED, true,
        AppErrors.of('PROVISIONING_PERMISSION_DENIED', []));
    }
  }

  async check(kind: PermissionKind): Promise<PermissionState> {
    if (kind === PermissionKind.INTERNET) {
      return PermissionState.GRANTED;
    }
    if (!PermissionPolicy.isDeclared(kind)) {
      return PermissionState.UNAVAILABLE;
    }
    const permission = PermissionPolicy.permissionName(kind);
    try {
      const manager = abilityAccessCtrl.createAtManager();
      const apiLevel = deviceInfo.sdkApiVersion;
      if (apiLevel >= PermissionPolicy.SELF_PERMISSION_STATUS_MIN_API) {
        try {
          return PermissionPolicy.stateFromSelfStatus(
            manager.getSelfPermissionStatus(permission as Permissions));
        } catch (error) {
          // SDK/device mismatch on a newer runtime: fall through to the
          // token-only check without losing the API-level semantics.
          this.logger.warn('PermissionGate', 'self_status_unavailable');
        }
      }
      const tokenId = bundleManager.getBundleInfoForSelfSync(0).appInfo.accessTokenId;
      const granted = manager.checkAccessTokenSync(tokenId, permission as Permissions) ===
        abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
      return PermissionPolicy.stateFromTokenCheck(granted, apiLevel);
    } catch (error) {
      this.logger.warn('PermissionGate', 'check_failed');
      return PermissionState.UNAVAILABLE;
    }
  }

  async openSettings(): Promise<void> {
    try {
      const want: Want = {
        action: 'ohos.settings.app.info',
        parameters: { bundleName: this.context.abilityInfo.bundleName }
      };
      await this.context.startAbility(want);
    } catch (error) {
      throw AppErrors.of('INTERNAL_ERROR', []);
    }
  }

  requiredForProvisioning(): ReadonlyArray<PermissionKind> {
    return PermissionPolicy.requiredForProvisioning();
  }
}

/**
 * Adapter for C-23 BleProvisioningViewModel, whose PermissionPort has a
 * narrower BLUETOOTH-only shape (T-16 seam). The same gate is used so the
 * manifest/request decision has one owner.
 */
export class BleViewModelPermissionGate implements ViewModelPermissionPort {
  private readonly gate: PermissionGate;

  constructor(gate: PermissionGate) {
    this.gate = gate;
  }

  async ensure(kind: ViewModelPermissionKind): Promise<void> {
    if (kind !== ViewModelPermissionKind.BLUETOOTH) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    const result = await this.gate.ensure(PermissionKind.BLUETOOTH);
    if (result.state !== PermissionState.GRANTED) {
      throw result.error === undefined
        ? AppErrors.of('PROVISIONING_PERMISSION_DENIED', []) : result.error;
    }
  }

  /** F-08: terminal denial recovery used by C-23's PermissionPort. */
  openSettings(): Promise<void> {
    return this.gate.openSettings();
  }
}
