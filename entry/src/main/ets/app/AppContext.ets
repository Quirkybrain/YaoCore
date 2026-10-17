/*
 * YaoCore C-28 AppContext (session gate + application lifecycle).
 * Producer: agent:implementation-engineer | Task: T-17 / wp-067-ui-shell
 * Contract: DES-B §2.8, §17.1.3, §17.4; DES-B-C28-STATE; D-019
 *
 * Host-testable by construction: AppContext depends on the narrow
 * AppContextRootPort and never imports @ohos/@kit. The composition root
 * satisfies the port. It owns no business state: family/profile/session facts
 * are re-read from C-08/C-12 after each transition.
 */
import { AppError, AppErrors } from '../common/types/AppError';
import type { LoggerPort } from '../common/types/Ports';
import type { Family } from '../model/FamilyModels';
import type { LocalProfile, SessionInfo } from '../service/auth/AuthModels';
import type { IBleProvisioningClient } from '../service/ble/BleProvisioningPorts';
import type { CloudService } from '../service/cloud/CloudService';
import type { I18nService } from '../service/i18n/I18nService';
import type { PreferencesStore } from '../service/storage/PreferencesStore';
import type { SecretDraftPort } from '../service/storage/SecretDraftPort';

export enum SessionGateState {
  NO_PROFILE = 'NO_PROFILE',
  LOCKED = 'LOCKED',
  UNLOCKED = 'UNLOCKED'
}

export class SessionGateProfile {
  readonly profileId: string;
  readonly displayName: string;

  constructor(profileId: string, displayName: string) {
    this.profileId = profileId;
    this.displayName = displayName;
  }
}

export interface AppLifecycleObserver {
  onForeground(): Promise<void>;
  onBackground(): Promise<void>;
}

/** Narrow C-08 repository surface used by the session gate. */
export interface ActiveFamilyPort {
  getActiveFamily(): Promise<Family | undefined>;
  setActiveFamily(familyId: string): Promise<void>;
}

/** Narrow C-12 auth surface used by the session gate. */
export interface SessionGateAuthPort {
  listProfiles(familyId: string): Promise<ReadonlyArray<LocalProfile>>;
  getActiveSession(): SessionInfo | undefined;
  unlock(profileId: string, password: string): Promise<SessionInfo>;
  lockAll(): Promise<void>;
}

/** C-28 services needed by AppContext; AppCompositionRoot implements this. */
export interface AppContextRootPort {
  readonly i18n: I18nService;
  readonly sessionAuth: SessionGateAuthPort;
  readonly activeFamily: ActiveFamilyPort;
  readonly preferences: PreferencesStore;
  readonly secretDrafts: SecretDraftPort;
  readonly ble: IBleProvisioningClient;
  readonly cloud: CloudService;
  readonly logger: LoggerPort;

  initialize(): Promise<void>;
  isInitialized(): boolean;
  getInitializationError(): AppError | undefined;
}

export type SessionGateListener = (state: SessionGateState) => void;

const MOTION_PREF_KEY: string = 'app.motion.enabled';

export class AppContext {
  private readonly root: AppContextRootPort;
  private gate: SessionGateState = SessionGateState.NO_PROFILE;
  private activeFamilyIdValue: string | undefined = undefined;
  private activeFamilyNameValue: string = '';
  private foreground: boolean = false;
  private initPromise: Promise<void> | undefined = undefined;
  private initializationErrorValue: AppError | undefined = undefined;
  private readonly gateListeners: SessionGateListener[] = [];
  private readonly lifecycleObservers: AppLifecycleObserver[] = [];

  constructor(root: AppContextRootPort) {
    this.root = root;
  }

  get activeFamilyId(): string | undefined {
    return this.activeFamilyIdValue;
  }

  get activeFamilyName(): string {
    return this.activeFamilyNameValue;
  }

  get session(): SessionInfo | undefined {
    return this.root.sessionAuth.getActiveSession();
  }

  get isForeground(): boolean {
    return this.foreground;
  }

  get sessionGate(): SessionGateState {
    return this.gate;
  }

  get initializationError(): AppError | undefined {
    return this.initializationErrorValue;
  }

  get i18n(): I18nService {
    return this.root.i18n;
  }

  initialize(): Promise<void> {
    if (this.initPromise !== undefined) {
      return this.initPromise;
    }
    this.initPromise = this.doInitialize();
    return this.initPromise;
  }

  /** StartupErrorView retry: re-runs a failed root initialization once. */
  retryInitialization(): Promise<void> {
    this.initPromise = undefined;
    this.initializationErrorValue = undefined;
    return this.initialize();
  }

  async refreshSessionGate(): Promise<void> {
    let family: Family | undefined = undefined;
    try {
      family = await this.root.activeFamily.getActiveFamily();
    } catch (error) {
      this.root.logger.warn('AppContext', 'active_family_read_failed');
    }
    this.activeFamilyIdValue = family === undefined ? undefined : family.familyId;
    this.activeFamilyNameValue = family === undefined ? '' : family.familyName;

    let hasProfile = false;
    if (family !== undefined) {
      try {
        const profiles = await this.root.sessionAuth.listProfiles(family.familyId);
        hasProfile = profiles.length > 0;
      } catch (error) {
        this.root.logger.warn('AppContext', 'profile_read_failed');
      }
    }

    let next: SessionGateState = SessionGateState.NO_PROFILE;
    if (family !== undefined && hasProfile) {
      next = this.root.sessionAuth.getActiveSession() === undefined
        ? SessionGateState.LOCKED : SessionGateState.UNLOCKED;
    }
    this.setGate(next);
  }

  subscribeSessionGate(listener: SessionGateListener): () => void {
    this.gateListeners.push(listener);
    return (): void => {
      const index = this.gateListeners.indexOf(listener);
      if (index >= 0) {
        this.gateListeners.splice(index, 1);
      }
    };
  }

  async setActiveFamily(familyId: string): Promise<void> {
    await this.root.activeFamily.setActiveFamily(familyId);
    await this.refreshSessionGate();
  }

  async unlock(profileId: string, password: string): Promise<SessionInfo> {
    const session = await this.root.sessionAuth.unlock(profileId, password);
    await this.refreshSessionGate();
    return session;
  }

  async lock(): Promise<void> {
    await this.root.sessionAuth.lockAll();
    await this.refreshSessionGate();
  }

  subscribeLifecycle(observer: AppLifecycleObserver): () => void {
    this.lifecycleObservers.push(observer);
    return (): void => {
      const index = this.lifecycleObservers.indexOf(observer);
      if (index >= 0) {
        this.lifecycleObservers.splice(index, 1);
      }
    };
  }

  async onForeground(): Promise<void> {
    this.foreground = true;
    for (let index = 0; index < this.lifecycleObservers.length; index++) {
      try {
        await this.lifecycleObservers[index].onForeground();
      } catch (error) {
        this.root.logger.warn('AppContext', 'foreground_observer_failed');
      }
    }
    try {
      const family = await this.root.activeFamily.getActiveFamily();
      this.activeFamilyIdValue = family === undefined ? undefined : family.familyId;
      this.activeFamilyNameValue = family === undefined ? '' : family.familyName;
    } catch (error) {
      this.root.logger.warn('AppContext', 'foreground_family_read_failed');
    }
    try {
      await this.root.i18n.reload();
    } catch (error) {
      this.root.logger.warn('AppContext', 'foreground_locale_reload_failed');
    }
  }

  /** DES-B §17.1.3 fixed order; every step runs even if one fails. */
  async onBackground(): Promise<void> {
    this.foreground = false;
    try {
      await this.root.sessionAuth.lockAll();
    } catch (error) {
      this.root.logger.warn('AppContext', 'background_lock_failed');
    }
    await this.refreshSessionGate();
    try {
      this.root.secretDrafts.clearAll();
    } catch (error) {
      this.root.logger.warn('AppContext', 'background_draft_clear_failed');
    }
    try {
      await this.root.ble.cancel();
    } catch (error) {
      this.root.logger.warn('AppContext', 'background_ble_cancel_failed');
    }
    try {
      this.root.cloud.stopPolling();
    } catch (error) {
      this.root.logger.warn('AppContext', 'background_cloud_stop_failed');
    }
    for (let index = 0; index < this.lifecycleObservers.length; index++) {
      try {
        await this.lifecycleObservers[index].onBackground();
      } catch (error) {
        this.root.logger.warn('AppContext', 'background_observer_failed');
      }
    }
    try {
      await this.root.preferences.flush();
    } catch (error) {
      this.root.logger.warn('AppContext', 'background_flush_failed');
    }
  }

  /** UIUX/DES-B motion preference; absent/failed reads keep motion enabled. */
  async isMotionEnabled(): Promise<boolean> {
    try {
      const value = await this.root.preferences.getString(MOTION_PREF_KEY);
      return value !== 'false';
    } catch (error) {
      return true;
    }
  }

  async listProfiles(): Promise<ReadonlyArray<SessionGateProfile>> {
    const familyId = this.activeFamilyIdValue;
    if (familyId === undefined) {
      return [];
    }
    try {
      const profiles = await this.root.sessionAuth.listProfiles(familyId);
      const result: SessionGateProfile[] = [];
      for (let index = 0; index < profiles.length; index++) {
        result.push(new SessionGateProfile(profiles[index].profileId,
          profiles[index].displayName));
      }
      return result;
    } catch (error) {
      this.root.logger.warn('AppContext', 'profile_list_failed');
      return [];
    }
  }

  private async doInitialize(): Promise<void> {
    try {
      await this.root.initialize();
    } catch (error) {
      this.initializationErrorValue = AppContext.asAppError(error as Error);
      return;
    }
    const rootError = this.root.getInitializationError();
    if (rootError !== undefined || !this.root.isInitialized()) {
      this.initializationErrorValue = rootError === undefined
        ? AppErrors.of('INTERNAL_ERROR', []) : rootError;
      return;
    }
    this.initializationErrorValue = undefined;
    await this.refreshSessionGate();
  }

  private setGate(next: SessionGateState): void {
    if (this.gate === next) {
      return;
    }
    this.gate = next;
    const listeners = this.gateListeners.slice();
    for (let index = 0; index < listeners.length; index++) {
      try {
        listeners[index](next);
      } catch (error) {
        this.root.logger.warn('AppContext', 'session_gate_listener_failed');
      }
    }
  }

  private static asAppError(error: Error): AppError {
    if (error instanceof AppError) {
      return error as AppError;
    }
    return AppErrors.of('INTERNAL_ERROR', []);
  }
}
