/*
 * YaoCore C-25 RoomsPage.
 * Producer: agent:implementation-engineer | Task: T-18 / wp-073-ui-pages
 * Contract: DES-B §14.1.1/§14.1.3, §14.3; FR-ROOM-001..006; ADR-004 §2
 *
 * Rooms shows the room grid, the selected room's devices and the safe
 * unassigned pool. Device state is rendered from DeviceRecords joined with
 * Room.roomName (never snapshot.roomNameHint).
 */
import type { I18nService } from '../service/i18n/I18nService';
import { AppContext } from '../app/AppContext';
import { AppRoute, AppRouteParams, NavigationService } from '../app/NavigationService';
import type { PageVmFactoryPort } from '../app/PageVmFactory';
import {
  AppColors,
  AppSpacing,
  AppTypography
} from '../common/theme/AppTheme';
import type { Room } from '../model/FamilyModels';
import { DeviceKey } from '../model/DeviceKey';
import type { DeviceRecord } from '../repository/DomainModels';
import { DeviceFilter, CloudLinkState } from '../viewmodel/core/ViewModelCore';
import { DeviceViewState, DeviceViewModel } from '../viewmodel/DeviceViewModel';
import { RoomViewState, RoomViewModel } from '../viewmodel/RoomViewModel';
import {
  EmptyState,
  ErrorState,
  LoadingSkeleton,
  PrimaryButton,
  SectionHeader
} from '../components/CommonControls';
import { RoomCard } from '../components/DeviceCards';
import { DeviceGrid, UnassignedPool } from '../components/DeviceGrid';
import { StatusBanner } from '../components/StatusPanels';
import { UiMapping } from '../components/support/UiMapping';

@Component
export struct RoomsPage {
  @Require appContext: AppContext;
  @Require i18n: I18nService;
  @Require navigation: NavigationService;
  @Require vmFactory: PageVmFactoryPort;
  @Prop localeRevision: number = 0;
  @Prop motionEnabled: boolean = true;
  @Prop @Watch('onHighlightChanged') highlightRoomId: string = '';
  @State rooms: RoomViewState = RoomViewState.initial();
  @State devices: DeviceViewState = DeviceViewState.initial();
  @State selectedRoomId: string = '';
  @State refreshing: boolean = false;

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
    if (this.highlightRoomId.length > 0) {
      this.selectedRoomId = this.highlightRoomId;
    }
    this.initialize();
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

  private onHighlightChanged(): void {
    if (this.highlightRoomId.length > 0) {
      this.selectedRoomId = this.highlightRoomId;
    }
  }

  private initialize(): void {
    const familyId = this.appContext.activeFamilyId;
    if (familyId === undefined) {
      return;
    }
    if (this.roomVm !== undefined) {
      this.roomVm.initialize(familyId).catch((): void => undefined);
    }
    if (this.deviceVm !== undefined) {
      this.deviceVm.initialize(familyId).then((): void => {
        const vm = this.deviceVm;
        if (vm !== undefined) {
          vm.setFilter(DeviceFilter.all());
        }
      }).catch((): void => undefined);
    }
  }

  private refresh(): void {
    if (this.refreshing) {
      return;
    }
    this.refreshing = true;
    if (this.roomVm !== undefined) {
      this.roomVm.refresh().catch((): void => undefined);
    }
    if (this.deviceVm !== undefined) {
      this.deviceVm.refresh().then((): void => {
        this.refreshing = false;
      }).catch((): void => {
        this.refreshing = false;
      });
    } else {
      this.refreshing = false;
    }
  }

  private roomDevices(): ReadonlyArray<DeviceRecord> {
    if (this.selectedRoomId.length === 0) {
      return [];
    }
    const filter = DeviceFilter.room(this.selectedRoomId);
    const result: DeviceRecord[] = [];
    for (let index = 0; index < this.devices.records.length; index++) {
      if (UiMapping.filterMatches(filter, this.devices.records[index])) {
        result.push(this.devices.records[index]);
      }
    }
    return result;
  }

  private openDevice(record: DeviceRecord): void {
    this.navigation.push(AppRoute.DEVICE_CONTROL, new AppRouteParams({
      gatewayId: record.state.key.gatewayId,
      deviceId: record.state.key.deviceId,
      roomId: record.state.roomId
    }));
  }

  private openDeviceKey(key: DeviceKey): void {
    for (let index = 0; index < this.devices.records.length; index++) {
      const record = this.devices.records[index];
      if (record.state.key.gatewayId === key.gatewayId &&
        record.state.key.deviceId === key.deviceId) {
        this.openDevice(record);
        return;
      }
    }
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

  private openRoomManage(roomId: string): void {
    this.navigation.push(AppRoute.ROOM_MANAGE, new AppRouteParams({ roomId: roomId }));
  }

  build() {
    Scroll() {
      Column({ space: AppSpacing.md }) {
        StatusBanner({
          i18n: this.i18n,
          localeRevision: this.localeRevision,
          familyName: this.appContext.activeFamilyName,
          gateway: undefined,
          cloud: CloudLinkState.UNKNOWN,
          isRefreshing: this.refreshing,
          onFamilyClick: (): void => {
            this.navigation.push(AppRoute.FAMILY);
          },
          onGatewayClick: (): void => {
            this.navigation.push(AppRoute.SETTINGS);
          },
          onRefresh: (): void => {
            this.refresh();
          }
        })

        if (this.rooms.phase === 'LOADING' && this.rooms.rooms.length === 0) {
          LoadingSkeleton({ rows: 3, cardHeight: 96 })
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
          SectionHeader({
            i18n: this.i18n,
            localeRevision: this.localeRevision,
            titleKey: 'rooms.title',
            action: undefined
          })
          if (this.rooms.rooms.length === 0) {
            EmptyState({
              i18n: this.i18n,
              localeRevision: this.localeRevision,
              titleKey: 'rooms.empty.title',
              messageKey: 'rooms.empty.message'
            })
          } else {
            Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap,
              justifyContent: FlexAlign.SpaceBetween }) {
              ForEach(this.rooms.rooms.slice(), (room: Room): void => {
                Column() {
                  RoomCard({
                    i18n: this.i18n,
                    localeRevision: this.localeRevision,
                    room: room,
                    deviceCount: UiMapping.roomDeviceCount(this.devices.records, room.roomId),
                    unassignedCount: this.rooms.unassignedRecords.length,
                    onOpen: (): void => {
                      this.selectedRoomId = room.roomId;
                    },
                    onRename: (): void => {
                      this.openRoomManage(room.roomId);
                    },
                    onDelete: (): void => {
                      this.openRoomManage(room.roomId);
                    }
                  })
                }
                .width('48%')
                .margin({ bottom: AppSpacing.sm })
              }, (room: Room): string => room.roomId)
            }
            .width('100%')
          }

          Row({ space: AppSpacing.sm }) {
            PrimaryButton({
              i18n: this.i18n,
              localeRevision: this.localeRevision,
              labelKey: 'rooms.add_room',
              fullWidth: true,
              onTap: (): void => {
                this.navigation.push(AppRoute.ROOM_MANAGE);
              }
            })
          }
          .width('100%')

          if (this.selectedRoomId.length > 0) {
            SectionHeader({
              i18n: this.i18n,
              localeRevision: this.localeRevision,
              titleKey: 'rooms.selected.title',
              action: undefined
            })
            Text(UiMapping.roomNameById(this.selectedRoomId, this.rooms.rooms))
              .fontSize(AppTypography.body)
              .fontColor(AppColors.inkSoft())
            if (this.roomDevices().length === 0) {
              EmptyState({
                i18n: this.i18n,
                localeRevision: this.localeRevision,
                titleKey: 'rooms.devices.empty.title',
                messageKey: 'rooms.devices.empty.message'
              })
            } else {
              DeviceGrid({
                i18n: this.i18n,
                localeRevision: this.localeRevision,
                records: this.roomDevices(),
                controls: this.devices.controls,
                rooms: this.rooms.rooms,
                motionEnabled: this.motionEnabled,
                onOpen: (key: DeviceKey): void => {
                  this.openDeviceKey(key);
                },
                onQuickToggle: (key: DeviceKey): void => {
                  const vm = this.deviceVm;
                  if (vm !== undefined) {
                    vm.togglePower(key).catch((): void => undefined);
                  }
                }
              })
            }
          }

          UnassignedPool({
            i18n: this.i18n,
            localeRevision: this.localeRevision,
            records: this.rooms.unassignedRecords,
            rooms: this.rooms.rooms,
            onAssign: (key: DeviceKey, roomId: string): void => {
              this.assignDevice(key, roomId);
            },
            onDelete: (key: DeviceKey): void => {
              this.openDeviceKey(key);
            },
            onRefresh: (): void => {
              this.refresh();
            }
          })

          if (this.rooms.pendingAction) {
            LoadingSkeleton({ rows: 1, cardHeight: 48 })
          }
        }
      }
      .width('100%')
      .padding(AppSpacing.md)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .id('rooms-locale-' + this.localeRevision)
  }
}
