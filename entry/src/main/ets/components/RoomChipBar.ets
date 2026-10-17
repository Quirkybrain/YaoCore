/*
 * YaoCore C-24 room filter chips.
 * Producer: agent:implementation-engineer | Task: T-18 / wp-073-ui-pages
 * Contract: DES-B §13.1.3, §14.1.2; FR-HOME-002
 */
import type { I18nService } from '../service/i18n/I18nService';
import type { Room } from '../model/FamilyModels';
import { DeviceFilter, DeviceFilterKind } from '../viewmodel/core/ViewModelCore';
import {
  AppColors,
  AppRadius,
  AppSpacing,
  AppTypography
} from '../common/theme/AppTheme';

@Component
export struct RoomChipBar {
  @Require i18n: I18nService;
  @Prop localeRevision: number = 0;
  @Prop rooms: ReadonlyArray<Room> = [];
  @Prop selectedFilter: DeviceFilter = DeviceFilter.all();
  onSelect: (filter: DeviceFilter) => void = (filter: DeviceFilter): void => {};

  private isSelected(kind: DeviceFilterKind, roomId?: string): boolean {
    if (this.selectedFilter.kind !== kind) {
      return false;
    }
    return roomId === undefined || this.selectedFilter.roomId === roomId;
  }

  build() {
    Scroll() {
      Row({ space: AppSpacing.xs }) {
        Button(this.i18n.t('home.room.all'))
          .height(44)
          .fontSize(AppTypography.label)
          .fontColor(this.isSelected(DeviceFilterKind.ALL, undefined)
            ? Color.White : AppColors.inkSoft())
          .backgroundColor(this.isSelected(DeviceFilterKind.ALL, undefined)
            ? AppColors.primary() : AppColors.surface())
          .borderRadius(AppRadius.chip)
          .accessibilityText(this.i18n.t('home.room.all'))
          .onClick((): void => {
            this.onSelect(DeviceFilter.all());
          })
        ForEach(this.rooms.slice(), (room: Room): void => {
          Button(room.roomName)
            .height(44)
            .fontSize(AppTypography.label)
            .fontColor(this.isSelected(DeviceFilterKind.ROOM, room.roomId)
              ? Color.White : AppColors.inkSoft())
            .backgroundColor(this.isSelected(DeviceFilterKind.ROOM, room.roomId)
              ? AppColors.primary() : AppColors.surface())
            .borderRadius(AppRadius.chip)
            .constraintSize({ maxWidth: 180 })
            .accessibilityText(room.roomName)
            .onClick((): void => {
              this.onSelect(DeviceFilter.room(room.roomId));
            })
        }, (room: Room): string => room.roomId)
      }
      .padding({ bottom: AppSpacing.xxs })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
  }
}
