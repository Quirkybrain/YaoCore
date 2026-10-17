/*
 * YaoCore C-27 ProfilePage (Tab 3).
 * Producer: agent:implementation-engineer | Task: T-18 / wp-073-ui-pages
 * Contract: DES-B §16.1.4, §16.3(7); FR-SET-002; D-010
 *
 * Local profile card only: family, role, GUEST expiry, family/settings/about
 * entries and lock. No cross-device presence is shown.
 */
import type { I18nService } from '../service/i18n/I18nService';
import {
  AppContext,
  SessionGateProfile
} from '../app/AppContext';
import { AppRoute, NavigationService } from '../app/NavigationService';
import type { PageVmFactoryPort } from '../app/PageVmFactory';
import {
  AppColors,
  AppRadius,
  AppSpacing,
  AppTypography
} from '../common/theme/AppTheme';
import { MemberRole } from '../model/FamilyModels';
import type { FamilyMemberView } from '../service/family/FamilyModels';
import { FamilyViewState, FamilyViewModel } from '../viewmodel/FamilyViewModel';
import { LoadingSkeleton, PrimaryButton, SectionHeader } from '../components/CommonControls';
import { UiMapping } from '../components/support/UiMapping';

@Component
export struct ProfilePage {
  @Require appContext: AppContext;
  @Require i18n: I18nService;
  @Require navigation: NavigationService;
  @Require vmFactory: PageVmFactoryPort;
  @Prop localeRevision: number = 0;
  @Prop motionEnabled: boolean = true;
  @State family: FamilyViewState = FamilyViewState.initial();
  @State profileName: string = '';
  @State locking: boolean = false;

  private familyVm: FamilyViewModel | undefined = undefined;
  private unsubscribeFamily: (() => void) | undefined = undefined;

  aboutToAppear(): void {
    const vm = this.vmFactory.createFamilyViewModel();
    this.familyVm = vm;
    this.unsubscribeFamily = vm.subscribe((state: FamilyViewState): void => {
      this.family = state;
    });
    vm.initialize().catch((): void => undefined);
    this.loadProfileName();
  }

  aboutToDisappear(): void {
    if (this.unsubscribeFamily !== undefined) {
      this.unsubscribeFamily();
      this.unsubscribeFamily = undefined;
    }
    if (this.familyVm !== undefined) {
      this.familyVm.dispose();
      this.familyVm = undefined;
    }
  }

  private loadProfileName(): void {
    const session = this.appContext.session;
    if (session === undefined) {
      return;
    }
    this.appContext.listProfiles().then((profiles: ReadonlyArray<SessionGateProfile>): void => {
      for (let index = 0; index < profiles.length; index++) {
        if (profiles[index].profileId === session.profileId) {
          this.profileName = profiles[index].displayName;
          return;
        }
      }
    }).catch((): void => undefined);
  }

  private member(): FamilyMemberView | undefined {
    const session = this.appContext.session;
    if (session === undefined) {
      return undefined;
    }
    for (let index = 0; index < this.family.members.length; index++) {
      if (this.family.members[index].member.memberId === session.memberId) {
        return this.family.members[index];
      }
    }
    return undefined;
  }

  private displayName(): string {
    const member = this.member();
    if (member !== undefined) {
      return member.member.displayName;
    }
    return this.profileName.length > 0 ? this.profileName : this.i18n.t('profile.unknown');
  }

  private role(): MemberRole | undefined {
    const session = this.appContext.session;
    if (session !== undefined) {
      return session.role;
    }
    const capabilities = this.family.capabilities;
    return capabilities === undefined ? undefined : capabilities.role;
  }

  private isAdmin(): boolean {
    const role = this.role();
    return role !== undefined && role === MemberRole.ADMIN;
  }

  private guestExpiryText(): string {
    const member = this.member();
    if (member === undefined || member.member.expiresAt === undefined) {
      return this.i18n.t('common.unknown');
    }
    return member.member.expiresAt;
  }

  private lock(): void {
    if (this.locking) {
      return;
    }
    this.locking = true;
    this.appContext.lock().then((): void => {
      this.locking = false;
    }).catch((): void => {
      this.locking = false;
    });
  }

  build() {
    Scroll() {
      Column({ space: AppSpacing.md }) {
        Column({ space: AppSpacing.sm }) {
          Text(this.displayName())
            .fontSize(AppTypography.title)
            .fontWeight(AppTypography.weightBold)
            .fontColor(AppColors.ink())
          Row({ space: AppSpacing.xs }) {
            if (this.role() !== undefined) {
              Text(this.i18n.t(UiMapping.roleKey(this.role() as MemberRole)))
                .fontSize(AppTypography.label)
                .fontColor(AppColors.primary())
            }
            if (this.family.activeFamily !== undefined) {
              Text('·')
                .fontSize(AppTypography.caption)
                .fontColor(AppColors.mutedLight())
              Text(this.family.activeFamily.familyName)
                .fontSize(AppTypography.label)
                .fontColor(AppColors.muted())
            }
          }
          if (this.role() === MemberRole.GUEST) {
            Text(this.i18n.t('profile.guest.expires') + ' ' + this.guestExpiryText())
              .fontSize(AppTypography.caption)
              .fontColor(AppColors.amber())
          }
          Text(this.i18n.t('profile.local_only'))
            .fontSize(AppTypography.caption)
            .fontColor(AppColors.muted())
        }
        .width('100%')
        .padding(AppSpacing.lg)
        .backgroundColor(AppColors.surface())
        .borderRadius(AppRadius.card)
        .border({ width: 1, color: AppColors.edge() })
        .alignItems(HorizontalAlign.Start)

        if (this.family.phase === 'LOADING' && this.family.members.length === 0) {
          LoadingSkeleton({ rows: 2, cardHeight: 56 })
        }

        SectionHeader({
          i18n: this.i18n,
          localeRevision: this.localeRevision,
          titleKey: 'profile.entries'
        })

        if (this.isAdmin()) {
          this.entry('profile.manage_family', (): void => {
            this.navigation.push(AppRoute.FAMILY);
          })
        } else {
          this.entry('profile.family', (): void => {
            this.navigation.push(AppRoute.FAMILY);
          })
        }
        this.entry('profile.settings', (): void => {
          this.navigation.push(AppRoute.SETTINGS);
        })
        this.entry('profile.about', (): void => {
          this.navigation.push(AppRoute.ABOUT);
        })
        this.entry('profile.provisioning', (): void => {
          this.navigation.push(AppRoute.PROVISIONING);
        })

        PrimaryButton({
          i18n: this.i18n,
          localeRevision: this.localeRevision,
          labelKey: 'profile.lock',
          loading: this.locking,
          destructive: true,
          onTap: (): void => {
            this.lock();
          }
        })
      }
      .width('100%')
      .padding(AppSpacing.md)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .id('profile-locale-' + this.localeRevision)
  }

  @Builder
  entry(labelKey: string, onTap: () => void) {
    Row({ space: AppSpacing.sm }) {
      Text(this.i18n.t(labelKey))
        .fontSize(AppTypography.body)
        .fontColor(AppColors.ink())
        .layoutWeight(1)
      Text('›')
        .fontSize(AppTypography.title)
        .fontColor(AppColors.mutedLight())
    }
    .width('100%')
    .height(52)
    .padding({ left: AppSpacing.md, right: AppSpacing.md })
    .backgroundColor(AppColors.surface())
    .borderRadius(AppRadius.button)
    .border({ width: 1, color: AppColors.edge() })
    .onClick((): void => {
      onTap();
    })
  }
}
