/*
 * YaoCore C-25 device grid and unassigned pool.
 * Producer: agent:implementation-engineer | Task: T-18 / wp-073-ui-pages
 * Contract: DES-B §13.1.3, §14.1.2, §14.1.3; FR-ROOM-001..006; D-011
 */
import type { I18nService } from '../service/i18n/I18nService';
import { DeviceType } from '../common/constants/DeviceConstants';
import type { DeviceRecord } from '../model/DeviceRecord';
import type { Room } from '../model/FamilyModels';
import type { DeviceKey } from '../model/DeviceKey';
import type { ControlUiState } from '../viewmodel/core/ViewModelCore';
import {
  AppColors,
  AppRadius,
  AppSpacing,
  AppTypography
} from '../common/theme/AppTheme';
import {
  ClimateCard,
  DoorCard,
  LightCard,
  SensorTile
} from './DeviceCards';
import { UiMapping } from './support/UiMapping';

@Component
export struct DeviceGrid {
  @Require i18n: I18nService;
  @Prop localeRevision: number = 0;
  @Prop records: ReadonlyArray<DeviceRecord> = [];
  @Prop controls: ReadonlyArray<ControlUiState> = [];
  @Prop rooms: ReadonlyArray<Room> = [];
  @Prop motionEnabled: boolean = true;
  onOpen: (key: DeviceKey) => void = (key: DeviceKey): void => {};
  onQuickToggle: (key: DeviceKey) => void = (key: DeviceKey): void => {};

  private controlOf(record: DeviceRecord): ControlUiState | undefined {
    return UiMapping.findControl(this.controls, record.state.key);
  }

  build() {
    Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap,
      justifyContent: FlexAlign.SpaceBetween }) {
      ForEach(this.records.slice(), (record: DeviceRecord): void => {
        Column() {
          if (record.state.snapshot.deviceType === DeviceType.LIGHT &&
            this.controlOf(record) !== undefined) {
            LightCard({
              i18n: this.i18n,
              localeRevision: this.localeRevision,
              record: record,
              control: this.controlOf(record) as ControlUiState,
              roomName: UiMapping.roomNameFor(record, this.rooms),
              compact: true,
              motionEnabled: this.motionEnabled,
              onToggle: (): void => {
                this.onQuickToggle(record.state.key);
              },
              onOpenDetail: (): void => {
                this.onOpen(record.state.key);
              }
            })
          } else if (record.state.snapshot.deviceType === DeviceType.AC &&
            this.controlOf(record) !== undefined) {
            ClimateCard({
              i18n: this.i18n,
              localeRevision: this.localeRevision,
              record: record,
              ac: UiMapping.acPreview(record),
              control: this.controlOf(record) as ControlUiState,
              roomName: UiMapping.roomNameFor(record, this.rooms),
              compact: true,
              motionEnabled: this.motionEnabled,
              onPower: (): void => {
                this.onQuickToggle(record.state.key);
              },
              onOpenDetail: (): void => {
                this.onOpen(record.state.key);
              }
            })
          } else if (record.state.snapshot.deviceType === DeviceType.DOOR &&
            this.controlOf(record) !== undefined) {
            DoorCard({
              i18n: this.i18n,
              localeRevision: this.localeRevision,
              record: record,
              door: UiMapping.doorPreview(record),
              control: this.controlOf(record) as ControlUiState,
              roomName: UiMapping.roomNameFor(record, this.rooms),
              compact: true,
              motionEnabled: this.motionEnabled,
              onOpenDetail: (): void => {
                this.onOpen(record.state.key);
              }
            })
          } else {
            SensorTile({
              i18n: this.i18n,
              localeRevision: this.localeRevision,
              record: record,
              roomName: UiMapping.roomNameFor(record, this.rooms),
              onOpen: (key: DeviceKey): void => {
                this.onOpen(key);
              }
            })
          }
        }
        .width('100%')
        .margin({ bottom: AppSpacing.sm })
      }, (record: DeviceRecord): string => record.state.key.globalId())
    }
    .width('100%')
  }
}

@Component
export struct UnassignedPool {
  @Require i18n: I18nService;
  @Prop localeRevision: number = 0;
  @Prop records: ReadonlyArray<DeviceRecord> = [];
  @Prop rooms: ReadonlyArray<Room> = [];
  @Prop motionEnabled: boolean = true;
  @Prop allowDelete: boolean = false;
  @Prop canAssign: boolean = false;
  @State assigningKey: string = '';
  @State selectedRoomId: string = '';
  onAssign: (key: DeviceKey, roomId: string) => void =
    (key: DeviceKey, roomId: string): void => {};
  onDelete: (key: DeviceKey) => void = (key: DeviceKey): void => {};
  onRefresh: () => void = (): void => {};

  build() {
    Column({ space: AppSpacing.xs }) {
      Row() {
        Text(this.i18n.t('room.unassigned.title'))
          .fontSize(AppTypography.section)
          .fontWeight(AppTypography.weightMedium)
          .fontColor(AppColors.ink())
          .layoutWeight(1)
        Text(this.i18n.t('device.disabled.hint'))
          .fontSize(AppTypography.caption)
          .fontColor(AppColors.amber())
        Button(this.i18n.t('common.refresh'))
          .height(44)
          .fontSize(AppTypography.caption)
          .fontColor(AppColors.primary())
          .backgroundColor(Color.Transparent)
          .onClick((): void => {
            this.onRefresh();
          })
      }
      .width('100%')
      if (this.records.length === 0) {
        Text(this.i18n.t('room.unassigned.empty'))
          .fontSize(AppTypography.body)
          .fontColor(AppColors.muted())
      }
      ForEach(this.records.slice(), (record: DeviceRecord): void => {
        Column({ space: AppSpacing.xxs }) {
          Row() {
            Column({ space: AppSpacing.xxs }) {
              Text(record.state.deviceName)
                .fontSize(AppTypography.body)
                .fontColor(AppColors.ink())
              Text(this.i18n.t(UiMapping.deviceTypeKey(record.state.snapshot.deviceType)) +
                ' · ' + this.i18n.t('device.disabled.unassigned'))
                .fontSize(AppTypography.caption)
                .fontColor(AppColors.amber())
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            if (this.canAssign) {
              Button(this.i18n.t('room.assign.action'))
                .height(44)
                .fontSize(AppTypography.caption)
                .fontColor(Color.White)
                .backgroundColor(AppColors.primary())
                .borderRadius(AppRadius.button)
                .enabled(this.rooms.length > 0)
                .onClick((): void => {
                  this.assigningKey = record.state.key.globalId();
                  this.selectedRoomId = this.rooms.length > 0 ? this.rooms[0].roomId : '';
                })
            }
            if (this.allowDelete) {
              Button(this.i18n.t('common.delete'))
                .height(44)
                .fontSize(AppTypography.caption)
                .fontColor(AppColors.red())
                .backgroundColor(Color.Transparent)
                .onClick((): void => {
                  this.onDelete(record.state.key);
                })
            }
          }
          .width('100%')
          if (this.canAssign && this.assigningKey === record.state.key.globalId()) {
            Scroll() {
              Row({ space: AppSpacing.xs }) {
                ForEach(this.rooms.slice(), (room: Room): void => {
                  Button(room.roomName)
                    .height(44)
                    .fontSize(AppTypography.caption)
                    .fontColor(this.selectedRoomId === room.roomId
                      ? Color.White : AppColors.inkSoft())
                    .backgroundColor(this.selectedRoomId === room.roomId
                      ? AppColors.primary() : AppColors.field())
                    .borderRadius(AppRadius.chip)
                    .onClick((): void => {
                      this.selectedRoomId = room.roomId;
                    })
                }, (room: Room): string => room.roomId)
                Button(this.i18n.t('common.confirm'))
                  .height(44)
                  .fontSize(AppTypography.caption)
                  .fontColor(Color.White)
                  .backgroundColor(AppColors.green())
                  .borderRadius(AppRadius.chip)
                  .enabled(this.selectedRoomId.length > 0)
                  .onClick((): void => {
                    if (this.selectedRoomId.length > 0) {
                      this.onAssign(record.state.key, this.selectedRoomId);
                      this.assigningKey = '';
                    }
                  })
              }
            }
            .scrollable(ScrollDirection.Horizontal)
            .scrollBar(BarState.Off)
            .width('100%')
          }
        }
        .width('100%')
        .padding(AppSpacing.sm)
        .backgroundColor(AppColors.field())
        .borderRadius(AppRadius.card)
      }, (record: DeviceRecord): string => record.state.key.globalId())
    }
    .width('100%')
    .padding(AppSpacing.md)
    .backgroundColor(AppColors.surface())
    .borderRadius(AppRadius.card)
    .border({ width: 1, color: AppColors.edge() })
    .alignItems(HorizontalAlign.Start)
  }
}
