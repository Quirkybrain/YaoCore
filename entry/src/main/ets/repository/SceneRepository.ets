/*
 * YaoCore C-11 SceneRepository.
 * Producer: agent:implementation-engineer | Task: T-09 / wp-024-domain
 * Contract: DES-B §6.1.3, §6.3.4
 *
 * Scene persistence and reference cleanup only. `actions_json` is the
 * canonical serialized SceneAction[]; a malformed row is a storage failure,
 * never a partially executable scene.
 *
 * O-1: public reads/writes run through the injected DomainOperationGate.
 * `tx`-taking reference-cleanup methods are transaction-context only and are
 * invoked from C-10's single top-level removal transaction.
 */
import { AppError, AppErrors } from '../common/types/AppError';
import { DeviceAction } from '../common/constants/DeviceConstants';
import { JsonKind } from '../common/types/JsonNode';
import type { JsonNode } from '../common/types/JsonNode';
import { JsonParser, JsonLimits } from '../common/utils/JsonParser';
import { JsonAtom } from '../common/utils/JsonAtom';
import type { CommandValue } from '../common/utils/JsonAtom';
import { DateTimeUtil } from '../common/utils/DateTimeUtil';
import type { ClockPort, IdPort } from '../common/types/Ports';
import { Scene, SceneAction } from '../model/FamilyModels';
import { DeviceKey } from '../model/DeviceKey';
import type { RdbRow, RdbStore, RdbTransaction } from '../service/storage/RdbStore';
import { DomainOperationGate } from './DomainOperationGate';
import type { SceneReferencePort } from './DomainPorts';
import { SceneCleanupSummary } from './DomainModels';
import { SqlCells } from './SqlCells';

const SCENE_COLUMNS: string = 'scene_id, family_id, scene_name, icon, actions_json, ' +
  'is_enabled, updated_at';

export class SceneRepository implements SceneReferencePort {
  private readonly rdb: RdbStore;
  private readonly clock: ClockPort;
  private readonly ids: IdPort;
  private readonly gate: DomainOperationGate;
  private initialized: boolean = false;

  constructor(rdb: RdbStore, clock: ClockPort, ids: IdPort, gate?: DomainOperationGate) {
    this.rdb = rdb;
    this.clock = clock;
    this.ids = ids;
    this.gate = gate === undefined ? new DomainOperationGate() : gate;
  }

  async initialize(): Promise<void> {
    try {
      await this.rdb.query('SELECT scene_id FROM scene LIMIT 0');
    } catch (error) {
      throw SceneRepository.storageError(error as Error);
    }
    this.initialized = true;
  }

  async listScenes(familyId: string): Promise<ReadonlyArray<Scene>> {
    this.ensureInitialized();
    const checked = SceneRepository.requireIdentifier(familyId, 'familyId');
    return this.gate.run(async (): Promise<ReadonlyArray<Scene>> => {
      return this.listScenesInTransaction(this.rdb, checked);
    });
  }

  async getScene(sceneId: string): Promise<Scene | undefined> {
    this.ensureInitialized();
    const checked = SceneRepository.requireSceneId(sceneId);
    return this.gate.run(async (): Promise<Scene | undefined> => {
      return this.readScene(this.rdb, checked);
    });
  }

  async putScene(scene: Scene): Promise<void> {
    this.ensureInitialized();
    return this.gate.run(async (): Promise<void> => {
      await this.rdb.transaction<void>(async (tx: RdbTransaction): Promise<void> => {
        await SceneRepository.insertScene(tx, scene,
          DateTimeUtil.nowUtcCompact(this.clock));
      });
    });
  }

  async deleteScene(tx: RdbTransaction, sceneId: string): Promise<void> {
    const checked = SceneRepository.requireSceneId(sceneId);
    const scene = await this.readScene(tx, checked);
    if (scene === undefined) {
      throw AppErrors.of('SCENE_NOT_FOUND', []);
    }
    await tx.execute('DELETE FROM scene WHERE scene_id = ?', [checked]);
  }

  // ---- SceneReferencePort (transaction-context) --------------------------

  async removeDeviceReferences(tx: RdbTransaction, familyId: string,
    key: DeviceKey): Promise<SceneCleanupSummary> {
    const scenes = await this.listScenesInTransaction(tx, familyId);
    let removedActions = 0;
    const affectedIds: string[] = [];
    const affectedNames: string[] = [];
    for (let index = 0; index < scenes.length; index++) {
      const scene = scenes[index];
      const kept: SceneAction[] = [];
      let removedHere = 0;
      for (let actionIndex = 0; actionIndex < scene.actions.length; actionIndex++) {
        const action = scene.actions[actionIndex];
        if (action.gatewayId === key.gatewayId && action.targetDeviceId === key.deviceId) {
          removedHere++;
        } else {
          kept.push(action);
        }
      }
      if (removedHere === 0) {
        continue;
      }
      removedActions += removedHere;
      affectedIds.push(scene.sceneId);
      affectedNames.push(scene.sceneName);
      const updated = new Scene(scene.sceneId, scene.familyId, scene.sceneName, scene.icon,
        kept, scene.isEnabled);
      await SceneRepository.insertScene(tx, updated,
        DateTimeUtil.nowUtcCompact(this.clock));
    }
    return new SceneCleanupSummary(removedActions, affectedIds, affectedNames);
  }

  async removeGatewayReferences(tx: RdbTransaction, familyId: string,
    gatewayId: string): Promise<SceneCleanupSummary> {
    const scenes = await this.listScenesInTransaction(tx, familyId);
    let removedActions = 0;
    const affectedIds: string[] = [];
    const affectedNames: string[] = [];
    for (let index = 0; index < scenes.length; index++) {
      const scene = scenes[index];
      const kept: SceneAction[] = [];
      let removedHere = 0;
      for (let actionIndex = 0; actionIndex < scene.actions.length; actionIndex++) {
        const action = scene.actions[actionIndex];
        if (action.gatewayId === gatewayId) {
          removedHere++;
        } else {
          kept.push(action);
        }
      }
      if (removedHere === 0) {
        continue;
      }
      removedActions += removedHere;
      affectedIds.push(scene.sceneId);
      affectedNames.push(scene.sceneName);
      const updated = new Scene(scene.sceneId, scene.familyId, scene.sceneName, scene.icon,
        kept, scene.isEnabled);
      await SceneRepository.insertScene(tx, updated,
        DateTimeUtil.nowUtcCompact(this.clock));
    }
    return new SceneCleanupSummary(removedActions, affectedIds, affectedNames);
  }

  async listSceneIdsReferencing(tx: RdbTransaction, familyId: string,
    key: DeviceKey): Promise<ReadonlyArray<string>> {
    const scenes = await this.listScenesInTransaction(tx, familyId);
    const ids: string[] = [];
    for (let index = 0; index < scenes.length; index++) {
      const scene = scenes[index];
      for (let actionIndex = 0; actionIndex < scene.actions.length; actionIndex++) {
        const action = scene.actions[actionIndex];
        if (action.gatewayId === key.gatewayId &&
          action.targetDeviceId === key.deviceId) {
          ids.push(scene.sceneId);
          break;
        }
      }
    }
    return ids;
  }

  // ---- Transaction-context helpers ---------------------------------------

  async readScene(tx: RdbTransaction, sceneId: string): Promise<Scene | undefined> {
    const rows = await tx.query('SELECT ' + SCENE_COLUMNS + ' FROM scene WHERE scene_id = ?',
      [sceneId]);
    if (rows.length === 0) {
      return undefined;
    }
    return SceneRepository.sceneFromRow(rows[0]);
  }

  async listScenesInTransaction(tx: RdbTransaction,
    familyId: string): Promise<ReadonlyArray<Scene>> {
    const rows = await tx.query('SELECT ' + SCENE_COLUMNS +
      ' FROM scene WHERE family_id = ? ORDER BY scene_id ASC', [familyId]);
    const scenes: Scene[] = [];
    for (let index = 0; index < rows.length; index++) {
      scenes.push(SceneRepository.sceneFromRow(rows[index]));
    }
    return scenes;
  }

  // ---- Codec --------------------------------------------------------------

  static encodeActions(actions: ReadonlyArray<SceneAction>): string {
    let text = '[';
    for (let index = 0; index < actions.length; index++) {
      if (index > 0) {
        text += ',';
      }
      const action = actions[index];
      text += '{"gatewayId":' + JsonAtom.normalizeString(action.gatewayId);
      text += ',"targetDeviceId":' + JsonAtom.normalizeString(action.targetDeviceId);
      text += ',"action":' + JsonAtom.normalizeString(action.action);
      if (action.value !== undefined) {
        text += ',"value":' + JsonAtom.encode(action.value);
      }
      if (action.delayMs !== undefined) {
        text += ',"delayMs":' + String(action.delayMs);
      }
      text += '}';
    }
    return text + ']';
  }

  static decodeActions(text: string): ReadonlyArray<SceneAction> {
    let root: JsonNode;
    try {
      root = JsonParser.parse(text, new JsonLimits(65536, 8, 8192));
    } catch (error) {
      throw AppErrors.of('STORAGE_RDB_ERROR', []);
    }
    if (root.kind !== JsonKind.ARRAY) {
      throw AppErrors.of('STORAGE_RDB_ERROR', []);
    }
    const actions: SceneAction[] = [];
    for (let index = 0; index < root.arrayValue.length; index++) {
      const node = root.arrayValue[index];
      if (node.kind !== JsonKind.OBJECT) {
        throw AppErrors.of('STORAGE_RDB_ERROR', []);
      }
      const gatewayId = SceneRepository.requiredString(node, 'gatewayId');
      const targetDeviceId = SceneRepository.requiredString(node, 'targetDeviceId');
      const action = SceneRepository.parseAction(SceneRepository.requiredString(node, 'action'));
      const valueNode = node.get('value');
      let value: CommandValue | undefined = undefined;
      if (valueNode !== undefined) {
        if (valueNode.kind === JsonKind.STRING) {
          value = valueNode.stringValue;
        } else if (valueNode.kind === JsonKind.NUMBER) {
          value = valueNode.numberValue;
        } else if (valueNode.kind === JsonKind.BOOLEAN) {
          value = valueNode.booleanValue;
        } else {
          throw AppErrors.of('STORAGE_RDB_ERROR', []);
        }
      }
      const delayNode = node.get('delayMs');
      let delayMs: number | undefined = undefined;
      if (delayNode !== undefined) {
        if (delayNode.kind !== JsonKind.NUMBER || !Number.isInteger(delayNode.numberValue) ||
          delayNode.numberValue < 0) {
          throw AppErrors.of('STORAGE_RDB_ERROR', []);
        }
        delayMs = delayNode.numberValue;
      }
      try {
        actions.push(new SceneAction(gatewayId, targetDeviceId, action, value, delayMs));
      } catch (error) {
        throw AppErrors.of('STORAGE_RDB_ERROR', []);
      }
    }
    return actions;
  }

  private static async insertScene(tx: RdbTransaction, scene: Scene,
    updatedAt: string): Promise<void> {
    await tx.execute('INSERT OR REPLACE INTO scene (' + SCENE_COLUMNS + ') ' +
      'VALUES (?, ?, ?, ?, ?, ?, ?)',
    [scene.sceneId, scene.familyId, scene.sceneName, scene.icon,
      SceneRepository.encodeActions(scene.actions), scene.isEnabled ? 1 : 0, updatedAt]);
  }

  private static sceneFromRow(row: RdbRow): Scene {
    try {
      return new Scene(SqlCells.requiredString(row, 'scene_id'),
        SqlCells.requiredString(row, 'family_id'),
        SqlCells.requiredString(row, 'scene_name'),
        SqlCells.requiredString(row, 'icon'),
        SceneRepository.decodeActions(SqlCells.requiredString(row, 'actions_json')),
        SqlCells.requiredNumber(row, 'is_enabled') !== 0);
    } catch (error) {
      if (error instanceof AppError && error.code.startsWith('STORAGE_')) {
        throw error;
      }
      throw AppErrors.of('STORAGE_RDB_ERROR', []);
    }
  }

  private static requiredString(node: JsonNode, key: string): string {
    const value = node.get(key);
    if (value === undefined || value.kind !== JsonKind.STRING) {
      throw AppErrors.of('STORAGE_RDB_ERROR', []);
    }
    return value.stringValue;
  }

  private static parseAction(value: string): DeviceAction {
    if (value === DeviceAction.OPEN) {
      return DeviceAction.OPEN;
    }
    if (value === DeviceAction.CLOSE) {
      return DeviceAction.CLOSE;
    }
    if (value === DeviceAction.TURN_ON) {
      return DeviceAction.TURN_ON;
    }
    if (value === DeviceAction.TURN_OFF) {
      return DeviceAction.TURN_OFF;
    }
    if (value === DeviceAction.SET_BRIGHTNESS) {
      return DeviceAction.SET_BRIGHTNESS;
    }
    if (value === DeviceAction.SET_COLOR) {
      return DeviceAction.SET_COLOR;
    }
    if (value === DeviceAction.SET_TARGET_TEMPERATURE) {
      return DeviceAction.SET_TARGET_TEMPERATURE;
    }
    if (value === DeviceAction.SET_MODE) {
      return DeviceAction.SET_MODE;
    }
    if (value === DeviceAction.SET_POSITION) {
      return DeviceAction.SET_POSITION;
    }
    if (value === DeviceAction.SET_SPEED) {
      return DeviceAction.SET_SPEED;
    }
    if (value === DeviceAction.SET_VOLUME) {
      return DeviceAction.SET_VOLUME;
    }
    if (value === DeviceAction.SET_DEVICE_NAME) {
      return DeviceAction.SET_DEVICE_NAME;
    }
    if (value === DeviceAction.SET_DEVICE_ROOM) {
      return DeviceAction.SET_DEVICE_ROOM;
    }
    if (value === DeviceAction.STOP) {
      return DeviceAction.STOP;
    }
    if (value === DeviceAction.BOARD_LED_ON) {
      return DeviceAction.BOARD_LED_ON;
    }
    if (value === DeviceAction.BOARD_LED_OFF) {
      return DeviceAction.BOARD_LED_OFF;
    }
    if (value === DeviceAction.PING) {
      return DeviceAction.PING;
    }
    throw AppErrors.of('STORAGE_RDB_ERROR', []);
  }

  private static requireSceneId(value: string): string {
    if (value.length === 0 || value.length > 63 || value.indexOf(':') >= 0 ||
      !/^[A-Za-z0-9][A-Za-z0-9_.-]*$/.test(value)) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'sceneId');
    }
    return value;
  }

  private static requireIdentifier(value: string, field: string): string {
    if (value.length === 0 || value.length > 63 || value.indexOf(':') >= 0 ||
      !/^[A-Za-z0-9][A-Za-z0-9_.-]*$/.test(value)) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', field);
    }
    return value;
  }

  private static storageError(error: Error): Error {
    if (error instanceof AppError) {
      return error;
    }
    return AppErrors.of('STORAGE_RDB_ERROR', []);
  }

  private ensureInitialized(): void {
    if (!this.initialized) {
      throw AppErrors.of('STORAGE_NOT_INITIALIZED', []);
    }
  }
}
