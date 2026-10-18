/*
 * YaoCore C-22 RoomViewModel.
 * Producer: agent:implementation-engineer | Task: T-16 / wp-060-vm
 * Contract: DES-B §11.1.2, §11.3.3; FR-ROOM-001..006; D-019
 *
 * Room deletion is always a blocking two-step flow: preview (device count and
 * names) then confirmation carrying the acknowledged count. Devices are moved
 * to the unassigned/disabled pool, never deleted; no LAN/cloud request is made.
 */
import { AppErrors } from '../common/types/AppError';
import { NameValue } from '../common/types/NameValue';
import type { ClockPort } from '../common/types/Ports';
import type { LoggerPort } from '../contracts/Ports';
import type { DeviceKey } from '../model/DeviceKey';
import type { Room } from '../model/FamilyModels';
import type { DeviceRecord } from '../model/DeviceRecord';
import type { RoomDeletionPreview, RoomDeletionResult } from '../service/room/RoomService';
import { RoomDeletionConfirmation } from '../service/room/RoomService';
import {
  LoadPhase,
  ViewModelError,
  ViewModelSupport
} from './core/ViewModelCore';
import type { ViewModelBase } from './core/ViewModelCore';
import { I18nService } from '../service/i18n/I18nService';
import { RoomService } from '../service/room/RoomService';
import { DeviceRepository } from '../repository/DeviceRepository';

const TAG: string = 'RoomViewModel';

/**
 * F-03: narrow session lookup supplied by the composition root. The view model
 * passes the active member id to RoomService, which refuses non-ADMIN actors.
 */
export interface RoomSessionPort {
  getMemberId(): string | undefined;
}

export class RoomViewState {
  readonly phase: LoadPhase;
  readonly rooms: ReadonlyArray<Room>;
  readonly unassignedRecords: ReadonlyArray<DeviceRecord>;
  readonly deletionPreview?: RoomDeletionPreview;
  readonly pendingAction: boolean;
  readonly error?: ViewModelError;
  readonly revision: number;

  constructor(phase: LoadPhase, rooms: ReadonlyArray<Room>,
    unassignedRecords: ReadonlyArray<DeviceRecord>, pendingAction: boolean, revision: number,
    deletionPreview?: RoomDeletionPreview, error?: ViewModelError) {
    this.phase = phase;
    this.rooms = rooms;
    this.unassignedRecords = unassignedRecords;
    this.pendingAction = pendingAction;
    this.deletionPreview = deletionPreview;
    this.error = error;
    this.revision = revision;
  }

  static initial(): RoomViewState {
    return new RoomViewState(LoadPhase.IDLE, [], [], false, 0);
  }
}

export class RoomViewModel implements ViewModelBase<RoomViewState> {
  private readonly rooms: RoomService;
  private readonly devices: DeviceRepository;
  private readonly i18n: I18nService;
  private readonly clock: ClockPort;
  private readonly logger: LoggerPort;
  private readonly session?: RoomSessionPort;

  private state: RoomViewState = RoomViewState.initial();
  private listeners: Array<(state: RoomViewState) => void> = [];
  private familyId: string = '';
  private revision: number = 0;
  private disposed: boolean = false;

  constructor(rooms: RoomService, devices: DeviceRepository, i18n: I18nService,
    clock: ClockPort, logger: LoggerPort, session?: RoomSessionPort) {
    this.rooms = rooms;
    this.devices = devices;
    this.i18n = i18n;
    this.clock = clock;
    this.logger = logger;
    this.session = session;
  }

  private actorMemberId(): string | undefined {
    return this.session === undefined ? undefined : this.session.getMemberId();
  }

  getState(): RoomViewState {
    return this.state;
  }

  subscribe(listener: (state: RoomViewState) => void): () => void {
    this.listeners.push(listener);
    return (): void => {
      const index = this.listeners.indexOf(listener);
      if (index >= 0) {
        this.listeners.splice(index, 1);
      }
    };
  }

  async initialize(familyId: string): Promise<void> {
    this.familyId = familyId;
    this.publish(this.copy(LoadPhase.LOADING, false, undefined, this.state.deletionPreview));
    await this.refresh();
  }

  async refresh(): Promise<void> {
    if (this.disposed) {
      return;
    }
    try {
      const rooms = await this.rooms.listRooms(this.familyId);
      const unassigned = await this.devices.listUnassigned(this.familyId);
      this.publish(new RoomViewState(LoadPhase.READY, rooms, unassigned, false,
        this.revision + 1, this.state.deletionPreview, undefined));
    } catch (error) {
      this.fail(error as Object);
    }
  }

  async createRoom(name: string, icon?: string): Promise<Room> {
    this.publish(this.copy(this.state.phase, true, undefined, this.state.deletionPreview));
    try {
      const room = await this.rooms.createRoom(this.familyId, name, icon,
        this.actorMemberId());
      await this.refresh();
      this.publish(this.copy(this.state.phase, false, undefined, this.state.deletionPreview));
      return room;
    } catch (error) {
      this.fail(error as Object);
      throw error as Error;
    }
  }

  async renameRoom(roomId: string, name: string): Promise<void> {
    this.publish(this.copy(this.state.phase, true, undefined, this.state.deletionPreview));
    try {
      await this.rooms.renameRoom(roomId, name, this.actorMemberId());
      await this.refresh();
      this.publish(this.copy(this.state.phase, false, undefined, this.state.deletionPreview));
    } catch (error) {
      this.fail(error as Object);
    }
  }

  async reorderRooms(orderedRoomIds: ReadonlyArray<string>): Promise<void> {
    this.publish(this.copy(this.state.phase, true, undefined, this.state.deletionPreview));
    try {
      await this.rooms.reorderRooms(this.familyId, orderedRoomIds, this.actorMemberId());
      await this.refresh();
      this.publish(this.copy(this.state.phase, false, undefined, this.state.deletionPreview));
    } catch (error) {
      this.fail(error as Object);
    }
  }

  async previewDelete(roomId: string): Promise<RoomDeletionPreview> {
    try {
      const preview = await this.rooms.previewDelete(roomId);
      this.publish(new RoomViewState(this.state.phase, this.state.rooms,
        this.state.unassignedRecords, false, this.revision + 1, preview, undefined));
      return preview;
    } catch (error) {
      this.fail(error as Object);
      throw error as Error;
    }
  }

  cancelDelete(): void {
    this.publish(new RoomViewState(this.state.phase, this.state.rooms,
      this.state.unassignedRecords, false, this.revision + 1, undefined, this.state.error));
  }

  async confirmDelete(roomId: string, acknowledgedCount: number): Promise<RoomDeletionResult> {
    this.publish(this.copy(this.state.phase, true, undefined, this.state.deletionPreview));
    try {
      const result = await this.rooms.deleteRoom(roomId,
        new RoomDeletionConfirmation(true, acknowledgedCount), this.actorMemberId());
      this.publish(new RoomViewState(this.state.phase, this.state.rooms,
        this.state.unassignedRecords, false, this.revision + 1, undefined, undefined));
      await this.refresh();
      return result;
    } catch (error) {
      // Keep the preview so the user can see the actual count and retry.
      this.fail(error as Object);
      throw error as Error;
    }
  }

  async assignDevice(key: DeviceKey, roomId: string): Promise<void> {
    this.publish(this.copy(this.state.phase, true, undefined, this.state.deletionPreview));
    try {
      await this.rooms.assignDevice(this.familyId, key, roomId, this.actorMemberId());
      await this.refresh();
      this.publish(this.copy(this.state.phase, false, undefined, this.state.deletionPreview));
    } catch (error) {
      this.fail(error as Object);
    }
  }

  async unassignDevice(key: DeviceKey): Promise<void> {
    this.publish(this.copy(this.state.phase, true, undefined, this.state.deletionPreview));
    try {
      await this.rooms.unassignDevice(this.familyId, key, this.actorMemberId());
      await this.refresh();
      this.publish(this.copy(this.state.phase, false, undefined, this.state.deletionPreview));
    } catch (error) {
      this.fail(error as Object);
    }
  }

  clearError(): void {
    this.publish(this.copy(this.state.phase, this.state.pendingAction, undefined,
      this.state.deletionPreview));
  }

  translateError(error: ViewModelError | undefined): string {
    return error === undefined ? '' : this.i18n.t(error.i18nKey);
  }

  dispose(): void {
    this.disposed = true;
    this.listeners.splice(0, this.listeners.length);
  }

  private copy(phase: LoadPhase, pendingAction: boolean, error: ViewModelError | undefined,
    preview: RoomDeletionPreview | undefined): RoomViewState {
    return new RoomViewState(phase, this.state.rooms, this.state.unassignedRecords,
      pendingAction, this.revision + 1, preview, error);
  }

  private fail(error: Object): void {
    const viewError = ViewModelSupport.viewError(error, this.clock);
    this.logger.warn(TAG, 'view_model_error', [new NameValue('code', viewError.error.code)]);
    this.publish(new RoomViewState(this.state.phase, this.state.rooms,
      this.state.unassignedRecords, false, this.revision + 1, this.state.deletionPreview,
      viewError));
  }

  private publish(next: RoomViewState): void {
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
