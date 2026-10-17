/*
 * YaoCore C-23 SettingsViewModel.
 * Producer: agent:implementation-engineer | Task: T-16 / wp-060-vm
 * Contract: DES-B §12.1.2, §12.3.2; ADR-002; ADR-004 §5/§7; D-012/D-015; F-03/F-06
 *
 * Cloud v1 is single-active-gateway: a family with more than one bound gateway
 * cannot save/test cloud configuration and gets an explicit restriction flag.
 * `testConnection` never becomes a persistent config write; it only reflects
 * the C-15 state. The IAM token is never stored in VM state.
 */
import { AppErrors } from '../common/types/AppError';
import { NameValue } from '../common/types/NameValue';
import type { ClockPort, LoggerPort } from '../common/types/Ports';
import { IpAddressUtil } from '../common/utils/IpAddressUtil';
import { GatewayAddress } from '../model/GatewayRoute';
import type { GatewayRoute } from '../model/GatewayRoute';
import type { CloudConfig } from '../model/FamilyModels';
import { TransportProfile } from '../model/DeviceTypes';
import type { CloudConfigValidation, CloudConfigView } from '../service/cloud/CloudModels';
import type { SessionInfo } from '../service/auth/AuthModels';
import type { PreferencesStore } from '../service/storage/PreferencesStore';
import type { DiscoveryCandidate } from '../service/gateway/DiscoveryModels';
import { LocaleChangedEvent, LocaleMode, SupportedLocale } from '../service/i18n/I18nModels';
import { ErrorI18nMapper } from '../service/i18n/ErrorI18nMapper';
import {
  LoadPhase,
  ViewModelError,
  ViewModelSupport
} from './core/ViewModelCore';
import type { ViewModelBase } from './core/ViewModelCore';
import type { ManualDiscoveryPort } from './ViewModelPorts';
import { I18nService } from '../service/i18n/I18nService';
import { CloudService } from '../service/cloud/CloudService';
import { GatewayRepository } from '../repository/GatewayRepository';
import { AuthService } from '../service/auth/AuthService';

const TAG: string = 'SettingsViewModel';
const MOTION_KEY: string = 'app.motion.enabled';
const NOTIFICATIONS_KEY: string = 'app.notifications.enabled';
const SINGLE_GATEWAY_KEY: string = 'settings.cloud.single_gateway_required';

export enum SettingsSection {
  LANGUAGE = 'LANGUAGE',
  CLOUD = 'CLOUD',
  SECURITY = 'SECURITY',
  ADVANCED = 'ADVANCED',
  NOTIFICATIONS = 'NOTIFICATIONS',
  ABOUT = 'ABOUT'
}

export class GatewaySecurityView {
  readonly gatewayId: string;
  readonly gatewayName: string;
  readonly profile: TransportProfile;
  readonly effectiveProfile: TransportProfile;
  readonly tlsEnabled: boolean;
  readonly pinCount: number;
  readonly pinMatched?: string;
  readonly lastErrorKey?: string;
  readonly rotationRecommended: boolean;

  constructor(gatewayId: string, gatewayName: string, profile: TransportProfile,
    effectiveProfile: TransportProfile, tlsEnabled: boolean, pinCount: number,
    rotationRecommended: boolean, pinMatched?: string, lastErrorKey?: string) {
    this.gatewayId = gatewayId;
    this.gatewayName = gatewayName;
    this.profile = profile;
    this.effectiveProfile = effectiveProfile;
    this.tlsEnabled = tlsEnabled;
    this.pinCount = pinCount;
    this.rotationRecommended = rotationRecommended;
    this.pinMatched = pinMatched;
    this.lastErrorKey = lastErrorKey;
  }
}

export class ManualAddressResult {
  readonly accepted: boolean;
  readonly gatewayId: string;
  readonly latencyMs?: number;
  readonly error?: ViewModelError;

  constructor(accepted: boolean, gatewayId: string, latencyMs?: number,
    error?: ViewModelError) {
    this.accepted = accepted;
    this.gatewayId = gatewayId;
    this.latencyMs = latencyMs;
    this.error = error;
  }
}

export class SettingsViewState {
  readonly phase: LoadPhase;
  readonly section: SettingsSection;
  readonly localeMode: LocaleMode;
  readonly currentLocale: SupportedLocale;
  readonly cloud?: CloudConfigView;
  readonly security: ReadonlyArray<GatewaySecurityView>;
  readonly advancedExpanded: boolean;
  readonly manualAddressResult?: ManualAddressResult;
  readonly motionEnabled: boolean;
  readonly notificationsEnabled: boolean;
  readonly appVersion: string;
  readonly pendingAction: boolean;
  readonly cloudRestricted: boolean;
  readonly cloudRestrictionKey?: string;
  readonly platformRestartRequired: boolean;
  readonly error?: ViewModelError;
  readonly revision: number;

  constructor(phase: LoadPhase, section: SettingsSection, localeMode: LocaleMode,
    currentLocale: SupportedLocale, cloud: CloudConfigView | undefined,
    security: ReadonlyArray<GatewaySecurityView>, advancedExpanded: boolean,
    manualAddressResult: ManualAddressResult | undefined, motionEnabled: boolean,
    notificationsEnabled: boolean, appVersion: string, pendingAction: boolean,
    cloudRestricted: boolean, cloudRestrictionKey: string | undefined,
    platformRestartRequired: boolean, error: ViewModelError | undefined, revision: number) {
    this.phase = phase;
    this.section = section;
    this.localeMode = localeMode;
    this.currentLocale = currentLocale;
    this.cloud = cloud;
    this.security = security;
    this.advancedExpanded = advancedExpanded;
    this.manualAddressResult = manualAddressResult;
    this.motionEnabled = motionEnabled;
    this.notificationsEnabled = notificationsEnabled;
    this.appVersion = appVersion;
    this.pendingAction = pendingAction;
    this.cloudRestricted = cloudRestricted;
    this.cloudRestrictionKey = cloudRestrictionKey;
    this.platformRestartRequired = platformRestartRequired;
    this.error = error;
    this.revision = revision;
  }

  static initial(locale: SupportedLocale): SettingsViewState {
    return new SettingsViewState(LoadPhase.IDLE, SettingsSection.LANGUAGE, LocaleMode.AUTO,
      locale, undefined, [], false, undefined, true, false, '', false, false, undefined,
      false, undefined, 0);
  }
}

export class SettingsViewModel implements ViewModelBase<SettingsViewState> {
  private readonly i18n: I18nService;
  private readonly cloud: CloudService;
  private readonly gateways: GatewayRepository;
  private readonly discovery: ManualDiscoveryPort;
  private readonly auth: AuthService;
  private readonly preferences: PreferencesStore;
  private readonly clock: ClockPort;
  private readonly logger: LoggerPort;
  private readonly appVersion: string;

  private state: SettingsViewState;
  private listeners: Array<(state: SettingsViewState) => void> = [];
  private revision: number = 0;
  private disposed: boolean = false;
  private unsubscribeLocale?: () => void = undefined;
  private familyId: string = '';

  constructor(i18n: I18nService, cloud: CloudService,
    gateways: GatewayRepository, discovery: ManualDiscoveryPort,
    auth: AuthService, preferences: PreferencesStore, clock: ClockPort,
    logger: LoggerPort, appVersion: string = '') {
    this.i18n = i18n;
    this.cloud = cloud;
    this.gateways = gateways;
    this.discovery = discovery;
    this.auth = auth;
    this.preferences = preferences;
    this.clock = clock;
    this.logger = logger;
    this.appVersion = appVersion;
    this.state = SettingsViewState.initial(i18n.getLocale());
  }

  getState(): SettingsViewState {
    return this.state;
  }

  subscribe(listener: (state: SettingsViewState) => void): () => void {
    this.listeners.push(listener);
    return (): void => {
      const index = this.listeners.indexOf(listener);
      if (index >= 0) {
        this.listeners.splice(index, 1);
      }
    };
  }

  async initialize(): Promise<void> {
    this.publish(this.copy(LoadPhase.LOADING, false, undefined));
    try {
      const session: SessionInfo | undefined = this.auth.getActiveSession();
      this.familyId = session === undefined ? '' : session.familyId;
      const motion = await this.readBoolean(MOTION_KEY, true);
      const notifications = await this.readBoolean(NOTIFICATIONS_KEY, false);
      const cloud = await this.loadCloud();
      const security = await this.loadSecurity();
      this.unsubscribeLocale = this.i18n.onLocaleChanged((event: LocaleChangedEvent): void => {
        this.onLocaleChanged(event);
      });
      this.publish(new SettingsViewState(LoadPhase.READY, this.state.section,
        this.i18n.getLocaleMode(), this.i18n.getLocale(), cloud, security,
        this.state.advancedExpanded, this.state.manualAddressResult, motion, notifications,
        this.appVersion, false, security.length > 1,
        security.length > 1 ? SINGLE_GATEWAY_KEY : undefined, false, undefined,
        this.revision + 1));
    } catch (error) {
      this.fail(error as Object);
    }
  }

  setSection(section: SettingsSection): void {
    this.publish(this.copy(this.state.phase, this.state.pendingAction, this.state.error,
      section));
  }

  async setLocaleMode(mode: LocaleMode): Promise<void> {
    try {
      await this.i18n.setLocaleMode(mode);
      this.publish(this.copy(this.state.phase, false, undefined, this.state.section,
        this.i18n.getLocaleMode(), this.i18n.getLocale()));
    } catch (error) {
      this.fail(error as Object);
    }
  }

  async saveCloudConfig(config: CloudConfig, token?: string): Promise<void> {
    if (this.state.cloudRestricted) {
      this.fail(AppErrors.of('CONFIGURATION_ERROR', [
        new NameValue('field', 'multiGatewayCloud')]));
      return;
    }
    this.publish(this.copy(this.state.phase, true, undefined));
    try {
      const effectiveToken = token === undefined || token.length === 0 ? undefined : token;
      const view = await this.cloud.saveConfig(config, effectiveToken);
      this.publish(new SettingsViewState(this.state.phase, this.state.section,
        this.state.localeMode, this.state.currentLocale, view, this.state.security,
        this.state.advancedExpanded, this.state.manualAddressResult, this.state.motionEnabled,
        this.state.notificationsEnabled, this.state.appVersion, false,
        this.state.cloudRestricted, this.state.cloudRestrictionKey,
        this.state.platformRestartRequired, undefined, this.revision + 1));
    } catch (error) {
      this.fail(error as Object);
    }
  }

  async testCloudConnection(): Promise<boolean> {
    if (this.state.cloudRestricted) {
      this.fail(AppErrors.of('CONFIGURATION_ERROR', [
        new NameValue('field', 'multiGatewayCloud')]));
      return false;
    }
    this.publish(this.copy(this.state.phase, true, undefined));
    try {
      const result: CloudConfigValidation = await this.cloud.testConnection();
      if (!result.valid) {
        const error = result.errors.length > 0 ? result.errors[0] :
          AppErrors.of('CLOUD_NOT_CONFIGURED', []);
        // F-04: C-15 records 401/403 as a transient TOKEN_EXPIRED/INVALID view.
        // Refresh the persistent layer so the UI stops showing CONFIGURED.
        let cloud = this.state.cloud;
        try {
          cloud = await this.loadCloud();
        } catch (loadError) {
          this.logger.warn(TAG, 'cloud_state_refresh_failed',
            [new NameValue('code', ViewModelSupport.codeOf(loadError as Object))]);
          cloud = this.state.cloud;
        }
        this.publish(this.cloudState(cloud, false, ViewModelSupport.viewError(error, this.clock)));
        return false;
      }
      const cloud = await this.loadCloud();
      this.publish(this.cloudState(cloud, false, undefined));
      return true;
    } catch (error) {
      this.fail(error as Object);
      return false;
    }
  }

  async clearCloudToken(): Promise<void> {
    this.publish(this.copy(this.state.phase, true, undefined));
    try {
      await this.cloud.clearToken();
      const cloud = await this.loadCloud();
      this.publish(new SettingsViewState(this.state.phase, this.state.section,
        this.state.localeMode, this.state.currentLocale, cloud, this.state.security,
        this.state.advancedExpanded, this.state.manualAddressResult, this.state.motionEnabled,
        this.state.notificationsEnabled, this.state.appVersion, false,
        this.state.cloudRestricted, this.state.cloudRestrictionKey,
        this.state.platformRestartRequired, undefined, this.revision + 1));
    } catch (error) {
      this.fail(error as Object);
    }
  }

  async refreshSecurity(): Promise<void> {
    try {
      const security = await this.loadSecurity();
      this.publish(new SettingsViewState(this.state.phase, this.state.section,
        this.state.localeMode, this.state.currentLocale, this.state.cloud, security,
        this.state.advancedExpanded, this.state.manualAddressResult, this.state.motionEnabled,
        this.state.notificationsEnabled, this.state.appVersion, false, security.length > 1,
        security.length > 1 ? SINGLE_GATEWAY_KEY : undefined,
        this.state.platformRestartRequired, undefined, this.revision + 1));
    } catch (error) {
      this.fail(error as Object);
    }
  }

  async setMotionEnabled(enabled: boolean): Promise<void> {
    try {
      await this.preferences.putString(MOTION_KEY, enabled ? 'true' : 'false');
      await this.preferences.flush();
      this.publish(new SettingsViewState(this.state.phase, this.state.section,
        this.state.localeMode, this.state.currentLocale, this.state.cloud, this.state.security,
        this.state.advancedExpanded, this.state.manualAddressResult, enabled,
        this.state.notificationsEnabled, this.state.appVersion, false,
        this.state.cloudRestricted, this.state.cloudRestrictionKey,
        this.state.platformRestartRequired, undefined, this.revision + 1));
    } catch (error) {
      this.fail(error as Object);
    }
  }

  async setNotificationsEnabled(enabled: boolean): Promise<void> {
    try {
      await this.preferences.putString(NOTIFICATIONS_KEY, enabled ? 'true' : 'false');
      await this.preferences.flush();
      this.publish(new SettingsViewState(this.state.phase, this.state.section,
        this.state.localeMode, this.state.currentLocale, this.state.cloud, this.state.security,
        this.state.advancedExpanded, this.state.manualAddressResult, this.state.motionEnabled,
        enabled, this.state.appVersion, false, this.state.cloudRestricted,
        this.state.cloudRestrictionKey, this.state.platformRestartRequired, undefined,
        this.revision + 1));
    } catch (error) {
      this.fail(error as Object);
    }
  }

  setAdvancedExpanded(expanded: boolean): void {
    this.publish(new SettingsViewState(this.state.phase, this.state.section,
      this.state.localeMode, this.state.currentLocale, this.state.cloud, this.state.security,
      expanded, this.state.manualAddressResult, this.state.motionEnabled,
      this.state.notificationsEnabled, this.state.appVersion, this.state.pendingAction,
      this.state.cloudRestricted, this.state.cloudRestrictionKey,
      this.state.platformRestartRequired, this.state.error, this.revision + 1));
  }

  async probeManualAddress(gatewayId: string, ip: string, port: number):
    Promise<ManualAddressResult> {
    try {
      if (!IpAddressUtil.isAllowedLanIpv4(ip.trim()) || !IpAddressUtil.isValidPort(port)) {
        throw AppErrors.of('MANUAL_ADDRESS_REJECTED', []);
      }
      const address = new GatewayAddress(ip.trim(), port);
      const candidate = await this.discovery.probeManual(gatewayId, address);
      this.discovery.resetManualFailures(gatewayId);
      const result = new ManualAddressResult(true, gatewayId, candidate.latencyMs, undefined);
      this.publish(new SettingsViewState(this.state.phase, this.state.section,
        this.state.localeMode, this.state.currentLocale, this.state.cloud, this.state.security,
        this.state.advancedExpanded, result, this.state.motionEnabled,
        this.state.notificationsEnabled, this.state.appVersion, false,
        this.state.cloudRestricted, this.state.cloudRestrictionKey,
        this.state.platformRestartRequired, undefined, this.revision + 1));
      return result;
    } catch (error) {
      const viewError = ViewModelSupport.viewError(error as Object, this.clock);
      const result = new ManualAddressResult(false, gatewayId, undefined, viewError);
      this.publish(new SettingsViewState(this.state.phase, this.state.section,
        this.state.localeMode, this.state.currentLocale, this.state.cloud, this.state.security,
        this.state.advancedExpanded, result, this.state.motionEnabled,
        this.state.notificationsEnabled, this.state.appVersion, false,
        this.state.cloudRestricted, this.state.cloudRestrictionKey,
        this.state.platformRestartRequired, viewError, this.revision + 1));
      return result;
    }
  }

  clearError(): void {
    this.publish(this.copy(this.state.phase, this.state.pendingAction, undefined));
  }

  translate(error: ViewModelError | undefined): string {
    return error === undefined ? '' : this.i18n.t(error.i18nKey);
  }

  translateKey(key: string | undefined): string {
    return key === undefined || key.length === 0 ? '' : this.i18n.t(key);
  }

  dispose(): void {
    this.disposed = true;
    if (this.unsubscribeLocale !== undefined) {
      this.unsubscribeLocale();
      this.unsubscribeLocale = undefined;
    }
    this.listeners.splice(0, this.listeners.length);
  }

  private onLocaleChanged(event: LocaleChangedEvent): void {
    if (this.disposed) {
      return;
    }
    this.publish(new SettingsViewState(this.state.phase, this.state.section, event.mode,
      event.current, this.state.cloud, this.state.security, this.state.advancedExpanded,
      this.state.manualAddressResult, this.state.motionEnabled, this.state.notificationsEnabled,
      this.state.appVersion, this.state.pendingAction, this.state.cloudRestricted,
      this.state.cloudRestrictionKey, !event.platformApplied, this.state.error,
      this.revision + 1));
  }

  private async loadCloud(): Promise<CloudConfigView> {
    return await this.cloud.getState();
  }

  private cloudState(cloud: CloudConfigView | undefined, pendingAction: boolean,
    error: ViewModelError | undefined): SettingsViewState {
    return new SettingsViewState(this.state.phase, this.state.section, this.state.localeMode,
      this.state.currentLocale, cloud, this.state.security, this.state.advancedExpanded,
      this.state.manualAddressResult, this.state.motionEnabled, this.state.notificationsEnabled,
      this.state.appVersion, pendingAction, this.state.cloudRestricted,
      this.state.cloudRestrictionKey, this.state.platformRestartRequired, error,
      this.revision + 1);
  }

  private async loadSecurity(): Promise<ReadonlyArray<GatewaySecurityView>> {
    const routes = this.familyId.length > 0 ?
      await this.gateways.listRoutesByFamily(this.familyId) : await this.gateways.listRoutes();
    const views: GatewaySecurityView[] = [];
    for (let index = 0; index < routes.length; index++) {
      const route = routes[index];
      let effective = route.profile;
      let pinMatched: string | undefined = undefined;
      let lastErrorKey: string | undefined = undefined;
      try {
        const candidate = await this.discovery.probeLastKnown(route.gatewayId);
        if (candidate !== undefined) {
          effective = candidate.profile === undefined ? route.profile : candidate.profile;
          if (candidate.errorCode !== undefined) {
            lastErrorKey = ErrorI18nMapper.appKey(
              AppErrors.of(candidate.errorCode, [])).key;
          }
        }
      } catch (error) {
        lastErrorKey = ErrorI18nMapper.appKey(
          ViewModelSupport.asAppError(error as Object)).key;
      }
      views.push(new GatewaySecurityView(route.gatewayId, route.gatewayName, route.profile,
        effective, route.profile === TransportProfile.P_TLS_PIN ||
          effective === TransportProfile.P_TLS_PIN, route.pins.length, false,
        pinMatched, lastErrorKey));
    }
    return views;
  }

  private async readBoolean(key: string, fallback: boolean): Promise<boolean> {
    try {
      const value = await this.preferences.getString(key);
      if (value === undefined) {
        return fallback;
      }
      return value === 'true';
    } catch (error) {
      return fallback;
    }
  }

  private copy(phase: LoadPhase, pendingAction: boolean, error: ViewModelError | undefined,
    section: SettingsSection = this.state.section, localeMode: LocaleMode = this.state.localeMode,
    locale: SupportedLocale = this.state.currentLocale): SettingsViewState {
    return new SettingsViewState(phase, section, localeMode, locale, this.state.cloud,
      this.state.security, this.state.advancedExpanded, this.state.manualAddressResult,
      this.state.motionEnabled, this.state.notificationsEnabled, this.state.appVersion,
      pendingAction, this.state.cloudRestricted, this.state.cloudRestrictionKey,
      this.state.platformRestartRequired, error, this.revision + 1);
  }

  private fail(error: Object): void {
    const viewError = ViewModelSupport.viewError(error, this.clock);
    this.logger.warn(TAG, 'view_model_error', [new NameValue('code', viewError.error.code)]);
    this.publish(this.copy(this.state.phase, false, viewError));
  }

  private publish(next: SettingsViewState): void {
    this.revision = next.revision;
    this.state = next;
    for (let index = 0; index < this.listeners.length; index++) {
      try {
        this.listeners[index](next);
      } catch (error) {
        this.logger.warn(TAG, 'listener_failed',
          [new NameValue('code', ViewModelSupport.codeOf(error as Object))]);
      }
    }
  }
}
