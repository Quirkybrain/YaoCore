/*
 * YaoCore C-25 HomePage.
 * Producer: agent:implementation-engineer | Task: T-18 / wp-073-ui-pages
 * Contract: DES-B §14.1.1/§14.1.2, §14.3; FR-HOME-001..004; UIUX §3/§4.2
 *
 * Home derives everything from the local SSOT. The quick grid uses
 * DeviceViewModel for acknowledged control state; a failed refresh keeps the
 * previous records visible (HomeViewModel contract).
 */
import type { I18nService } from '../service/i18n/I18nService';
import { AppContext } from '../app/AppContext';
import { AppRoute, AppRouteParams, NavigationService } from '../app/NavigationService';
import type { PageVmFactoryPort } from '../app/PageVmFactory';
import { DeviceType } from '../common/constants/DeviceConstants';
import { MemberRole } from '../model/FamilyModels';
import {
  AppColors,
  AppSpacing,
  AppTypography
} from '../common/theme/AppTheme';
import { DeviceKey } from '../model/DeviceKey';
import type { DeviceRecord } from '../model/DeviceRecord';
import {
  CloudLinkState,
  DeviceFilter,
  GatewayStatus
} from '../viewmodel/core/ViewModelCore';
import { DeviceViewState, DeviceViewModel } from '../viewmodel/DeviceViewModel';
import { HomeViewState, HomeViewModel } from '../viewmodel/HomeViewModel';
import { EmptyState, ErrorState, LoadingSkeleton, PrimaryButton } from '../components/CommonControls';
import { DeviceGrid } from '../components/DeviceGrid';
import { RoomChipBar } from '../components/RoomChipBar';
import { EnvironmentPanel, StatusBanner } from '../components/StatusPanels';

@Component
export struct HomePage {
  @Require appContext: AppContext;
  @Require i18n: I18nService;
  @Require navigation: NavigationService;
  @Require vmFactory: PageVmFactoryPort;
  @Prop localeRevision: number = 0;
  @Prop motionEnabled: boolean = true;
  @State home: HomeViewState = HomeViewState.initial();
  @State devices: DeviceViewState = DeviceViewState.initial();
  @State refreshing: boolean = false;
  @State selectedFilter: DeviceFilter = DeviceFilter.all();

  private homeVm: HomeViewModel | undefined = undefined;
  private deviceVm: DeviceViewModel | undefined = undefined;
  private unsubscribeHome: (() => void) | undefined = undefined;
  private unsubscribeDevices: (() => void) | undefined = undefined;
  private unsubscribeFamily: (() => void) | undefined = undefined;

  aboutToAppear(): void {
    const homeVm = this.vmFactory.createHomeViewModel();
    const deviceVm = this.vmFactory.createDeviceViewModel();
    this.homeVm = homeVm;
    this.deviceVm = deviceVm;
    this.unsubscribeHome = homeVm.subscribe((state: HomeViewState): void => {
      this.home = state;
    });
    this.unsubscribeDevices = deviceVm.subscribe((state: DeviceViewState): void => {
      this.devices = state;
    });
    this.unsubscribeFamily = this.appContext.subscribeActiveFamily((): void => {
      this.initialize();
    });
    this.initialize();
  }

  aboutToDisappear(): void {
    if (this.unsubscribeHome !== undefined) {
      this.unsubscribeHome();
      this.unsubscribeHome = undefined;
    }
    if (this.unsubscribeDevices !== undefined) {
      this.unsubscribeDevices();
      this.unsubscribeDevices = undefined;
    }
    if (this.unsubscribeFamily !== undefined) {
      this.unsubscribeFamily();
      this.unsubscribeFamily = undefined;
    }
    if (this.homeVm !== undefined) {
      this.homeVm.dispose();
      this.homeVm = undefined;
    }
    if (this.deviceVm !== undefined) {
      this.deviceVm.dispose();
      this.deviceVm = undefined;
    }
  }

  private initialize(): void {
    const familyId = this.appContext.activeFamilyId;
    if (familyId !== undefined && this.deviceVm !== undefined) {
      this.deviceVm.initialize(familyId).then((): void => {
        const current = this.deviceVm;
        if (current !== undefined) {
          current.setFilter(this.selectedFilter);
        }
      }).catch((): void => undefined);
    }
    if (this.homeVm !== undefined) {
      this.homeVm.initialize().then((): void => {
        this.refreshing = false;
      }).catch((): void => {
        this.refreshing = false;
      });
    }
  }

  private refresh(): void {
    if (this.refreshing) {
      return;
    }
    this.refreshing = true;
    const familyId = this.appContext.activeFamilyId;
    if (familyId !== undefined && this.deviceVm !== undefined) {
      this.deviceVm.initialize(familyId).catch((): void => undefined);
    }
    if (this.homeVm !== undefined) {
      this.homeVm.refresh().then((): void => {
        this.refreshing = false;
      }).catch((): void => {
        this.refreshing = false;
      });
    } else {
      this.refreshing = false;
    }
  }

  private gateway(): GatewayStatus | undefined {
    return this.home.gatewayStatuses.length > 0 ? this.home.gatewayStatuses[0] : undefined;
  }

  private cloudState(): CloudLinkState {
    const gateway = this.gateway();
    return gateway === undefined ? CloudLinkState.UNKNOWN : gateway.cloud;
  }

  private selectFilter(filter: DeviceFilter): void {
    this.selectedFilter = filter;
    if (this.homeVm !== undefined) {
      this.homeVm.setRoomFilter(filter);
    }
    if (this.deviceVm !== undefined) {
      this.deviceVm.setFilter(filter);
    }
  }

  private openRooms(roomId: string): void {
    this.navigation.openRoomsWithHighlight(roomId);
  }

  /** F-03: gateway binding is ADMIN-only; MEMBER/GUEST never see the entry. */
  private isAdmin(): boolean {
    const session = this.appContext.session;
    return session !== undefined && session.role === MemberRole.ADMIN;
  }

  private openDevice(record: DeviceRecord): void {
    this.navigation.push(AppRoute.DEVICE_CONTROL, new AppRouteParams({
      gatewayId: record.state.key.gatewayId,
      deviceId: record.state.key.deviceId,
      roomId: record.state.roomId
    }));
  }

  private openDeviceKey(key: DeviceKey): void {
    const record = this.findVisibleRecord(key);
    if (record !== undefined) {
      this.openDevice(record);
    }
  }

  private findVisibleRecord(key: DeviceKey): DeviceRecord | undefined {
    for (let index = 0; index < this.devices.records.length; index++) {
      if (this.devices.records[index].state.key.gatewayId === key.gatewayId &&
        this.devices.records[index].state.key.deviceId === key.deviceId) {
        return this.devices.records[index];
      }
    }
    return undefined;
  }

  /** §14.1.2: unassigned devices belong to the Rooms pool, not Home. */
  private homeRecords(): ReadonlyArray<DeviceRecord> {
    const result: DeviceRecord[] = [];
    for (let index = 0; index < this.devices.records.length; index++) {
      const record = this.devices.records[index];
      if (!record.state.isUnassigned && !record.state.isDismissed) {
        result.push(record);
      }
    }
    return result;
  }

  private filterHomeRecords(records: ReadonlyArray<DeviceRecord>): ReadonlyArray<DeviceRecord> {
    const result: DeviceRecord[] = [];
    for (let index = 0; index < records.length; index++) {
      if (!records[index].state.isUnassigned && !records[index].state.isDismissed) {
        result.push(records[index]);
      }
    }
    return result;
  }

  private quickToggle(key: DeviceKey): void {
    const record = this.findVisibleRecord(key);
    if (record === undefined) {
      return;
    }
    const type = record.state.snapshot.deviceType;
    if (type === DeviceType.LIGHT || type === DeviceType.AC) {
      const vm = this.deviceVm;
      if (vm !== undefined) {
        vm.togglePower(key).catch((): void => undefined);
      }
      return;
    }
    this.openDevice(record);
  }

  build() {
    Scroll() {
      Column({ space: AppSpacing.md }) {
        StatusBanner({
          i18n: this.i18n,
          localeRevision: this.localeRevision,
          familyName: this.home.activeFamily === undefined
            ? this.appContext.activeFamilyName : this.home.activeFamily.familyName,
          gateway: this.gateway(),
          cloud: this.cloudState(),
          isRefreshing: this.refreshing,
          onFamilyClick: (): void => {
            this.navigation.push(AppRoute.FAMILY,
              new AppRouteParams({ section: 'FAMILY' }));
          },
          onGatewayClick: (): void => {
            this.navigation.push(AppRoute.SETTINGS);
          },
          onRefresh: (): void => {
            this.refresh();
          }
        })

        if (this.home.phase === 'LOADING' && this.home.records.length === 0) {
          LoadingSkeleton({ rows: 3, cardHeight: 96 })
        } else if (this.home.phase === 'ERROR') {
          ErrorState({
            i18n: this.i18n,
            localeRevision: this.localeRevision,
            titleKey: 'common.error',
            messageKey: this.home.error === undefined
              ? 'common.refresh_failed' : this.home.error.i18nKey,
            onRetry: (): void => {
              this.refresh();
            }
          })
        } else {
          if (this.home.activeFamily === undefined) {
            EmptyState({
              i18n: this.i18n,
              localeRevision: this.localeRevision,
              titleKey: 'home.no_family.title',
              messageKey: 'home.no_family.message'
            })
          } else {
            EnvironmentPanel({
              i18n: this.i18n,
              localeRevision: this.localeRevision,
              environment: this.home.environment
            })
            RoomChipBar({
              i18n: this.i18n,
              localeRevision: this.localeRevision,
              rooms: this.home.rooms,
              selectedFilter: this.selectedFilter,
              onSelect: (filter: DeviceFilter): void => {
                this.selectFilter(filter);
              }
            })
            if (this.selectedFilter.roomId !== undefined) {
              PrimaryButton({
                i18n: this.i18n,
                localeRevision: this.localeRevision,
                labelKey: 'home.open_room',
                isEnabled: true,
                fullWidth: false,
                onTap: (): void => {
                  this.openRooms(this.selectedFilter.roomId as string);
                }
              })
            }
            if (this.homeRecords().length === 0) {
              EmptyState({
                i18n: this.i18n,
                localeRevision: this.localeRevision,
                titleKey: 'home.empty.title',
                messageKey: 'home.empty.message'
              })
            } else {
              DeviceGrid({
                i18n: this.i18n,
                localeRevision: this.localeRevision,
                records: this.homeRecords().length > 0
                  ? this.homeRecords() : this.filterHomeRecords(this.home.records),
                controls: this.devices.controls,
                rooms: this.home.rooms,
                motionEnabled: this.motionEnabled,
                onOpen: (key: DeviceKey): void => {
                  this.openDeviceKey(key);
                },
                onQuickToggle: (key: DeviceKey): void => {
                  this.quickToggle(key);
                }
              })
            }
            if (this.isAdmin()) {
              Row({ space: AppSpacing.sm }) {
                PrimaryButton({
                  i18n: this.i18n,
                  localeRevision: this.localeRevision,
                  labelKey: 'home.add_gateway',
                  fullWidth: true,
                  onTap: (): void => {
                    this.navigation.push(AppRoute.PROVISIONING);
                  }
                })
              }
              .width('100%')
            }
            Text(this.i18n.t('home.grid.hint'))
              .fontSize(AppTypography.caption)
              .fontColor(AppColors.muted())
          }
        }
      }
      .width('100%')
      .padding(AppSpacing.md)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .id('home-locale-' + this.localeRevision)
  }
}
