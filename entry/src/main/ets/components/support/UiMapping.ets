/*
 * YaoCore C-24/C-25/C-26/C-27 pure presentation selectors.
 * Producer: agent:implementation-engineer | Task: T-18 / wp-073-ui-pages
 * Contract: DES-B §13.4, §14.4, §15.4, §16.4; D-019 host layer
 *
 * No ArkUI decorator, no @ohos import, no service/repository instantiation.
 * Host tests import this module directly; pages/components only render the
 * returned values and keys.
 */
import { DeviceType } from '../../common/constants/DeviceConstants';
import { DeviceKey } from '../../model/DeviceKey';
import type { Room } from '../../model/FamilyModels';
import type { DeviceRecord } from '../../model/DeviceRecord';
import type { SceneExecutionProgress, SceneExecutionResult } from '../../model/SceneExecutionModels';
import {
  ControlPhase,
  ControlUiState,
  DeviceFilter,
  DeviceFilterKind
} from '../../viewmodel/core/ViewModelCore';
import { CardVisualState, AsyncUiState } from '../../common/theme/AppEnums';
import {
  DoorStage,
  DoorUiState
} from '../../viewmodel/core/DoorConfirmationTracker';
import { AcModeViewKind, AcVocabulary } from '../../service/ac/AcModels';
import { AcViewState } from '../../service/ac/AcModels';
import { AcBrand } from '../../service/ac/AcModels';
import {
  DoorLinkConfig,
  DoorLockState
} from '../../viewmodel/core/DoorConfirmationTracker';
import { InviteMode, MemberRole } from '../../model/FamilyModels';
import type { TransportProfile } from '../../model/DeviceTypes';
import { TransportProfile as Profile } from '../../model/DeviceTypes';

const COLOR_PATTERN: RegExp = /^#[0-9A-Fa-f]{6}$/;

/**
 * Device-payload colour presets, not UI theme colours (I18N-08 applies to the
 * latter only). Values are sent verbatim to SET_COLOR.
 */
export const LIGHT_COLOR_PRESETS: ReadonlyArray<string> = [
  '#FFD8A8', '#FFB4A2', '#F9E79F', '#A7F3D0', '#A5D8FF', '#D8C4F0', '#FFFFFF'
];

export class UiMapping {
  static deviceTypeKey(type: DeviceType | undefined): string {
    if (type === undefined) {
      return 'device.type.unknown';
    }
    return 'device.type.' + type.toLowerCase();
  }

  static isDisabled(record: DeviceRecord): boolean {
    return !record.state.isEnabled || record.state.isUnassigned || record.state.isDismissed ||
      record.gatewayRemoved;
  }

  static isReadOnly(record: DeviceRecord): boolean {
    return !record.isSupported || !record.isControlAllowed;
  }

  /**
   * DES-B §13.1.4 / §14.3(3): offline, disabled and read-only devices may be
   * viewed but never controlled. PENDING is deliberately allowed: the user is
   * still dragging the 55ms slider, and the VM de-duplicates same-action
   * commands instead of freezing the control.
   */
  static controlsEnabled(record: DeviceRecord | undefined): boolean {
    const visual = UiMapping.visualState(record, undefined);
    return visual !== CardVisualState.DISABLED && visual !== CardVisualState.OFFLINE &&
      visual !== CardVisualState.READ_ONLY;
  }

  /**
   * Four-stage door progress. UNVERIFIED/UNCONFIRMED/WAITING_CONTACT stop at
   * stage 3; FAILED/UNKNOWN must not render a completed fourth stage (SC-14:
   * no evidence => never look "secured").
   */
  static doorStageProgress(stage: DoorStage): number {
    switch (stage) {
      case DoorStage.PENDING:
        return 1;
      case DoorStage.GATEWAY_CONFIRMED:
        return 2;
      case DoorStage.WAITING_CONTACT:
      case DoorStage.UNCONFIRMED:
      case DoorStage.UNVERIFIED:
        return 3;
      case DoorStage.SECURED:
      case DoorStage.OPEN:
        return 4;
      case DoorStage.FAILED:
      case DoorStage.UNKNOWN:
      default:
        return 0;
    }
  }

  /** UNKNOWN_INITIAL is "unknown", never "door link unverified". */
  static lockKeyFor(lockState: DoorLockState): string {
    if (lockState === DoorLockState.SECURED) {
      return 'door.state.secured';
    }
    if (lockState === DoorLockState.UNCONFIRMED) {
      return 'door.state.unconfirmed';
    }
    if (lockState === DoorLockState.OPEN) {
      return 'device.door.stage.open';
    }
    return 'door.state.unknown';
  }

  /**
   * DES-B §13.3(4): control phase maps IDLE/PENDING/COMMITTED/REVERT; device
   * offline/disabled/read-only always overrides the control phase.
   */
  static visualState(record: DeviceRecord | undefined,
    control: ControlUiState | undefined): CardVisualState {
    if (record === undefined) {
      return CardVisualState.DISABLED;
    }
    if (UiMapping.isDisabled(record)) {
      return CardVisualState.DISABLED;
    }
    if (!record.state.snapshot.isOnline || record.gatewayRemoved) {
      return CardVisualState.OFFLINE;
    }
    if (UiMapping.isReadOnly(record)) {
      return CardVisualState.READ_ONLY;
    }
    if (control === undefined) {
      return CardVisualState.IDLE;
    }
    if (control.phase === ControlPhase.PENDING) {
      return CardVisualState.PENDING;
    }
    if (control.phase === ControlPhase.COMMITTED) {
      return CardVisualState.COMMITTED;
    }
    if (control.phase === ControlPhase.REVERT) {
      return CardVisualState.REVERT;
    }
    return CardVisualState.IDLE;
  }

  static cardStateKey(state: CardVisualState): string {
    switch (state) {
      case CardVisualState.PENDING:
        return 'card.state.pending';
      case CardVisualState.COMMITTED:
        return 'card.state.committed';
      case CardVisualState.REVERT:
        return 'card.state.revert';
      case CardVisualState.OFFLINE:
        return 'device.state.offline';
      case CardVisualState.DISABLED:
        return 'card.state.disabled';
      case CardVisualState.READ_ONLY:
        return 'card.state.read_only';
      default:
        return 'card.state.idle';
    }
  }

  static loadState(phase: string, hasData: boolean): AsyncUiState {
    if (phase === 'ERROR') {
      return AsyncUiState.ERROR;
    }
    if (phase === 'LOADING' || phase === 'IDLE') {
      return AsyncUiState.LOADING;
    }
    return hasData ? AsyncUiState.READY : AsyncUiState.EMPTY;
  }

  static roomNameFor(record: DeviceRecord | undefined, rooms: ReadonlyArray<Room>): string {
    if (record === undefined || record.state.roomId.length === 0) {
      return '';
    }
    for (let index = 0; index < rooms.length; index++) {
      if (rooms[index].roomId === record.state.roomId) {
        return rooms[index].roomName;
      }
    }
    return '';
  }

  static roomNameById(roomId: string | undefined, rooms: ReadonlyArray<Room>): string {
    if (roomId === undefined || roomId.length === 0) {
      return '';
    }
    for (let index = 0; index < rooms.length; index++) {
      if (rooms[index].roomId === roomId) {
        return rooms[index].roomName;
      }
    }
    return '';
  }

  static findRecord(records: ReadonlyArray<DeviceRecord>, key: DeviceKey): DeviceRecord | undefined {
    for (let index = 0; index < records.length; index++) {
      if (records[index].state.key.gatewayId === key.gatewayId &&
        records[index].state.key.deviceId === key.deviceId) {
        return records[index];
      }
    }
    return undefined;
  }

  static findControl(controls: ReadonlyArray<ControlUiState>,
    key: DeviceKey): ControlUiState | undefined {
    for (let index = 0; index < controls.length; index++) {
      if (controls[index].key.gatewayId === key.gatewayId &&
        controls[index].key.deviceId === key.deviceId) {
        return controls[index];
      }
    }
    return undefined;
  }

  static powerValue(record: DeviceRecord | undefined,
    control: ControlUiState | undefined): boolean {
    if (control !== undefined && control.optimisticValue !== undefined &&
      control.phase === ControlPhase.PENDING && typeof control.optimisticValue === 'boolean') {
      return control.optimisticValue as boolean;
    }
    return record !== undefined && record.state.snapshot.powerStatus === true;
  }

  static brightnessValue(record: DeviceRecord | undefined,
    control: ControlUiState | undefined): number {
    if (control !== undefined && control.optimisticValue !== undefined &&
      control.phase === ControlPhase.PENDING && typeof control.optimisticValue === 'number') {
      return UiMapping.clampNumber(control.optimisticValue as number, 0, 100);
    }
    if (control !== undefined && control.confirmedValue !== undefined &&
      typeof control.confirmedValue === 'number') {
      return UiMapping.clampNumber(control.confirmedValue as number, 0, 100);
    }
    return record !== undefined && record.state.snapshot.brightness !== undefined
      ? record.state.snapshot.brightness : 0;
  }

  static temperatureValue(record: DeviceRecord | undefined,
    control: ControlUiState | undefined): number {
    if (control !== undefined && control.optimisticValue !== undefined &&
      control.phase === ControlPhase.PENDING && typeof control.optimisticValue === 'number') {
      return UiMapping.clampNumber(control.optimisticValue as number, 16, 30);
    }
    if (control !== undefined && control.confirmedValue !== undefined &&
      typeof control.confirmedValue === 'number') {
      return UiMapping.clampNumber(control.confirmedValue as number, 16, 30);
    }
    return record !== undefined && record.state.snapshot.targetTemperature !== undefined
      ? record.state.snapshot.targetTemperature : 24;
  }

  static colorValue(record: DeviceRecord | undefined): string {
    if (record === undefined || record.state.snapshot.color === undefined) {
      return LIGHT_COLOR_PRESETS[0];
    }
    return COLOR_PATTERN.test(record.state.snapshot.color)
      ? record.state.snapshot.color : LIGHT_COLOR_PRESETS[0];
  }

  static isKnownColor(value: string): boolean {
    return COLOR_PATTERN.test(value);
  }

  static clampNumber(value: number, min: number, max: number): number {
    if (!Number.isFinite(value)) {
      return min;
    }
    if (value < min) {
      return min;
    }
    if (value > max) {
      return max;
    }
    return value;
  }

  static roomDeviceCount(records: ReadonlyArray<DeviceRecord>, roomId: string): number {
    let count = 0;
    for (let index = 0; index < records.length; index++) {
      if (records[index].state.roomId === roomId) {
        count++;
      }
    }
    return count;
  }

  static unassignedCount(records: ReadonlyArray<DeviceRecord>): number {
    let count = 0;
    for (let index = 0; index < records.length; index++) {
      if (records[index].state.isUnassigned) {
        count++;
      }
    }
    return count;
  }

  static filterMatches(filter: DeviceFilter, record: DeviceRecord): boolean {
    if (filter.kind === DeviceFilterKind.ALL) {
      return true;
    }
    if (filter.kind === DeviceFilterKind.ROOM) {
      return record.state.roomId === filter.roomId;
    }
    return record.state.isUnassigned;
  }

  static filterKey(filter: DeviceFilter): string {
    if (filter.kind === DeviceFilterKind.ROOM && filter.roomId !== undefined) {
      return 'room:' + filter.roomId;
    }
    if (filter.kind === DeviceFilterKind.UNASSIGNED) {
      return 'unassigned';
    }
    return 'all';
  }

  // ---- Scene ---------------------------------------------------------------

  static sceneStepKey(state: string): string {
    switch (state) {
      case 'RUNNING':
        return 'scene.step.running';
      case 'SUCCEEDED':
        return 'scene.step.succeeded';
      case 'FAILED':
        return 'scene.step.failed';
      case 'SKIPPED':
        return 'scene.step.skipped';
      case 'CANCELLED':
        return 'scene.step.cancelled';
      default:
        return 'scene.step.pending';
    }
  }

  static sceneStepMarker(state: string): string {
    switch (state) {
      case 'SUCCEEDED':
        return '✓';
      case 'FAILED':
        return '✗';
      case 'SKIPPED':
      case 'CANCELLED':
        return '–';
      case 'RUNNING':
        return '…';
      default:
        return '·';
    }
  }

  static sceneRunKey(state: string | undefined): string {
    switch (state) {
      case 'PREFLIGHT':
        return 'scene.state.preflight';
      case 'RUNNING':
        return 'scene.running';
      case 'SUCCEEDED':
        return 'scene.state.succeeded';
      case 'PARTIAL_FAILED':
        return 'scene.partial_failed';
      case 'FAILED':
        return 'scene.state.failed';
      case 'CANCELLED':
        return 'scene.state.cancelled';
      default:
        return 'scene.state.idle';
    }
  }

  static sceneNoRollback(progress: SceneExecutionProgress | undefined,
    result: SceneExecutionResult | undefined): boolean {
    if (progress !== undefined && (progress.state === 'PARTIAL_FAILED' ||
      progress.state === 'FAILED' || progress.state === 'CANCELLED')) {
      return progress.executedCount > 0;
    }
    if (result !== undefined && result.noRollbackNotice &&
      (result.state === 'PARTIAL_FAILED' || result.state === 'FAILED' ||
        result.state === 'CANCELLED')) {
      return result.executedCount > 0;
    }
    return false;
  }

  static sceneIsRunning(state: string | undefined): boolean {
    return state === 'PREFLIGHT' || state === 'RUNNING';
  }

  static sceneFailed(state: string | undefined): boolean {
    return state === 'PARTIAL_FAILED' || state === 'FAILED';
  }

  static progressPercent(progress: SceneExecutionProgress | undefined): number {
    if (progress === undefined || progress.steps.length === 0) {
      return 0;
    }
    return Math.round((progress.executedCount / progress.steps.length) * 100);
  }

  // ---- Family -------------------------------------------------------------

  static joinPhaseKey(phase: string | undefined): string {
    switch (phase) {
      case 'JOIN_REQUEST_READY':
        return 'family.join.phase.request_ready';
      case 'WAITING_FOR_INVITATION':
        return 'family.join.phase.waiting';
      case 'CODE_REQUIRED':
        return 'family.join.phase.code_required';
      case 'VALIDATING':
        return 'family.join.phase.validating';
      case 'APPLYING':
        return 'family.join.phase.applying';
      case 'MEMBER_BOUND':
        return 'family.join.phase.member_bound';
      case 'COMPLETED':
        return 'family.join.phase.completed';
      case 'FAILED':
        return 'family.join.phase.failed';
      case 'CANCELLED':
        return 'family.join.phase.cancelled';
      default:
        return 'family.join.phase.idle';
    }
  }

  static joinCanSubmit(phase: string | undefined): boolean {
    return phase === 'JOIN_REQUEST_READY' ||
      phase === 'WAITING_FOR_INVITATION' ||
      phase === 'CODE_REQUIRED';
  }

  static joinNeedsProfile(phase: string | undefined): boolean {
    return phase === 'MEMBER_BOUND';
  }

  static inviteNeedsRooms(role: MemberRole): boolean {
    return role === MemberRole.GUEST;
  }

  static inviteInputValid(role: MemberRole, roomIds: ReadonlyArray<string>): boolean {
    if (role === MemberRole.ADMIN) {
      return false;
    }
    return !UiMapping.inviteNeedsRooms(role) || roomIds.length > 0;
  }

  static weakInviteMode(mode: InviteMode): boolean {
    return mode === InviteMode.CODE_KEK;
  }

  static inviteModeKey(mode: InviteMode): string {
    return mode === InviteMode.CODE_KEK ? 'invite.mode.code_kek' : 'invite.mode.key_wrap';
  }

  static roleKey(role: MemberRole): string {
    return 'member.role.' + role.toLowerCase();
  }

  static canManageFamily(canManageFamily: boolean | undefined): boolean {
    return canManageFamily === true;
  }

  static canInvite(canInvite: boolean | undefined): boolean {
    return canInvite === true;
  }

  // ---- AC ------------------------------------------------------------------

  static acModeKey(ac: AcViewState | undefined): string {
    if (ac === undefined) {
      return 'ac.mode.unknown';
    }
    if (ac.mode.kind === AcModeViewKind.UNKNOWN) {
      return 'ac.mode.unknown';
    }
    return ac.mode.i18nKey;
  }

  static acBrandKey(ac: AcViewState | undefined): string {
    return ac === undefined ? 'brand.generic' : ac.brandI18nKey;
  }

  static acEditable(ac: AcViewState | undefined): boolean {
    return ac !== undefined && !ac.isReadOnly && ac.mode.kind !== AcModeViewKind.NON_STANDARD;
  }

  /**
   * Read-only preview for Home quick cards (C-25 §14.1.2): no control command
   * is inferred; the detail page owns the full C-21 ClimateViewModel.
   */
  static acPreview(record: DeviceRecord | undefined): AcViewState {
    if (record === undefined) {
      return new AcViewState(undefined, undefined, AcVocabulary.view(undefined),
        AcBrand.GENERIC, AcVocabulary.brandI18nKey(AcBrand.GENERIC), true);
    }
    const snapshot = record.state.snapshot;
    const brandKey = snapshot.brand === undefined || snapshot.brand.length === 0 ?
      'brand.generic' : 'brand.' + snapshot.brand.toLowerCase();
    let brand: AcBrand = AcBrand.GENERIC;
    if (snapshot.brand !== undefined) {
      const lowered = snapshot.brand.toLowerCase();
      if (lowered === 'gree') {
        brand = AcBrand.GREE;
      } else if (lowered === 'haier') {
        brand = AcBrand.HAIER;
      } else if (lowered === 'midea') {
        brand = AcBrand.MIDEA;
      }
    }
    return new AcViewState(snapshot.powerStatus, snapshot.targetTemperature,
      AcVocabulary.view(snapshot.mode), brand, brandKey, !record.isControlAllowed);
  }

  /** Door preview for Home quick cards; the detail page owns DoorViewModel. */
  static doorPreview(record: DeviceRecord | undefined): DoorUiState {
    return new DoorUiState(DoorStage.UNVERIFIED, DoorLockState.UNKNOWN,
      DoorLinkConfig.none(), false, record === undefined ? 0 : record.merge.lastSnapshotAtMs);
  }

  // ---- Door ----------------------------------------------------------------

  static doorStageKey(stage: DoorStage): string {
    switch (stage) {
      case DoorStage.PENDING:
        return 'device.door.stage.pending';
      case DoorStage.GATEWAY_CONFIRMED:
        return 'device.door.stage.gateway_confirmed';
      case DoorStage.WAITING_CONTACT:
        return 'device.door.stage.waiting_contact';
      case DoorStage.SECURED:
        return 'door.state.secured';
      case DoorStage.OPEN:
        return 'device.door.stage.open';
      case DoorStage.UNCONFIRMED:
        return 'door.state.unconfirmed';
      case DoorStage.UNKNOWN:
        return 'door.state.unknown';
      case DoorStage.UNVERIFIED:
        return 'door.link.unverified';
      case DoorStage.FAILED:
        return 'device.door.stage.failed';
      default:
        return 'device.door.stage.idle';
    }
  }

  static doorNeedsLinkGuide(door: DoorUiState | undefined): boolean {
    return door !== undefined && door.link.mode === 'NONE' &&
      door.stage === DoorStage.IDLE;
  }

  static doorAlarmKey(door: DoorUiState | undefined): string {
    if (door === undefined || !door.alertActive) {
      return '';
    }
    return 'door.alert.unconfirmed';
  }

  // ---- Provisioning --------------------------------------------------------

  static provisioningStepIndex(step: number): number {
    if (!Number.isInteger(step) || step < 0) {
      return 0;
    }
    if (step > 5) {
      return 5;
    }
    return step;
  }

  static provisioningStepKey(index: number): string {
    return 'provisioning.step' + String(UiMapping.provisioningStepIndex(index));
  }

  static provisioningProgressKey(state: string): string {
    return 'provisioning.progress.' + state.toLowerCase();
  }

  static provisioningErrorStep(errorCode: string | undefined): number {
    if (errorCode === undefined || errorCode.length === 0) {
      return 0;
    }
    if (errorCode === 'PROVISIONING_PERMISSION_DENIED' ||
      errorCode === 'PROVISIONING_BLUETOOTH_OFF') {
      return 0;
    }
    if (errorCode === 'PROVISIONING_DEVICE_NOT_FOUND') {
      return 1;
    }
    if (errorCode === 'PROVISIONING_POP_INVALID' ||
      errorCode === 'PROVISIONING_SECURITY_HANDSHAKE_FAILED' ||
      errorCode === 'PROVISIONING_IDENTITY_INVALID' ||
      errorCode === 'PROVISIONING_CONNECT_FAILED') {
      return 2;
    }
    if (errorCode === 'PROVISIONING_WIFI_AUTH_ERROR' ||
      errorCode === 'PROVISIONING_WIFI_NETWORK_NOT_FOUND') {
      return 3;
    }
    if (errorCode === 'PROVISIONING_WIFI_TIMEOUT' ||
      errorCode === 'PROVISIONING_CREDENTIAL_MISSING' ||
      errorCode === 'PROVISIONING_SECRET_DRAFT_EXPIRED' ||
      errorCode === 'PROVISIONING_BINDING_PROBE_FAILED' ||
      errorCode === 'PROVISIONING_BOARD_LED_UNCONFIRMED') {
      return 4;
    }
    return 0;
  }

  // ---- Settings ------------------------------------------------------------

  static localeModeKey(mode: string): string {
    if (mode === 'ZH_CN') {
      return 'settings.language.zh_cn';
    }
    if (mode === 'EN_US') {
      return 'settings.language.en_us';
    }
    return 'settings.language.auto';
  }

  static cloudStateKey(state: string | undefined): string {
    switch (state) {
      case 'CONFIGURED':
        return 'cloud.state.configured';
      case 'TOKEN_MISSING':
        return 'cloud.state.token_missing';
      case 'TOKEN_EXPIRED':
        return 'cloud.state.token_expired';
      case 'TOKEN_INVALID':
        return 'cloud.state.token_invalid';
      case 'UNAVAILABLE':
        return 'cloud.state.unavailable';
      default:
        return 'cloud.state.not_configured';
    }
  }

  static cloudNeedsToken(state: string | undefined): boolean {
    return state === 'TOKEN_EXPIRED' || state === 'TOKEN_INVALID' || state === 'TOKEN_MISSING';
  }

  static securityProfileKey(profile: TransportProfile, pinCount: number): string {
    if (profile === Profile.P_HMAC) {
      return 'gateway.security.hmac_only';
    }
    if (profile === Profile.P_TLS_PIN) {
      return 'gateway.security.tls_pinned';
    }
    return 'gateway.security.unavailable';
  }

  static settingsSectionKey(section: string): string {
    return 'settings.section.' + section.toLowerCase();
  }

  static isManualAddressRejected(code: string | undefined): boolean {
    return code === 'MANUAL_ADDRESS_REJECTED' || code === 'MANUAL_ADDRESS_NOT_BOUND';
  }
}
