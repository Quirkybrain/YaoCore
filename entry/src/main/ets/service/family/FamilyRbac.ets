/*
 * YaoCore C-08 family RBAC matrix (data-side enforcement helpers).
 * Producer: agent:implementation-engineer | Task: T-09 / wp-024-domain
 * Contract: DES-A §12.1 RBAC matrix; DES-B §3.2, §3.3; DP-06
 *
 * C-12 owns session-aware policy decisions. C-08 uses this matrix to refuse
 * admin-only operations when the caller supplies an actor role, and to keep
 * the "last ADMIN" data invariant. Hiding UI is never authorization.
 *
 * GUEST room scope is an App policy, NOT a cryptographic boundary: a GUEST
 * holding a command secret can still reach the gateway (ADR-003 §6.3; DP-06).
 */
import { AppErrors } from '../../common/types/AppError';
import { MemberRole } from '../../model/FamilyModels';

export enum FamilyCapability {
  MANAGE_FAMILY = 'MANAGE_FAMILY',
  MANAGE_ROOMS = 'MANAGE_ROOMS',
  INVITE_MEMBERS = 'INVITE_MEMBERS',
  CONTROL_DEVICE = 'CONTROL_DEVICE',
  EXECUTE_SCENE = 'EXECUTE_SCENE',
  VIEW_ALL_DEVICES = 'VIEW_ALL_DEVICES'
}

export class FamilyRbac {
  static allows(role: MemberRole, capability: FamilyCapability): boolean {
    if (role === MemberRole.ADMIN) {
      return true;
    }
    if (role === MemberRole.MEMBER) {
      return capability === FamilyCapability.CONTROL_DEVICE ||
        capability === FamilyCapability.EXECUTE_SCENE ||
        capability === FamilyCapability.VIEW_ALL_DEVICES;
    }
    if (role === MemberRole.GUEST) {
      // Room-scope enforcement happens in canControlRoom/canExecuteSceneInRooms.
      return capability === FamilyCapability.CONTROL_DEVICE ||
        capability === FamilyCapability.EXECUTE_SCENE;
    }
    return false;
  }

  static requireAdmin(role: MemberRole): void {
    if (role !== MemberRole.ADMIN) {
      throw AppErrors.of('AUTH_RBAC_DENIED', []);
    }
  }

  static canControlRoom(role: MemberRole, roomId: string,
    allowedRoomIds: ReadonlyArray<string>): boolean {
    if (role === MemberRole.ADMIN || role === MemberRole.MEMBER) {
      return true;
    }
    if (role !== MemberRole.GUEST || roomId.length === 0) {
      return false;
    }
    for (let index = 0; index < allowedRoomIds.length; index++) {
      if (allowedRoomIds[index] === roomId) {
        return true;
      }
    }
    return false;
  }

  static canExecuteSceneInRooms(role: MemberRole, roomIds: ReadonlyArray<string>,
    allowedRoomIds: ReadonlyArray<string>): boolean {
    if (role === MemberRole.ADMIN || role === MemberRole.MEMBER) {
      return true;
    }
    if (role !== MemberRole.GUEST) {
      return false;
    }
    for (let index = 0; index < roomIds.length; index++) {
      if (!FamilyRbac.canControlRoom(role, roomIds[index], allowedRoomIds)) {
        return false;
      }
    }
    return roomIds.length > 0;
  }
}
