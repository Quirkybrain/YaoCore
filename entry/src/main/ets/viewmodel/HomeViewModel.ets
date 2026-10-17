/*
 * YaoCore C-21 HomeViewModel.
 * Producer: agent:implementation-engineer | Task: T-15 / wp-060-vm
 * Contract: DES-B §10.1.2, §10.2, §10.4; FR-HOME-001..004; D-019
 *
 * Home state is derived from the local SSOT and signed discover results only.
 * A failed refresh preserves previous records and reports the gateway link
 * state; it never fabricates device state or sensor values.
 */
import { AppError } from '../common/types/AppError';
import { NameValue } from '../common/types/NameValue';
import type { ClockPort, LoggerPort } from '../common/types/Ports';
import { DeviceType } from '../common/constants/DeviceConstants';
import { TransportProfile } from '../model/DeviceTypes';
import { DeviceFilter, DeviceFilterKind, EnvironmentSummary, GatewayLinkState,
  CloudLinkState, GatewayStatus, LoadPhase, ViewModelError, ViewModelSupport } from './core/ViewModelCore';
import type {
  AppContextPort,
  ViewModelBase,
  VmTimerPort
} from './core/ViewModelCore';
import { I18nService } from '../service/i18n/I18nService';
import { FamilyService } from '../service/family/FamilyService';
import { RoomService } from '../service/room/RoomService';
import { CloudService } from '../service/cloud/CloudService';
import { DeviceRepository } from '../repository/DeviceRepository';
import type { DeviceRecord, DiscoverApplyOptions } from '../repository/DomainModels';
import { DiscoverApplyOptions as DiscoverApplyOptionsValue } from '../repository/DomainModels';
import { GatewayAddress } from '../model/GatewayRoute';
import type { GatewayRoute } from '../model/GatewayRoute';
import { GatewayTarget } from '../service/gateway/GatewayTransportPorts';
import type { IGatewayClient } from '../service/gateway/GatewayTransportPorts';
import type { CloudConfigView } from '../service/cloud/CloudModels';
import { CloudTransportState } from '../service/cloud/CloudModels';
import type { Family, Room } from '../model/FamilyModels';
import type { GatewayRoutePort } from '../repository/GatewayPorts';
import type { ManualDiscoveryPort } from './ViewModelPorts';

const TAG: string = 'HomeViewModel';

export class HomeViewState {
  readonly phase: LoadPhase;
  readonly families: ReadonlyArray<Family>;
  readonly activeFamily?: Family;
  readonly rooms: ReadonlyArray<Room>;
  readonly roomFilter: DeviceFilter;
  readonly records: ReadonlyArray<DeviceRecord>;
  readonly unassignedCount: number;
  readonly gatewayStatuses: ReadonlyArray<GatewayStatus>;
  readonly environment: EnvironmentSummary;
  readonly lastRefreshAtMs?: number;
  readonly error?: ViewModelError;
  readonly needsUnlock: boolean;
  readonly revision: number;

  constructor(phase: LoadPhase, families: ReadonlyArray<Family>, activeFamily: Family | undefined,
    rooms: ReadonlyArray<Room>, roomFilter: DeviceFilter, records: ReadonlyArray<DeviceRecord>,
    unassignedCount: number, gatewayStatuses: ReadonlyArray<GatewayStatus>,
    environment: EnvironmentSummary, revision: number, lastRefreshAtMs?: number,
    error?: ViewModelError, needsUnlock: boolean = false) {
    this.phase = phase;
    this.families = families;
    this.activeFamily = activeFamily;
    this.rooms = rooms;
    this.roomFilter = roomFilter;
    this.records = records;
    this.unassignedCount = unassignedCount;
    this.gatewayStatuses = gatewayStatuses;
    this.environment = environment;
    this.lastRefreshAtMs = lastRefreshAtMs;
    this.error = error;
    this.needsUnlock = needsUnlock;
    this.revision = revision;
  }

  static initial(): HomeViewState {
    return new HomeViewState(LoadPhase.IDLE, [], undefined, [], DeviceFilter.all(), [], 0, [],
      EnvironmentSummary.empty(), 0);
  }
}

export class HomeViewModel implements ViewModelBase<HomeViewState> {
  private readonly families: FamilyService;
  private readonly rooms: RoomService;
  private readonly devices: DeviceRepository;
  private readonly routes: GatewayRoutePort;
  private readonly client: IGatewayClient;
  private readonly discovery: ManualDiscoveryPort;
  private readonly cloud: CloudService;
  private readonly appContext: AppContextPort;
  private readonly i18n: I18nService;
  private readonly clock: ClockPort;
  private readonly timer: VmTimerPort;
  private readonly logger: LoggerPort;

  private state: HomeViewState = HomeViewState.initial();
  private listeners: Array<(state: HomeViewState) => void> = [];
  private allRecords: ReadonlyArray<DeviceRecord> = [];
  private revision: number = 0;
  private disposed: boolean = false;

  constructor(families: FamilyService, rooms: RoomService, devices: DeviceRepository,
    gateways: GatewayRoutePort, client: IGatewayClient, discovery: ManualDiscoveryPort,
    cloud: CloudService, appContext: AppContextPort, i18n: I18nService, clock: ClockPort,
    timer: VmTimerPort, logger: LoggerPort) {
    this.families = families;
    this.rooms = rooms;
    this.devices = devices;
    this.routes = gateways;
    this.client = client;
    this.discovery = discovery;
    this.cloud = cloud;
    this.appContext = appContext;
    this.i18n = i18n;
    this.clock = clock;
    this.timer = timer;
    this.logger = logger;
  }

  getState(): HomeViewState {
    return this.state;
  }

  subscribe(listener: (state: HomeViewState) => void): () => void {
    this.listeners.push(listener);
    return (): void => {
      const index = this.listeners.indexOf(listener);
      if (index >= 0) {
        this.listeners.splice(index, 1);
      }
    };
  }

  async initialize(): Promise<void> {
    this.publish(this.copy(LoadPhase.LOADING, undefined, undefined));
    try {
      const families = await this.families.listFamilies();
      const active = await this.families.getActiveFamily();
      this.state = new HomeViewState(LoadPhase.LOADING, families, active, this.state.rooms,
        this.state.roomFilter, this.state.records, this.state.unassignedCount,
        this.state.gatewayStatuses, this.state.environment, this.revision + 1,
        this.state.lastRefreshAtMs, undefined, false);
      if (active === undefined) {
        this.allRecords = [];
        this.publish(this.buildReady(families, active, [], [], EnvironmentSummary.empty()));
        return;
      }
      await this.refresh();
    } catch (error) {
      this.fail(error);
    }
  }

  async refresh(): Promise<void> {
    if (this.disposed) {
      return;
    }
    this.publish(this.copy(LoadPhase.LOADING, undefined, undefined));
    try {
      let families = this.state.families;
      let active = this.state.activeFamily;
      if (families.length === 0 || active === undefined) {
        families = await this.families.listFamilies();
        active = await this.families.getActiveFamily();
      }
      if (active === undefined) {
        this.allRecords = [];
        this.publish(this.buildReady(families, active, [], [], EnvironmentSummary.empty()));
        return;
      }
      const routes = await this.routes.listRoutesByFamily(active.familyId);
      const cloudState = await this.cloudLinkState();
      const statuses: GatewayStatus[] = [];
      const nowMs = this.clock.nowMs();
      for (let index = 0; index < routes.length; index++) {
        const status = await this.refreshGateway(routes[index], active.familyId, cloudState,
          nowMs);
        statuses.push(status);
      }
      const rooms = await this.rooms.listRooms(active.familyId);
      this.allRecords = await this.devices.listRecords(active.familyId);
      const visible = this.applyFilter(this.allRecords, this.state.roomFilter);
      const environment = HomeViewModel.environmentOf(this.allRecords);
      const unassigned = await this.devices.listUnassigned(active.familyId);
      this.publish(new HomeViewState(LoadPhase.READY, families, active, rooms,
        this.state.roomFilter, visible, unassigned.length, statuses, environment,
        this.revision + 1, this.clock.nowMs(), undefined, this.state.needsUnlock));
    } catch (error) {
      this.fail(error);
    }
  }

  async selectFamily(familyId: string): Promise<void> {
    try {
      const result = await this.families.switchFamily(familyId);
      this.appContext.refreshSessionGate();
      this.state = new HomeViewState(this.state.phase, this.state.families, result.family,
        this.state.rooms, this.state.roomFilter, this.state.records, this.state.unassignedCount,
        this.state.gatewayStatuses, this.state.environment, this.revision + 1,
        this.state.lastRefreshAtMs, this.state.error, result.requiresUnlock);
      await this.refresh();
    } catch (error) {
      this.fail(error);
    }
  }

  setRoomFilter(filter: DeviceFilter): void {
    if (this.disposed) {
      return;
    }
    const visible = this.applyFilter(this.allRecords, filter);
    this.publish(new HomeViewState(this.state.phase, this.state.families,
      this.state.activeFamily, this.state.rooms, filter, visible, this.state.unassignedCount,
      this.state.gatewayStatuses, this.state.environment, this.revision + 1,
      this.state.lastRefreshAtMs, this.state.error, this.state.needsUnlock));
  }

  refreshEnvironment(): void {
    const environment = HomeViewModel.environmentOf(this.allRecords);
    this.publish(new HomeViewState(this.state.phase, this.state.families,
      this.state.activeFamily, this.state.rooms, this.state.roomFilter, this.state.records,
      this.state.unassignedCount, this.state.gatewayStatuses, environment, this.revision + 1,
      this.state.lastRefreshAtMs, this.state.error, this.state.needsUnlock));
  }

  /** UI helper: resolves the mapped error key, never raw gateway text. */
  translateError(error: ViewModelError | undefined): string {
    return error === undefined ? '' : this.i18n.t(error.i18nKey);
  }

  dispose(): void {
    this.disposed = true;
    this.listeners.splice(0, this.listeners.length);
  }

  private async refreshGateway(route: GatewayRoute, familyId: string,
    cloud: CloudLinkState, nowMs: number): Promise<GatewayStatus> {
    if (route.profile === TransportProfile.P_BLOCKED) {
      return new GatewayStatus(route.gatewayId, route.gatewayName, GatewayLinkState.BLOCKED,
        cloud, route.profile, undefined, route.lastSeenAt, 'gateway.security.unavailable');
    }
    const ip = route.lastKnownIp.length > 0 ? route.lastKnownIp : route.localIp;
    if (ip.length === 0) {
      return new GatewayStatus(route.gatewayId, route.gatewayName, GatewayLinkState.UNKNOWN,
        cloud, route.profile, undefined, route.lastSeenAt);
    }
    const startedAtMs = this.clock.nowMs();
    try {
      const target = new GatewayTarget(route.gatewayId, route.familyId,
        new GatewayAddress(ip, route.port), route.profile, route.pins, route.port,
        route.credentialAlias);
      const snapshot = await this.client.discover(target);
      const options: DiscoverApplyOptions = new DiscoverApplyOptionsValue(familyId,
        this.clock.nowMs(), true);
      await this.devices.applyDiscoverSnapshot(snapshot, options);
      return new GatewayStatus(route.gatewayId, route.gatewayName, GatewayLinkState.ONLINE,
        cloud, route.profile, Math.max(0, this.clock.nowMs() - startedAtMs), route.lastSeenAt);
    } catch (error) {
      const appError = ViewModelSupport.asAppError(error);
      const blocked = appError.code === 'GATEWAY_PROFILE_BLOCKED' ||
        appError.code.startsWith('TLS_');
      this.logger.warn(TAG, 'gateway_refresh_failed',
        [new NameValue('gatewayId', route.gatewayId), new NameValue('code', appError.code)]);
      return new GatewayStatus(route.gatewayId, route.gatewayName,
        blocked ? GatewayLinkState.BLOCKED : GatewayLinkState.OFFLINE, cloud, route.profile,
        undefined, route.lastSeenAt,
        blocked ? 'gateway.security.unavailable' : undefined);
    }
  }

  private async cloudLinkState(): Promise<CloudLinkState> {
    try {
      const view: CloudConfigView = await this.cloud.getState();
      if (view.state === CloudTransportState.CONFIGURED) {
        return CloudLinkState.CONFIGURED;
      }
      if (view.state === CloudTransportState.NOT_CONFIGURED) {
        return CloudLinkState.NOT_CONFIGURED;
      }
      if (view.state === CloudTransportState.TOKEN_MISSING ||
        view.state === CloudTransportState.TOKEN_EXPIRED) {
        return CloudLinkState.TOKEN_EXPIRED;
      }
      if (view.state === CloudTransportState.TOKEN_INVALID) {
        return CloudLinkState.TOKEN_INVALID;
      }
      if (view.state === CloudTransportState.UNAVAILABLE) {
        return CloudLinkState.UNAVAILABLE;
      }
      return CloudLinkState.UNKNOWN;
    } catch (error) {
      return CloudLinkState.UNKNOWN;
    }
  }

  private buildReady(families: ReadonlyArray<Family>, active: Family | undefined,
    rooms: ReadonlyArray<Room>, statuses: ReadonlyArray<GatewayStatus>,
    environment: EnvironmentSummary): HomeViewState {
    return new HomeViewState(LoadPhase.READY, families, active, rooms,
      this.state.roomFilter, this.applyFilter(this.allRecords, this.state.roomFilter),
      this.state.unassignedCount, statuses, environment, this.revision + 1, this.clock.nowMs(),
      undefined, this.state.needsUnlock);
  }

  private applyFilter(records: ReadonlyArray<DeviceRecord>,
    filter: DeviceFilter): ReadonlyArray<DeviceRecord> {
    const result: DeviceRecord[] = [];
    for (let index = 0; index < records.length; index++) {
      const record = records[index];
      if (filter.kind === DeviceFilterKind.ALL) {
        result.push(record);
      } else if (filter.kind === DeviceFilterKind.ROOM &&
        record.state.roomId === filter.roomId) {
        result.push(record);
      } else if (filter.kind === DeviceFilterKind.UNASSIGNED && record.state.isUnassigned) {
        result.push(record);
      }
    }
    return result;
  }

  private static environmentOf(records: ReadonlyArray<DeviceRecord>): EnvironmentSummary {
    let temperature: number | undefined = undefined;
    let humidity: number | undefined = undefined;
    let presence: boolean | undefined = undefined;
    let temperatureEpoch = -1;
    let humidityEpoch = -1;
    let presenceEpoch = -1;
    let updatedAt: string | undefined = undefined;
    let source: string | undefined = undefined;
    for (let index = 0; index < records.length; index++) {
      const record = records[index];
      if (record.state.snapshot.deviceType !== DeviceType.SENSOR) {
        continue;
      }
      const snapshot = record.state.snapshot;
      if (snapshot.temperature !== undefined && snapshot.stateEpochMs > temperatureEpoch) {
        temperature = snapshot.temperature;
        temperatureEpoch = snapshot.stateEpochMs;
        updatedAt = snapshot.updatedAt;
        source = snapshot.stateSource;
      }
      if (snapshot.humidity !== undefined && snapshot.stateEpochMs > humidityEpoch) {
        humidity = snapshot.humidity;
        humidityEpoch = snapshot.stateEpochMs;
      }
      if (snapshot.presence !== undefined && snapshot.stateEpochMs > presenceEpoch) {
        presence = snapshot.presence;
        presenceEpoch = snapshot.stateEpochMs;
      }
    }
    return new EnvironmentSummary(temperature, humidity, presence, updatedAt, source);
  }

  private copy(phase: LoadPhase, error: ViewModelError | undefined,
    needsUnlock: boolean | undefined): HomeViewState {
    return new HomeViewState(phase, this.state.families, this.state.activeFamily,
      this.state.rooms, this.state.roomFilter, this.state.records, this.state.unassignedCount,
      this.state.gatewayStatuses, this.state.environment, this.revision + 1,
      this.state.lastRefreshAtMs, error,
      needsUnlock === undefined ? this.state.needsUnlock : needsUnlock);
  }

  private fail(error: Object): void {
    const viewError = ViewModelSupport.viewError(error, this.clock);
    this.logger.warn(TAG, 'view_model_error', [new NameValue('code', viewError.error.code)]);
    this.state = new HomeViewState(LoadPhase.ERROR, this.state.families,
      this.state.activeFamily, this.state.rooms, this.state.roomFilter, this.state.records,
      this.state.unassignedCount, this.state.gatewayStatuses, this.state.environment,
      this.revision + 1, this.state.lastRefreshAtMs, viewError, this.state.needsUnlock);
    this.emit();
  }

  private publish(next: HomeViewState): void {
    this.revision = next.revision;
    this.state = next;
    this.emit();
  }

  private emit(): void {
    for (let index = 0; index < this.listeners.length; index++) {
      try {
        this.listeners[index](this.state);
      } catch (error) {
        this.logger.warn(TAG, 'listener_failed',
          [new NameValue('code', ViewModelSupport.codeOf(error as Object))]);
      }
    }
  }
}
