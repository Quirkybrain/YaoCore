/*
 * YaoCore C-26 RoomManagePage.
 * Producer: agent:implementation-engineer | Task: T-18 / wp-073-ui-pages
 * Contract: DES-B §15.1.3, §15.2/§15.3; FR-ROOM-001..006; ADR-004 §2
 *
 * Room rename only changes roomName (ids stay fixed). Delete always uses
 * previewDelete -> blocking confirmation -> confirmDelete, and never deletes
 * physical devices: RoomService moves them into the disabled unassigned pool.
 */
import type { I18nService } from '../service/i18n/I18nService';
import { AppContext } from '../app/AppContext';
import type { AppRouteParams, NavigationService } from '../app/NavigationService';
import type { PageVmFactoryPort } from '../app/PageVmFactory';
import {
  AppColors,
  AppRadius,
  AppSpacing,
  AppTypography
} from '../common/theme/AppTheme';
import { MemberRole } from '../model/FamilyModels';
import type { Room } from '../model/FamilyModels';
import { NameValue } from '../common/types/NameValue';
import { I18nParams } from '../service/i18n/I18nModels';
import { DeviceKey } from '../model/DeviceKey';
import type { RoomDeletionPreview } from '../service/room/RoomService';
import { DeviceViewState, DeviceViewModel } from '../viewmodel/DeviceViewModel';
import { RoomViewState, RoomViewModel } from '../viewmodel/RoomViewModel';
import {
  AppDialog,
  AppTextField,
  EmptyState,
  ErrorState,
  LoadingSkeleton,
  PrimaryButton,
  SectionHeader
} from '../components/CommonControls';
import { UnassignedPool } from '../components/DeviceGrid';

@Component
export struct RoomManagePage {
  @Require params: AppRouteParams;
  @Require appContext: AppContext;
  @Require i18n: I18nService;
  @Require navigation: NavigationService;
  @Require vmFactory: PageVmFactoryPort;
  @Prop localeRevision: number = 0;
  @Prop motionEnabled: boolean = true;
  @State rooms: RoomViewState = RoomViewState.initial();
  @State devices: DeviceViewState = DeviceViewState.initial();
  @State newRoomName: string = '';
  @State editingRoomId: string = '';
  @State editingName: string = '';
  @State pendingDelete: RoomDeletionPreview | undefined = undefined;
  @State deletingRoomId: string = '';
  @State busy: boolean = false;

  private roomVm: RoomViewModel | undefined = undefined;
  private deviceVm: DeviceViewModel | undefined = undefined;
  private unsubscribeRooms: (() => void) | undefined = undefined;
  private unsubscribeDevices: (() => void) | undefined = undefined;

  aboutToAppear(): void {
    const roomVm = this.vmFactory.createRoomViewModel();
    const deviceVm = this.vmFactory.createDeviceViewModel();
    this.roomVm = roomVm;
    this.deviceVm = deviceVm;
    this.unsubscribeRooms = roomVm.subscribe((state: RoomViewState): void => {
      this.rooms = state;
    });
    this.unsubscribeDevices = deviceVm.subscribe((state: DeviceViewState): void => {
      this.devices = state;
    });
    const familyId = this.appContext.activeFamilyId;
    if (familyId !== undefined) {
      roomVm.initialize(familyId).catch((): void => undefined);
      deviceVm.initialize(familyId).catch((): void => undefined);
    }
    if (this.params.roomId !== undefined) {
      this.editingRoomId = this.params.roomId;
      this.editingName = '';
    }
  }

  aboutToDisappear(): void {
    if (this.unsubscribeRooms !== undefined) {
      this.unsubscribeRooms();
      this.unsubscribeRooms = undefined;
    }
    if (this.unsubscribeDevices !== undefined) {
      this.unsubscribeDevices();
      this.unsubscribeDevices = undefined;
    }
    if (this.roomVm !== undefined) {
      this.roomVm.dispose();
      this.roomVm = undefined;
    }
    if (this.deviceVm !== undefined) {
      this.deviceVm.dispose();
      this.deviceVm = undefined;
    }
  }

  private isAdmin(): boolean {
    const session = this.appContext.session;
    return session !== undefined && session.role === MemberRole.ADMIN;
  }

  private refresh(): void {
    if (this.roomVm !== undefined) {
      this.roomVm.refresh().catch((): void => undefined);
    }
    if (this.deviceVm !== undefined) {
      this.deviceVm.refresh().catch((): void => undefined);
    }
  }

  private createRoom(): void {
    const vm = this.roomVm;
    if (vm === undefined || this.newRoomName.trim().length === 0 || this.busy) {
      return;
    }
    this.busy = true;
    vm.createRoom(this.newRoomName.trim()).then((): void => {
      this.newRoomName = '';
      this.busy = false;
      this.refresh();
    }).catch((): void => {
      this.busy = false;
    });
  }

  private renameRoom(room: Room): void {
    const vm = this.roomVm;
    if (vm === undefined || this.editingRoomId.length === 0) {
      return;
    }
    const name = this.editingName.trim().length === 0 ? room.roomName :
      this.editingName.trim();
    this.busy = true;
    vm.renameRoom(this.editingRoomId, name).then((): void => {
      this.editingRoomId = '';
      this.editingName = '';
      this.busy = false;
    }).catch((): void => {
      this.busy = false;
    });
  }

  private move(room: Room, delta: number): void {
    const vm = this.roomVm;
    if (vm === undefined) {
      return;
    }
    const ordered: string[] = [];
    for (let index = 0; index < this.rooms.rooms.length; index++) {
      ordered.push(this.rooms.rooms[index].roomId);
    }
    const from = ordered.indexOf(room.roomId);
    const to = from + delta;
    if (from < 0 || to < 0 || to >= ordered.length) {
      return;
    }
    ordered.splice(from, 1);
    ordered.splice(to, 0, room.roomId);
    vm.reorderRooms(ordered).catch((): void => undefined);
  }

  private beginDelete(room: Room): void {
    const vm = this.roomVm;
    if (vm === undefined) {
      return;
    }
    this.deletingRoomId = room.roomId;
    vm.previewDelete(room.roomId).then((preview: RoomDeletionPreview): void => {
      this.pendingDelete = preview;
    }).catch((): void => {
      this.pendingDelete = undefined;
    });
  }

  private confirmDelete(): void {
    const vm = this.roomVm;
    const preview = this.pendingDelete;
    if (vm === undefined || preview === undefined || this.busy) {
      return;
    }
    this.busy = true;
    vm.confirmDelete(preview.room.roomId, preview.deviceCount).then((): void => {
      this.pendingDelete = undefined;
      this.deletingRoomId = '';
      this.busy = false;
      this.refresh();
    }).catch((): void => {
      this.busy = false;
      // Device count may have changed after the preview: re-read it and keep
      // the blocking dialog open (DES-B §15.2).
      vm.previewDelete(preview.room.roomId).then((next: RoomDeletionPreview): void => {
        this.pendingDelete = next;
      }).catch((): void => {
        this.pendingDelete = undefined;
      });
    });
  }

  private assignDevice(key: DeviceKey, roomId: string): void {
    const vm = this.roomVm;
    if (vm === undefined) {
      return;
    }
    vm.assignDevice(key, roomId).then((): void => {
      this.refresh();
    }).catch((): void => undefined);
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        Scroll() {
          Column({ space: AppSpacing.md }) {
            if (!this.isAdmin()) {
              Text(this.i18n.t('family.invite.admin_only'))
                .fontSize(AppTypography.label)
                .fontColor(AppColors.amber())
            }
            SectionHeader({
              i18n: this.i18n,
              localeRevision: this.localeRevision,
              titleKey: 'room.manage.title'
            })
            if (this.rooms.phase === 'LOADING' && this.rooms.rooms.length === 0) {
              LoadingSkeleton({ rows: 3, cardHeight: 64 })
            } else if (this.rooms.phase === 'ERROR') {
              ErrorState({
                i18n: this.i18n,
                localeRevision: this.localeRevision,
                messageKey: this.rooms.error === undefined
                  ? 'common.refresh_failed' : this.rooms.error.i18nKey,
                onRetry: (): void => {
                  this.refresh();
                }
              })
            } else {
              if (this.isAdmin()) {
                Row({ space: AppSpacing.xs }) {
                  TextInput({
                    placeholder: this.i18n.t('room.name.placeholder'),
                    text: this.newRoomName
                  })
                    .layoutWeight(1)
                    .height(44)
                    .fontSize(AppTypography.body)
                    .backgroundColor(AppColors.field())
                    .borderRadius(AppRadius.field)
                    .onChange((value: string): void => {
                      this.newRoomName = value;
                    })
                  Button(this.i18n.t('room.new'))
                    .height(44)
                    .fontSize(AppTypography.label)
                    .fontColor(Color.White)
                    .backgroundColor(AppColors.primary())
                    .borderRadius(AppRadius.button)
                    .enabled(!this.busy && this.newRoomName.trim().length > 0)
                    .onClick((): void => {
                      this.createRoom();
                    })
                }
                .width('100%')
              }

              if (this.rooms.rooms.length === 0) {
                EmptyState({
                  i18n: this.i18n,
                  localeRevision: this.localeRevision,
                  titleKey: 'rooms.empty.title',
                  messageKey: 'rooms.empty.message'
                })
              }

              ForEach(this.rooms.rooms.slice(), (room: Room): void => {
                Column({ space: AppSpacing.xs }) {
                  if (this.editingRoomId === room.roomId) {
                    Row({ space: AppSpacing.xs }) {
                      TextInput({
                        placeholder: room.roomName,
                        text: this.editingName
                      })
                        .layoutWeight(1)
                        .height(44)
                        .fontSize(AppTypography.body)
                        .backgroundColor(AppColors.field())
                        .borderRadius(AppRadius.field)
                        .onChange((value: string): void => {
                          this.editingName = value;
                        })
                      Button(this.i18n.t('common.save'))
                        .height(44)
                        .fontSize(AppTypography.label)
                        .fontColor(Color.White)
                        .backgroundColor(AppColors.primary())
                        .borderRadius(AppRadius.button)
                        .onClick((): void => {
                          this.renameRoom(room);
                        })
                      Button(this.i18n.t('common.cancel'))
                        .height(44)
                        .fontSize(AppTypography.label)
                        .fontColor(AppColors.inkSoft())
                        .backgroundColor(AppColors.field())
                        .borderRadius(AppRadius.button)
                        .onClick((): void => {
                          this.editingRoomId = '';
                          this.editingName = '';
                        })
                    }
                    .width('100%')
                  } else {
                    Row() {
                      Text(room.roomName)
                        .fontSize(AppTypography.body)
                        .fontColor(AppColors.ink())
                        .layoutWeight(1)
                      Text(this.i18n.t('device.count',
                        new I18nParams([new NameValue('count',
                          String(this.roomDeviceCount(room.roomId)))])))
                        .fontSize(AppTypography.caption)
                        .fontColor(AppColors.muted())
                    }
                    .width('100%')
                  }
                  if (this.isAdmin()) {
                    Row({ space: AppSpacing.xs }) {
                      Button(this.i18n.t('room.move.up'))
                        .height(44)
                        .fontSize(AppTypography.caption)
                        .fontColor(AppColors.inkSoft())
                        .backgroundColor(AppColors.field())
                        .borderRadius(AppRadius.chip)
                        .onClick((): void => {
                          this.move(room, -1);
                        })
                      Button(this.i18n.t('room.move.down'))
                        .height(44)
                        .fontSize(AppTypography.caption)
                        .fontColor(AppColors.inkSoft())
                        .backgroundColor(AppColors.field())
                        .borderRadius(AppRadius.chip)
                        .onClick((): void => {
                          this.move(room, 1);
                        })
                      Button(this.i18n.t('common.edit'))
                        .height(44)
                        .fontSize(AppTypography.caption)
                        .fontColor(AppColors.primary())
                        .backgroundColor(Color.Transparent)
                        .onClick((): void => {
                          this.editingRoomId = room.roomId;
                          this.editingName = room.roomName;
                        })
                      Button(this.i18n.t('common.delete'))
                        .height(44)
                        .fontSize(AppTypography.caption)
                        .fontColor(AppColors.red())
                        .backgroundColor(Color.Transparent)
                        .onClick((): void => {
                          this.beginDelete(room);
                        })
                    }
                  }
                }
                .width('100%')
                .padding(AppSpacing.sm)
                .backgroundColor(AppColors.surface())
                .borderRadius(AppRadius.card)
                .border({ width: 1, color: AppColors.edge() })
                .alignItems(HorizontalAlign.Start)
              }, (room: Room): string => room.roomId)

              UnassignedPool({
                i18n: this.i18n,
                localeRevision: this.localeRevision,
                records: this.rooms.unassignedRecords,
                rooms: this.rooms.rooms,
                onAssign: (key: DeviceKey, roomId: string): void => {
                  this.assignDevice(key, roomId);
                },
                onDelete: (key: DeviceKey): void => {
                  // Device deletion is not exposed by C-22/C-21 in this task;
                  // the pool keeps the device visible and disabled.
                },
                onRefresh: (): void => {
                  this.refresh();
                }
              })
              if (this.rooms.error !== undefined) {
                Text(this.i18n.t(this.rooms.error.i18nKey))
                  .fontSize(AppTypography.caption)
                  .fontColor(AppColors.red())
              }
            }
          }
          .width('100%')
          .padding(AppSpacing.md)
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)

        if (this.pendingDelete !== undefined) {
          AppDialog({
            i18n: this.i18n,
            localeRevision: this.localeRevision,
            titleKey: 'room.delete.title',
            messageKey: 'room.delete.warning',
            detail: this.pendingDelete.room.roomName + ' · ' +
              this.i18n.t('device.count', new I18nParams([new NameValue('count',
                String((this.pendingDelete as RoomDeletionPreview).deviceCount))])),
            confirmKey: 'common.delete',
            destructive: true,
            busy: this.busy,
            onConfirm: (): void => {
              this.confirmDelete();
            },
            onCancel: (): void => {
              this.pendingDelete = undefined;
              this.deletingRoomId = '';
              const vm = this.roomVm;
              if (vm !== undefined) {
                vm.cancelDelete();
              }
            }
          })
        }
      }
      .width('100%')
      .height('100%')
      .id('room-manage-locale-' + this.localeRevision)
    }
    .title(this.i18n.t('room.manage.title'))
    .backgroundColor(AppColors.background())
  }

  private roomDeviceCount(roomId: string): number {
    let count = 0;
    for (let index = 0; index < this.devices.records.length; index++) {
      if (this.devices.records[index].state.roomId === roomId) {
        count++;
      }
    }
    return count;
  }
}
