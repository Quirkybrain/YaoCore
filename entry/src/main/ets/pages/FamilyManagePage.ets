/*
 * YaoCore C-26 FamilyManagePage.
 * Producer: agent:implementation-engineer | Task: T-18 / wp-073-ui-pages
 * Contract: DES-B §15.1.2, §15.2/§15.3; FR-FAM-001..004; ADR-003; D-009/D-010/D-013
 *
 * Default invitation flow is D-009 KEY_WRAP: the joining member first shows
 * YCR1, the admin pastes it and returns a YCI1 container. CODE_KEK is an
 * explicit weak mode with a six-digit code and a security warning. Members
 * never display presence, only contact-sync metadata (D-010).
 */
import type { I18nService } from '../service/i18n/I18nService';
import { AppContext } from '../app/AppContext';
import type { AppRouteParams } from '../app/NavigationService';
import type { NavigationService } from '../app/NavigationService';
import type { PageVmFactoryPort } from '../app/PageVmFactory';
import {
  AppColors,
  AppRadius,
  AppSpacing,
  AppTypography
} from '../common/theme/AppTheme';
import { DateTimeUtil } from '../common/utils/DateTimeUtil';
import { NameValue } from '../common/types/NameValue';
import { I18nParams } from '../service/i18n/I18nModels';
import {
  InviteMode,
  MemberRole
} from '../model/FamilyModels';
import type { Family, Room } from '../model/FamilyModels';
import { CreateInvitationInput, FamilyJoinPhase } from '../service/family/FamilyModels';
import type {
  FamilyMemberView,
  InvitationView,
  InviteCreation
} from '../service/family/FamilyModels';
import {
  FamilySection,
  FamilyViewState,
  FamilyViewModel
} from '../viewmodel/FamilyViewModel';
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
import { UiMapping } from '../components/support/UiMapping';

const INVITE_TTL_MS: number = 86400000;
const GUEST_EXTEND_MS: number = 30 * 86400000;

@Component
export struct FamilyManagePage {
  @Require params: AppRouteParams;
  @Require appContext: AppContext;
  @Require i18n: I18nService;
  @Require navigation: NavigationService;
  @Require vmFactory: PageVmFactoryPort;
  @Prop localeRevision: number = 0;
  @Prop motionEnabled: boolean = true;
  @State family: FamilyViewState = FamilyViewState.initial();
  @State rooms: RoomViewState = RoomViewState.initial();
  @State section: FamilySection = FamilySection.MEMBERS;
  @State displayName: string = '';
  @State joinRequestText: string = '';
  @State invitationText: string = '';
  @State invitationCode: string = '';
  @State profilePassword: string = '';
  @State adminJoinRequest: string = '';
  @State inviteRole: MemberRole = MemberRole.MEMBER;
  @State selectedRoomIds: string[] = [];
  @State createdInviteText: string = '';
  @State createdInviteCode: string = '';
  @State createdInviteWeak: boolean = false;
  @State receiptInviteId: string = '';
  @State receiptText: string = '';
  @State dialogKind: string = '';
  @State dialogMemberId: string = '';
  @State dialogInviteId: string = '';
  @State dialogRoomId: string = '';
  @State busy: boolean = false;

  private familyVm: FamilyViewModel | undefined = undefined;
  private roomVm: RoomViewModel | undefined = undefined;
  private unsubscribeFamily: (() => void) | undefined = undefined;
  private unsubscribeRooms: (() => void) | undefined = undefined;

  aboutToAppear(): void {
    const familyVm = this.vmFactory.createFamilyViewModel();
    const roomVm = this.vmFactory.createRoomViewModel();
    this.familyVm = familyVm;
    this.roomVm = roomVm;
    this.unsubscribeFamily = familyVm.subscribe((state: FamilyViewState): void => {
      this.family = state;
      this.section = state.section;
      this.busy = state.pendingAction;
      const joinText = state.join === undefined ? undefined : state.join.joinRequestText;
      if (joinText !== undefined && this.joinRequestText.length === 0) {
        this.joinRequestText = joinText;
      }
    });
    this.unsubscribeRooms = roomVm.subscribe((state: RoomViewState): void => {
      this.rooms = state;
    });
    const requested = this.params.section;
    if (requested === 'INVITES') {
      this.section = FamilySection.INVITES;
      familyVm.setSection(FamilySection.INVITES);
    } else if (requested === 'JOIN') {
      this.section = FamilySection.JOIN;
      familyVm.setSection(FamilySection.JOIN);
    } else if (requested === 'FAMILY') {
      this.section = FamilySection.FAMILY;
      familyVm.setSection(FamilySection.FAMILY);
    }
    familyVm.initialize().catch((): void => undefined);
    const familyId = this.appContext.activeFamilyId;
    if (familyId !== undefined) {
      roomVm.initialize(familyId).catch((): void => undefined);
    }
  }

  aboutToDisappear(): void {
    if (this.unsubscribeFamily !== undefined) {
      this.unsubscribeFamily();
      this.unsubscribeFamily = undefined;
    }
    if (this.unsubscribeRooms !== undefined) {
      this.unsubscribeRooms();
      this.unsubscribeRooms = undefined;
    }
    if (this.familyVm !== undefined) {
      this.familyVm.dispose();
      this.familyVm = undefined;
    }
    if (this.roomVm !== undefined) {
      this.roomVm.dispose();
      this.roomVm = undefined;
    }
  }

  private isAdmin(): boolean {
    return this.family.capabilities !== undefined &&
      this.family.capabilities.canManageFamily;
  }

  private canInvite(): boolean {
    return this.family.capabilities !== undefined && this.family.capabilities.canInvite;
  }

  private activeFamily(): Family | undefined {
    return this.family.activeFamily;
  }

  private selectSection(section: FamilySection): void {
    this.section = section;
    if (this.familyVm !== undefined) {
      this.familyVm.setSection(section);
    }
  }

  private toggleRoom(roomId: string): void {
    const next: string[] = [];
    let present = false;
    for (let index = 0; index < this.selectedRoomIds.length; index++) {
      if (this.selectedRoomIds[index] === roomId) {
        present = true;
      } else {
        next.push(this.selectedRoomIds[index]);
      }
    }
    if (!present) {
      next.push(roomId);
    }
    this.selectedRoomIds = next;
  }

  private createFromRequest(): void {
    const vm = this.familyVm;
    const family = this.activeFamily();
    if (vm === undefined || family === undefined || this.busy) {
      return;
    }
    if (this.adminJoinRequest.trim().length === 0 ||
      !UiMapping.inviteInputValid(this.inviteRole, this.selectedRoomIds)) {
      return;
    }
    this.busy = true;
    const input = new CreateInvitationInput(family.familyId, this.inviteRole,
      this.selectedRoomIds.slice(), InviteMode.KEY_WRAP, 1, INVITE_TTL_MS);
    vm.startInviteFromJoinRequest(this.adminJoinRequest.trim(), input).then(
      (creation: InviteCreation): void => {
        this.createdInviteText = creation.containerText;
        this.createdInviteCode = '';
        this.createdInviteWeak = false;
        this.busy = false;
      }).catch((): void => {
        this.busy = false;
      });
  }

  private createWeakCode(): void {
    const vm = this.familyVm;
    const family = this.activeFamily();
    if (vm === undefined || family === undefined || this.busy) {
      return;
    }
    if (!UiMapping.inviteInputValid(this.inviteRole, this.selectedRoomIds)) {
      return;
    }
    this.busy = true;
    const input = new CreateInvitationInput(family.familyId, this.inviteRole,
      this.selectedRoomIds.slice(), InviteMode.CODE_KEK, 1, INVITE_TTL_MS);
    vm.createCodeInvitation(input).then((creation: InviteCreation): void => {
      this.createdInviteText = creation.containerText;
      this.createdInviteCode = creation.code === undefined ? '' : creation.code;
      this.createdInviteWeak = true;
      this.busy = false;
    }).catch((): void => {
      this.busy = false;
    });
  }

  private startJoin(): void {
    const vm = this.familyVm;
    if (vm === undefined || this.busy) {
      return;
    }
    this.busy = true;
    vm.startJoin(this.displayName.trim().length > 0 ? this.displayName.trim() : undefined)
      .then((): void => {
        this.busy = false;
      }).catch((): void => {
        this.busy = false;
      });
  }

  private submitInvitation(): void {
    const vm = this.familyVm;
    if (vm === undefined || this.busy) {
      return;
    }
    this.busy = true;
    vm.submitJoinInvitation(this.invitationText.trim(),
      this.invitationCode.trim().length > 0 ? this.invitationCode.trim() : undefined)
      .then((): void => {
        this.busy = false;
      }).catch((): void => {
        this.busy = false;
      });
  }

  private completeJoin(): void {
    const vm = this.familyVm;
    if (vm === undefined || this.busy) {
      return;
    }
    this.busy = true;
    vm.completeJoinWithProfile(this.displayName.trim(), this.profilePassword).then(
      (): void => {
        this.busy = false;
        this.profilePassword = '';
      }).catch((): void => {
        this.busy = false;
      });
  }

  private confirmDialog(): void {
    const vm = this.familyVm;
    const family = this.activeFamily();
    if (vm === undefined || family === undefined) {
      return;
    }
    const kind = this.dialogKind;
    this.dialogKind = '';
    this.busy = true;
    if (kind === 'remove') {
      vm.removeMember(this.dialogMemberId).then((): void => {
        this.busy = false;
      }).catch((): void => {
        this.busy = false;
      });
    } else if (kind === 'transfer') {
      vm.transferAdmin(this.dialogMemberId).then((): void => {
        this.busy = false;
      }).catch((): void => {
        this.busy = false;
      });
    } else if (kind === 'dissolve') {
      vm.dissolveFamily(family.familyId).then((): void => {
        this.busy = false;
        this.navigation.pop();
      }).catch((): void => {
        this.busy = false;
      });
    } else if (kind === 'leave') {
      vm.leaveFamily(family.familyId).then((): void => {
        this.busy = false;
        this.navigation.pop();
      }).catch((): void => {
        this.busy = false;
      });
    } else if (kind === 'revoke') {
      vm.revokeInvitation(this.dialogInviteId).then((): void => {
        this.busy = false;
      }).catch((): void => {
        this.busy = false;
      });
    } else {
      this.busy = false;
    }
  }

  private importReceipt(): void {
    const vm = this.familyVm;
    if (vm === undefined || this.receiptInviteId.trim().length === 0 ||
      this.receiptText.trim().length === 0) {
      return;
    }
    this.busy = true;
    vm.importReceipt(this.receiptInviteId.trim(), this.receiptText.trim()).then(
      (): void => {
        this.busy = false;
        this.receiptText = '';
      }).catch((): void => {
        this.busy = false;
      });
  }

  private memberActionKey(view: FamilyMemberView): string {
    if (view.member.role === MemberRole.GUEST) {
      return 'family.member.extend';
    }
    return 'family.member.change_role';
  }

  private extendGuest(view: FamilyMemberView): void {
    const vm = this.familyVm;
    if (vm === undefined) {
      return;
    }
    const expiresAt = DateTimeUtil.formatUtcCompact(Date.now() + GUEST_EXTEND_MS);
    this.busy = true;
    vm.extendGuest(view.member.memberId, expiresAt).then((): void => {
      this.busy = false;
    }).catch((): void => {
      this.busy = false;
    });
  }

  private changeRole(view: FamilyMemberView): void {
    const vm = this.familyVm;
    if (vm === undefined) {
      return;
    }
    const next = view.member.role === MemberRole.MEMBER
      ? MemberRole.GUEST : MemberRole.MEMBER;
    this.busy = true;
    vm.changeMemberRole(view.member.memberId, next).then((): void => {
      this.busy = false;
    }).catch((): void => {
      this.busy = false;
    });
  }

  private lastSyncText(view: FamilyMemberView): string {
    if (view.lastSyncedAt === undefined) {
      return this.i18n.t('member.sync.never');
    }
    return this.i18n.t('member.sync.last_at',
      new I18nParams([new NameValue('time', view.lastSyncedAt)]));
  }

  private remainingText(view: InvitationView): string {
    const hours = Math.max(0, Math.floor(view.remainingMs / 3600000));
    const minutes = Math.max(0, Math.floor((view.remainingMs % 3600000) / 60000));
    return this.i18n.t('family.invite.remaining',
      new I18nParams([new NameValue('hours', String(hours)),
        new NameValue('minutes', String(minutes))]));
  }

  @Builder
  sectionTab(section: FamilySection, labelKey: string) {
    Button(this.i18n.t(labelKey))
      .height(44)
      .fontSize(AppTypography.label)
      .fontColor(this.section === section ? Color.White : AppColors.inkSoft())
      .backgroundColor(this.section === section
        ? AppColors.primary() : AppColors.surface())
      .borderRadius(AppRadius.chip)
      .onClick((): void => {
        this.selectSection(section);
      })
  }

  @Builder
  membersSection() {
    Column({ space: AppSpacing.sm }) {
      SectionHeader({
        i18n: this.i18n,
        localeRevision: this.localeRevision,
        titleKey: 'family.section.members'
      })
      if (this.family.members.length === 0) {
        EmptyState({
          i18n: this.i18n,
          localeRevision: this.localeRevision,
          titleKey: 'family.members.empty.title',
          messageKey: 'family.members.empty.message'
        })
      }
      ForEach(this.family.members.slice(), (view: FamilyMemberView): void => {
        Column({ space: AppSpacing.xxs }) {
          Row() {
            Column({ space: AppSpacing.xxs }) {
              Text(view.member.displayName)
                .fontSize(AppTypography.body)
                .fontWeight(AppTypography.weightMedium)
                .fontColor(AppColors.ink())
              Row({ space: AppSpacing.xs }) {
                Text(this.i18n.t(view.roleI18nKey))
                  .fontSize(AppTypography.caption)
                  .fontColor(AppColors.primary())
                Text(this.i18n.t(view.statusI18nKey))
                  .fontSize(AppTypography.caption)
                  .fontColor(AppColors.muted())
                Text(this.lastSyncText(view))
                  .fontSize(AppTypography.caption)
                  .fontColor(AppColors.muted())
              }
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            if (this.isAdmin() && view.member.memberId !==
              this.family.activeFamily?.ownerMemberId) {
              Button(this.i18n.t(this.memberActionKey(view)))
                .height(44)
                .fontSize(AppTypography.caption)
                .fontColor(AppColors.primary())
                .backgroundColor(Color.Transparent)
                .onClick((): void => {
                  if (view.member.role === MemberRole.GUEST) {
                    this.extendGuest(view);
                  } else {
                    this.changeRole(view);
                  }
                })
            }
          }
          .width('100%')
          if (view.allowedRoomNames.length > 0) {
            Text(view.allowedRoomNames.join(', '))
              .fontSize(AppTypography.caption)
              .fontColor(AppColors.muted())
          }
          if (this.isAdmin()) {
            Row({ space: AppSpacing.xs }) {
              if (view.member.memberId !== this.family.activeFamily?.ownerMemberId) {
                Button(this.i18n.t('family.member.transfer'))
                  .height(44)
                  .fontSize(AppTypography.caption)
                  .fontColor(AppColors.inkSoft())
                  .backgroundColor(AppColors.field())
                  .borderRadius(AppRadius.chip)
                  .onClick((): void => {
                    this.dialogKind = 'transfer';
                    this.dialogMemberId = view.member.memberId;
                  })
                Button(this.i18n.t('family.member.remove'))
                  .height(44)
                  .fontSize(AppTypography.caption)
                  .fontColor(AppColors.red())
                  .backgroundColor(Color.Transparent)
                  .onClick((): void => {
                    this.dialogKind = 'remove';
                    this.dialogMemberId = view.member.memberId;
                  })
              }
            }
          }
        }
        .width('100%')
        .padding(AppSpacing.sm)
        .backgroundColor(AppColors.surface())
        .borderRadius(AppRadius.card)
        .border({ width: 1, color: AppColors.edge() })
        .alignItems(HorizontalAlign.Start)
      }, (view: FamilyMemberView): string => view.member.memberId)
      Text(this.i18n.t('family.contact_sync_only'))
        .fontSize(AppTypography.caption)
        .fontColor(AppColors.muted())
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  roleAndRoomPicker() {
    Column({ space: AppSpacing.xs }) {
      Text(this.i18n.t('family.invite.role'))
        .fontSize(AppTypography.label)
        .fontColor(AppColors.muted())
      Row({ space: AppSpacing.xs }) {
        Button(this.i18n.t('member.role.member'))
          .height(44)
          .fontSize(AppTypography.caption)
          .fontColor(this.inviteRole === MemberRole.MEMBER
            ? Color.White : AppColors.inkSoft())
          .backgroundColor(this.inviteRole === MemberRole.MEMBER
            ? AppColors.primary() : AppColors.field())
          .borderRadius(AppRadius.chip)
          .onClick((): void => {
            this.inviteRole = MemberRole.MEMBER;
          })
        Button(this.i18n.t('member.role.guest'))
          .height(44)
          .fontSize(AppTypography.caption)
          .fontColor(this.inviteRole === MemberRole.GUEST
            ? Color.White : AppColors.inkSoft())
          .backgroundColor(this.inviteRole === MemberRole.GUEST
            ? AppColors.primary() : AppColors.field())
          .borderRadius(AppRadius.chip)
          .onClick((): void => {
            this.inviteRole = MemberRole.GUEST;
          })
      }
      Text(this.i18n.t('family.invite.rooms'))
        .fontSize(AppTypography.label)
        .fontColor(AppColors.muted())
      Scroll() {
        Row({ space: AppSpacing.xs }) {
          ForEach(this.rooms.rooms.slice(), (room: Room): void => {
            Button(room.roomName)
              .height(44)
              .fontSize(AppTypography.caption)
              .fontColor(this.selectedRoomIds.indexOf(room.roomId) >= 0
                ? Color.White : AppColors.inkSoft())
              .backgroundColor(this.selectedRoomIds.indexOf(room.roomId) >= 0
                ? AppColors.primary() : AppColors.field())
              .borderRadius(AppRadius.chip)
              .onClick((): void => {
                this.toggleRoom(room.roomId);
              })
          }, (room: Room): string => room.roomId)
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  invitesSection() {
    Column({ space: AppSpacing.sm }) {
      SectionHeader({
        i18n: this.i18n,
        localeRevision: this.localeRevision,
        titleKey: 'family.section.invites'
      })
      if (!this.canInvite()) {
        Text(this.i18n.t('family.invite.admin_only'))
          .fontSize(AppTypography.label)
          .fontColor(AppColors.muted())
      } else {
        Text(this.i18n.t('family.invite.key_wrap_hint'))
          .fontSize(AppTypography.label)
          .fontColor(AppColors.inkSoft())
        AppTextField({
          i18n: this.i18n,
          localeRevision: this.localeRevision,
          labelKey: 'family.invite.join_request',
          placeholderKey: 'family.invite.join_request_placeholder',
          value: this.adminJoinRequest,
          onChange: (value: string): void => {
            this.adminJoinRequest = value;
          }
        })
        this.roleAndRoomPicker()
        Row({ space: AppSpacing.sm }) {
          PrimaryButton({
            i18n: this.i18n,
            localeRevision: this.localeRevision,
            labelKey: 'family.invite.create_from_request',
            isEnabled: !this.busy && this.adminJoinRequest.trim().length > 0 &&
              UiMapping.inviteInputValid(this.inviteRole, this.selectedRoomIds),
            fullWidth: false,
            onTap: (): void => {
              this.createFromRequest();
            }
          })
          Button(this.i18n.t('family.invite.create_code'))
            .height(48)
            .fontSize(AppTypography.body)
            .fontColor(Color.White)
            .backgroundColor(AppColors.amber())
            .borderRadius(AppRadius.button)
            .enabled(!this.busy &&
              UiMapping.inviteInputValid(this.inviteRole, this.selectedRoomIds))
            .onClick((): void => {
              this.createWeakCode();
            })
        }
        Text(this.i18n.t('invite.security.weak_mode_warning'))
          .fontSize(AppTypography.caption)
          .fontColor(AppColors.amber())
        if (this.createdInviteText.length > 0) {
          Column({ space: AppSpacing.xxs }) {
            Text(this.i18n.t('family.invite.created'))
              .fontSize(AppTypography.label)
              .fontColor(AppColors.green())
            Text(this.createdInviteText)
              .fontSize(AppTypography.caption)
              .fontColor(AppColors.inkSoft())
              .wordBreak(WordBreak.BREAK_ALL)
              .copyOption(CopyOptions.LocalDevice)
            if (this.createdInviteWeak && this.createdInviteCode.length > 0) {
              Text(this.i18n.t('family.invite.code_once') + ' ' + this.createdInviteCode)
                .fontSize(AppTypography.body)
                .fontColor(AppColors.amber())
            }
            Text(this.i18n.t('invite.security.guest_scope_not_crypto'))
              .fontSize(AppTypography.caption)
              .fontColor(AppColors.muted())
          }
          .width('100%')
          .padding(AppSpacing.sm)
          .backgroundColor(AppColors.field())
          .borderRadius(AppRadius.card)
          .alignItems(HorizontalAlign.Start)
        }
      }

      ForEach(this.family.invitations.slice(), (view: InvitationView): void => {
        Column({ space: AppSpacing.xxs }) {
          Row() {
            Text(this.i18n.t(view.targetRoleI18nKey) + ' · ' +
              this.i18n.t(view.modeI18nKey))
              .fontSize(AppTypography.body)
              .fontColor(AppColors.ink())
              .layoutWeight(1)
            Text(this.i18n.t(I18nInvitationStatusKey.of(view.record.status)))
              .fontSize(AppTypography.caption)
              .fontColor(AppColors.muted())
          }
          .width('100%')
          Text(this.remainingText(view))
            .fontSize(AppTypography.caption)
            .fontColor(AppColors.muted())
          if (view.isWeakMode) {
            Text(this.i18n.t('invite.security.weak_mode_warning'))
              .fontSize(AppTypography.caption)
              .fontColor(AppColors.amber())
          }
          if (this.canInvite()) {
            Row({ space: AppSpacing.xs }) {
              Button(this.i18n.t('family.invite.import_receipt'))
                .height(44)
                .fontSize(AppTypography.caption)
                .fontColor(AppColors.primary())
                .backgroundColor(Color.Transparent)
                .onClick((): void => {
                  this.receiptInviteId = view.record.inviteId;
                })
              Button(this.i18n.t('family.invite.revoke'))
                .height(44)
                .fontSize(AppTypography.caption)
                .fontColor(AppColors.red())
                .backgroundColor(Color.Transparent)
                .onClick((): void => {
                  this.dialogKind = 'revoke';
                  this.dialogInviteId = view.record.inviteId;
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
      }, (view: InvitationView): string => view.record.inviteId)

      if (this.receiptInviteId.length > 0 && this.canInvite()) {
        AppTextField({
          i18n: this.i18n,
          localeRevision: this.localeRevision,
          labelKey: 'family.invite.receipt',
          placeholderKey: 'family.invite.receipt_placeholder',
          value: this.receiptText,
          onChange: (value: string): void => {
            this.receiptText = value;
          }
        })
        PrimaryButton({
          i18n: this.i18n,
          localeRevision: this.localeRevision,
          labelKey: 'family.invite.import_receipt',
          isEnabled: !this.busy && this.receiptText.trim().length > 0,
          fullWidth: false,
          onTap: (): void => {
            this.importReceipt();
          }
        })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  joinSection() {
    Column({ space: AppSpacing.sm }) {
      SectionHeader({
        i18n: this.i18n,
        localeRevision: this.localeRevision,
        titleKey: 'family.section.join'
      })
      Text(this.i18n.t('family.join.hint'))
        .fontSize(AppTypography.label)
        .fontColor(AppColors.inkSoft())
      if (this.joinRequestText.length === 0) {
        AppTextField({
          i18n: this.i18n,
          localeRevision: this.localeRevision,
          labelKey: 'family.join.display_name',
          placeholderKey: 'onboarding.display_name',
          value: this.displayName,
          onChange: (value: string): void => {
            this.displayName = value;
          }
        })
        PrimaryButton({
          i18n: this.i18n,
          localeRevision: this.localeRevision,
          labelKey: 'family.join.start',
          isEnabled: !this.busy && this.displayName.trim().length > 0,
          onTap: (): void => {
            this.startJoin();
          }
        })
      } else {
        Text(this.i18n.t('family.join.request_ready'))
          .fontSize(AppTypography.label)
          .fontColor(AppColors.green())
        Text(this.joinRequestText)
          .fontSize(AppTypography.caption)
          .fontColor(AppColors.inkSoft())
          .wordBreak(WordBreak.BREAK_ALL)
          .copyOption(CopyOptions.LocalDevice)
        AppTextField({
          i18n: this.i18n,
          localeRevision: this.localeRevision,
          labelKey: 'family.join.invitation',
          placeholderKey: 'onboarding.invitation_text',
          value: this.invitationText,
          onChange: (value: string): void => {
            this.invitationText = value;
          }
        })
        AppTextField({
          i18n: this.i18n,
          localeRevision: this.localeRevision,
          labelKey: 'family.join.code_optional',
          placeholderKey: 'onboarding.invitation_code',
          value: this.invitationCode,
          onChange: (value: string): void => {
            this.invitationCode = value;
          }
        })
        PrimaryButton({
          i18n: this.i18n,
          localeRevision: this.localeRevision,
          labelKey: 'family.join.submit',
          isEnabled: !this.busy && this.invitationText.trim().length > 0,
          onTap: (): void => {
            this.submitInvitation();
          }
        })
      }
      if (this.family.join !== undefined) {
        Text(this.i18n.t(UiMapping.joinPhaseKey(this.family.join.phase)))
          .fontSize(AppTypography.label)
          .fontColor(AppColors.muted())
        if (this.family.join.error !== undefined) {
          Text(this.i18n.t(this.family.join.error.i18nKey))
            .fontSize(AppTypography.caption)
            .fontColor(AppColors.red())
        }
        if (this.family.join.phase === FamilyJoinPhase.MEMBER_BOUND) {
          Text(this.i18n.t('family.join.profile_hint'))
            .fontSize(AppTypography.label)
            .fontColor(AppColors.inkSoft())
          AppTextField({
            i18n: this.i18n,
            localeRevision: this.localeRevision,
            labelKey: 'family.join.display_name',
            placeholderKey: 'onboarding.display_name',
            value: this.displayName,
            onChange: (value: string): void => {
              this.displayName = value;
            }
          })
          AppTextField({
            i18n: this.i18n,
            localeRevision: this.localeRevision,
            labelKey: 'family.join.password',
            placeholderKey: 'onboarding.password',
            value: this.profilePassword,
            password: true,
            onChange: (value: string): void => {
              this.profilePassword = value;
            }
          })
          PrimaryButton({
            i18n: this.i18n,
            localeRevision: this.localeRevision,
            labelKey: 'family.join.complete',
            isEnabled: !this.busy && this.displayName.trim().length > 0 &&
              this.profilePassword.length >= 8,
            onTap: (): void => {
              this.completeJoin();
            }
          })
        }
      }
      Button(this.i18n.t('family.join.cancel'))
        .height(44)
        .fontSize(AppTypography.label)
        .fontColor(AppColors.inkSoft())
        .backgroundColor(AppColors.field())
        .borderRadius(AppRadius.button)
        .onClick((): void => {
          const vm = this.familyVm;
          if (vm !== undefined) {
            vm.cancelJoin().catch((): void => undefined);
          }
          this.joinRequestText = '';
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  familySection() {
    Column({ space: AppSpacing.sm }) {
      SectionHeader({
        i18n: this.i18n,
        localeRevision: this.localeRevision,
        titleKey: 'family.section.family'
      })
      ForEach(this.family.families.slice(), (value: Family): void => {
        Row() {
          Text(value.familyName)
            .fontSize(AppTypography.body)
            .fontColor(AppColors.ink())
            .layoutWeight(1)
          if (this.family.activeFamily !== undefined &&
            value.familyId === this.family.activeFamily.familyId) {
            Text(this.i18n.t('family.current'))
              .fontSize(AppTypography.caption)
              .fontColor(AppColors.green())
          } else {
            Button(this.i18n.t('family.switch'))
              .height(44)
              .fontSize(AppTypography.caption)
              .fontColor(AppColors.primary())
              .backgroundColor(Color.Transparent)
              .onClick((): void => {
                const vm = this.familyVm;
                if (vm !== undefined) {
                  vm.switchFamily(value.familyId).catch((): void => undefined);
                }
              })
          }
        }
        .width('100%')
        .padding(AppSpacing.sm)
        .backgroundColor(AppColors.surface())
        .borderRadius(AppRadius.card)
      }, (value: Family): string => value.familyId)
      if (this.isAdmin()) {
        Text(this.i18n.t('family.rotation.notice'))
          .fontSize(AppTypography.caption)
          .fontColor(AppColors.amber())
        Row({ space: AppSpacing.sm }) {
          Button(this.i18n.t('family.leave'))
            .height(44)
            .fontSize(AppTypography.label)
            .fontColor(AppColors.inkSoft())
            .backgroundColor(AppColors.field())
            .borderRadius(AppRadius.button)
            .onClick((): void => {
              this.dialogKind = 'leave';
            })
          Button(this.i18n.t('family.dissolve'))
            .height(44)
            .fontSize(AppTypography.label)
            .fontColor(Color.White)
            .backgroundColor(AppColors.red())
            .borderRadius(AppRadius.button)
            .onClick((): void => {
              this.dialogKind = 'dissolve';
            })
        }
      } else {
        Button(this.i18n.t('family.leave'))
          .height(44)
          .fontSize(AppTypography.label)
          .fontColor(AppColors.inkSoft())
          .backgroundColor(AppColors.field())
          .borderRadius(AppRadius.button)
          .onClick((): void => {
            this.dialogKind = 'leave';
          })
      }
      Text(this.i18n.t('family.last_admin'))
        .fontSize(AppTypography.caption)
        .fontColor(AppColors.muted())
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  private dialogTitleKey(): string {
    if (this.dialogKind === 'remove') {
      return 'family.member.remove';
    }
    if (this.dialogKind === 'transfer') {
      return 'family.member.transfer';
    }
    if (this.dialogKind === 'dissolve') {
      return 'family.dissolve';
    }
    if (this.dialogKind === 'leave') {
      return 'family.leave';
    }
    return 'family.invite.revoke';
  }

  private dialogMessageKey(): string {
    if (this.dialogKind === 'transfer') {
      return 'family.transfer.confirm';
    }
    if (this.dialogKind === 'dissolve') {
      return 'family.dissolve_confirm';
    }
    if (this.dialogKind === 'leave') {
      return 'family.leave_confirm';
    }
    if (this.dialogKind === 'revoke') {
      return 'family.invite.revoke_confirm';
    }
    return 'family.remove.confirm';
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        Scroll() {
          Column({ space: AppSpacing.md }) {
            Row() {
              Column({ space: AppSpacing.xxs }) {
                Text(this.family.activeFamily === undefined
                  ? this.i18n.t('family.none') : this.family.activeFamily.familyName)
                  .fontSize(AppTypography.title)
                  .fontWeight(AppTypography.weightBold)
                  .fontColor(AppColors.ink())
                if (this.family.capabilities !== undefined) {
                  Text(this.i18n.t(UiMapping.roleKey(this.family.capabilities.role)))
                    .fontSize(AppTypography.label)
                    .fontColor(AppColors.muted())
                }
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              if (this.busy) {
                LoadingProgress()
                  .width(24)
                  .height(24)
                  .color(AppColors.primary())
              }
            }
            .width('100%')

            Scroll() {
              Row({ space: AppSpacing.xs }) {
                this.sectionTab(FamilySection.MEMBERS, 'family.section.members')
                this.sectionTab(FamilySection.INVITES, 'family.section.invites')
                this.sectionTab(FamilySection.JOIN, 'family.section.join')
                this.sectionTab(FamilySection.FAMILY, 'family.section.family')
              }
            }
            .scrollable(ScrollDirection.Horizontal)
            .scrollBar(BarState.Off)
            .width('100%')

            if (this.family.phase === 'LOADING' && this.family.activeFamily === undefined) {
              LoadingSkeleton({ rows: 3, cardHeight: 72 })
            } else if (this.family.phase === 'ERROR') {
              ErrorState({
                i18n: this.i18n,
                localeRevision: this.localeRevision,
                messageKey: this.family.error === undefined
                  ? 'common.refresh_failed' : this.family.error.i18nKey,
                onRetry: (): void => {
                  const vm = this.familyVm;
                  if (vm !== undefined) {
                    vm.refresh().catch((): void => undefined);
                  }
                }
              })
            } else if (this.family.activeFamily === undefined) {
              EmptyState({
                i18n: this.i18n,
                localeRevision: this.localeRevision,
                titleKey: 'family.none',
                messageKey: 'family.none_message'
              })
            } else {
              if (this.family.error !== undefined) {
                Text(this.i18n.t(this.family.error.i18nKey))
                  .fontSize(AppTypography.caption)
                  .fontColor(AppColors.red())
              }
              if (this.family.needsUnlock) {
                Text(this.i18n.t('family.needs_unlock'))
                  .fontSize(AppTypography.caption)
                  .fontColor(AppColors.amber())
              }
              if (this.section === FamilySection.MEMBERS) {
                this.membersSection()
              } else if (this.section === FamilySection.INVITES) {
                this.invitesSection()
              } else if (this.section === FamilySection.JOIN) {
                this.joinSection()
              } else {
                this.familySection()
              }
            }
          }
          .width('100%')
          .padding(AppSpacing.md)
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)

        if (this.dialogKind.length > 0) {
          AppDialog({
            i18n: this.i18n,
            localeRevision: this.localeRevision,
            titleKey: this.dialogTitleKey(),
            messageKey: this.dialogMessageKey(),
            destructive: this.dialogKind === 'remove' || this.dialogKind === 'dissolve' ||
              this.dialogKind === 'leave' || this.dialogKind === 'revoke',
            busy: this.busy,
            onConfirm: (): void => {
              this.confirmDialog();
            },
            onCancel: (): void => {
              this.dialogKind = '';
            }
          })
        }
      }
      .width('100%')
      .height('100%')
      .id('family-locale-' + this.localeRevision)
    }
    .title(this.i18n.t('page.family.title'))
    .backgroundColor(AppColors.background())
  }
}

/** Invitation status key without importing a service helper into the page. */
class I18nInvitationStatusKey {
  static of(status: string): string {
    if (status === 'ACCEPTED') {
      return 'invite.status.accepted';
    }
    if (status === 'EXPIRED') {
      return 'invite.status.expired';
    }
    if (status === 'REVOKED') {
      return 'invite.status.revoked';
    }
    return 'invite.status.pending';
  }
}
