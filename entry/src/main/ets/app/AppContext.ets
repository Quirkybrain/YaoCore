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
import type { LoggerPort } from '../contracts/Ports';
import type { Family } from '../model/FamilyModels';
import type { LocalProfile, SessionInfo } from '../service/auth/AuthModels';
import type { IBleProvisioningClient } from '../contracts/BleProvisioningPorts';
import type { CloudService } from '../service/cloud/CloudService';
import type { I18nService } from '../service/i18n/I18nService';
import type { PreferencesStore } from '../contracts/PreferencesStore';
import type { SecretDraftPort } from '../contracts/SecretDraftPort';
import type { PageVmFactoryPort } from './PageVmFactory';

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

/**
 * C-22 onboarding capability reachable from the NO_PROFILE gate (F-02).
 * Implemented by app/OnboardingService; AppContext only owns the gate refresh.
 * Joining is two-step because a KEY_WRAP invitation answers a YCR1 request
 * created by this device (FamilyJoinSession.start -> submitInvitation).
 */
export interface OnboardingPort {
  createFamily(familyName: string, ownerDisplayName: string, password: string): Promise<void>;
  startJoin(displayName: string): Promise<string>;
  completeJoin(invitationText: string, code: string, displayName: string,
    password: string): Promise<void>;
  cancelJoin(): Promise<void>;
}

/** C-28 services needed by AppContext; AppCompositionRoot implements this. */
export interface AppContextRootPort {
  readonly i18n: I18nService;
  readonly sessionAuth: SessionGateAuthPort;
  readonly activeFamily: ActiveFamilyPort;
  readonly onboarding: OnboardingPort;
  readonly preferences: PreferencesStore;
  readonly secretDrafts: SecretDraftPort;
  readonly ble: IBleProvisioningClient;
  readonly cloud: CloudService;
  readonly logger: LoggerPort;
  readonly pageVms: PageVmFactoryPort;

  initialize(): Promise<void>;
  isInitialized(): boolean;
  getInitializationError(): AppError | undefined;
}

export type SessionGateListener = (state: SessionGateState) => void;
export type ActiveFamilyListener = (familyId: string | undefined) => void;

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
  private readonly activeFamilyListeners: ActiveFamilyListener[] = [];
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

  /** T-18 additive seam: pages obtain VM factories through Index props (no globals). */
  get pageVms(): PageVmFactoryPort {
    return this.root.pageVms;
  }

  isInitialized(): boolean {
    return this.root.isInitialized();
  }

  async initialize(): Promise<void> {
    if (this.root.isInitialized() || this.initializationErrorValue !== undefined) {
      return;
    }
    if (this.initPromise !== undefined) {
      await this.initPromise;
      return;
    }
    this.initPromise = this.doInitialize();
    await this.initPromise;
  }

  /** StartupErrorView retry: re-runs a failed root initialization once. */
  async retryInitialization(): Promise<void> {
    this.initPromise = undefined;
    this.initializationErrorValue = undefined;
    await this.initialize();
  }

  async refreshSessionGate(): Promise<void> {
    const previousFamilyId = this.activeFamilyIdValue;
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
      const session = this.root.sessionAuth.getActiveSession();
      // F-13: a session for another family must never unlock this family.
      const hasSessionForActiveFamily = session !== undefined &&
        session.familyId === family.familyId;
      next = hasSessionForActiveFamily
        ? SessionGateState.UNLOCKED : SessionGateState.LOCKED;
    }
    this.setGate(next);
    if (previousFamilyId !== this.activeFamilyIdValue) {
      this.notifyActiveFamily(this.activeFamilyIdValue);
    }
  }

  /**
   * R2-06: active-family changes are observable. Index/MainShell and Home use
   * this instead of polling `activeFamilyId`.
   */
  subscribeActiveFamily(listener: ActiveFamilyListener): () => void {
    this.activeFamilyListeners.push(listener);
    return (): void => {
      const index = this.activeFamilyListeners.indexOf(listener);
      if (index >= 0) {
        this.activeFamilyListeners.splice(index, 1);
      }
    };
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
    // F-13: switching the active family must never inherit the previous
    // family's session; lock first, then recompute the gate.
    await this.root.sessionAuth.lockAll();
    await this.refreshSessionGate();
  }

  /** F-02: NO_PROFILE onboarding; creates family + owner profile, then locks. */
  async createFamily(familyName: string, ownerDisplayName: string,
    password: string): Promise<void> {
    await this.root.onboarding.createFamily(familyName, ownerDisplayName, password);
    await this.refreshSessionGate();
  }

  /** F-02: creates this device's YCR1 join request for an admin. */
  startJoin(displayName: string): Promise<string> {
    return this.root.onboarding.startJoin(displayName);
  }

  /** F-02: accepts the admin's YCI1 invitation, then locks. */
  async completeJoin(invitationText: string, code: string, displayName: string,
    password: string): Promise<void> {
    await this.root.onboarding.completeJoin(invitationText, code, displayName, password);
    await this.refreshSessionGate();
  }

  cancelJoin(): Promise<void> {
    return this.root.onboarding.cancelJoin();
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
    const previousFamilyId = this.activeFamilyIdValue;
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
      if (previousFamilyId !== this.activeFamilyIdValue) {
        this.notifyActiveFamily(this.activeFamilyIdValue);
      }
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

  private notifyActiveFamily(familyId: string | undefined): void {
    const listeners = this.activeFamilyListeners.slice();
    for (let index = 0; index < listeners.length; index++) {
      try {
        listeners[index](familyId);
      } catch (error) {
        this.root.logger.warn('AppContext', 'active_family_listener_failed');
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
