/*
 * YaoCore T-09 domain host compile suite.
 * Producer: agent:implementation-engineer | Task: T-09 / wp-024-domain
 *
 * COMPILED_ONLY in this environment (the Hypium Previewer cannot start on this
 * Linux host; TEST-001 §2.3). Its purpose is to pull every new C-08..C-11
 * product module into the ArkTS compile graph. Executable behaviour lives in
 * entry/src/test/host/Domain*.test.mjs (Node) and the device skeleton lives in
 * entry/src/ohosTest/ets/test/domain/.
 */
import { describe, expect, it } from '@ohos/hypium';
import { DomainOperationGate } from '../../main/ets/repository/DomainOperationGate';
import { DomainMigrations } from '../../main/ets/repository/DomainMigrations';
import { FamilyRepository } from '../../main/ets/repository/FamilyRepository';
import { RoomRepository } from '../../main/ets/repository/RoomRepository';
import { DeviceRepository } from '../../main/ets/repository/DeviceRepository';
import { SceneRepository } from '../../main/ets/repository/SceneRepository';
import { DeviceSnapshotCodec } from '../../main/ets/repository/DeviceSnapshotCodec';
import { FamilyService } from '../../main/ets/service/family/FamilyService';
import { FamilyJoinSession } from '../../main/ets/service/family/FamilyJoinSession';
import { FamilyRbac } from '../../main/ets/service/family/FamilyRbac';
import { RoomService } from '../../main/ets/service/room/RoomService';
import { DeviceCommandRunner } from '../../main/ets/service/device/DeviceCommandRunner';
import { SceneService } from '../../main/ets/service/scene/SceneService';
import { SceneExecutor } from '../../main/ets/service/scene/SceneExecutor';
import { SceneValidation } from '../../main/ets/service/scene/SceneValidation';

export function DomainHostSuite() {
  describe('T09_domain_compile', () => {
    it('T09_domain_modules_are_present', 0, () => {
      expect(DomainOperationGate !== undefined).assertTrue();
      expect(DomainMigrations !== undefined).assertTrue();
      expect(FamilyRepository.registerMigrations !== undefined).assertTrue();
      expect(RoomRepository.registerMigrations !== undefined).assertTrue();
      expect(DeviceRepository.registerMigrations !== undefined).assertTrue();
      expect(SceneRepository.registerMigrations !== undefined).assertTrue();
      expect(DeviceSnapshotCodec !== undefined).assertTrue();
      expect(FamilyService !== undefined).assertTrue();
      expect(FamilyJoinSession !== undefined).assertTrue();
      expect(FamilyRbac !== undefined).assertTrue();
      expect(RoomService !== undefined).assertTrue();
      expect(DeviceCommandRunner !== undefined).assertTrue();
      expect(SceneService !== undefined).assertTrue();
      expect(SceneExecutor !== undefined).assertTrue();
      expect(SceneValidation !== undefined).assertTrue();
    });
  });
}
