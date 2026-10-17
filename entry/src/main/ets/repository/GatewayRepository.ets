/*
 * YaoCore C-07 GatewayRepository.
 * Producer: agent:implementation-engineer | Task: T-08 / wp-020-storage
 * Contract: DES-A §10.1-§10.6, §22.2-§22.3; ADR-002 §4/§6/§8.3/§8.4
 *
 * Owns gw_route/gw_sequence and the per-gateway command-secret alias. Secrets
 * are stored only through SecretStore (Asset Store); routes carry the alias,
 * directory pins (public), tlsEnabled, port, family and timestamps.
 *
 * Compensation model for cross-store binding (DES-A §10.3): secret first,
 * route second; if the route write fails the previous secret is restored (or
 * the fresh secret deleted). Pending rotation aliases are cleaned on
 * initialize(). P-BLOCKED is runtime-only and is never persisted.
 */
import { AppErrors, AppError } from '../common/types/AppError';
import { NameValue } from '../common/types/NameValue';
import { ProtocolConstants } from '../common/constants/ProtocolConstants';
import { StorageConstants } from '../common/constants/StorageConstants';
import { DateTimeUtil } from '../common/utils/DateTimeUtil';
import { BytesUtil } from '../common/utils/BytesUtil';
import { JsonParser, JsonLimits } from '../common/utils/JsonParser';
import { JsonKind } from '../common/types/JsonNode';
import type { JsonNode } from '../common/types/JsonNode';
import type { ClockPort, IdPort } from '../common/types/Ports';
import { SecureBytes } from '../common/types/SecureBytes';
import { TransportProfile } from '../model/DeviceTypes';
import { GatewayAddress, GatewayRoute, GatewayRouteInit, TlsMaterial } from '../model/GatewayRoute';
import { BleProvisioningResult } from '../model/ProvisioningModels';
import type { PreferencesStore } from '../service/storage/PreferencesStore';
import type { RdbRow, RdbStore, RdbTransaction } from '../service/storage/RdbStore';
import { SecretAlias } from '../service/storage/SecretStore';
import type { SecretStore } from '../service/storage/SecretStore';
import type { SecretDraftPort } from '../service/storage/SecretDraftPort';
import type {
  GatewayAddressPort,
  GatewayCredentialPort,
  GatewayRoutePort,
  GatewaySequencePort,
  InvitationApplicationPort,
  InvitedGateway,
  SecretVerifier
} from './GatewayPorts';

const ROUTE_COLUMNS: string = 'gateway_id, family_id, gateway_name, local_ip, port, ' +
  'profile, tls_enabled, pins_json, pin_alg, key_id, credential_alias, last_known_ip, ' +
  'last_seen_at, created_at, updated_at';

const SELECT_ROUTES: string = 'SELECT ' + ROUTE_COLUMNS + ' FROM gw_route';
const INSERT_ROUTE: string = 'INSERT OR REPLACE INTO gw_route (' + ROUTE_COLUMNS + ') ' +
  'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)';

class RouteCells {
  readonly gatewayId: string;
  readonly familyId: string;
  readonly gatewayName: string;
  readonly localIp: string;
  readonly port: number;
  readonly profile: string;
  readonly tlsEnabled: number;
  readonly pinsJson: string;
  readonly pinAlg: string;
  readonly keyId: string;
  readonly credentialAlias: string;
  readonly lastKnownIp: string;
  readonly lastSeenAt: string | null;
  readonly createdAt: string;
  readonly updatedAt: string;

  constructor(row: RdbRow) {
    this.gatewayId = GatewayRepository.requiredString(row, 'gateway_id');
    this.familyId = GatewayRepository.requiredString(row, 'family_id');
    this.gatewayName = GatewayRepository.requiredString(row, 'gateway_name');
    this.localIp = GatewayRepository.requiredString(row, 'local_ip');
    this.port = GatewayRepository.requiredNumber(row, 'port');
    this.profile = GatewayRepository.requiredString(row, 'profile');
    this.tlsEnabled = GatewayRepository.requiredNumber(row, 'tls_enabled');
    this.pinsJson = GatewayRepository.requiredString(row, 'pins_json');
    this.pinAlg = GatewayRepository.requiredString(row, 'pin_alg');
    this.keyId = GatewayRepository.requiredString(row, 'key_id');
    this.credentialAlias = GatewayRepository.requiredString(row, 'credential_alias');
    this.lastKnownIp = GatewayRepository.requiredString(row, 'last_known_ip');
    this.lastSeenAt = GatewayRepository.optionalString(row, 'last_seen_at');
    this.createdAt = GatewayRepository.requiredString(row, 'created_at');
    this.updatedAt = GatewayRepository.requiredString(row, 'updated_at');
  }
}

export class GatewayRepository implements GatewayRoutePort, GatewayCredentialPort,
  GatewayAddressPort, GatewaySequencePort, InvitationApplicationPort {
  private readonly rdb: RdbStore;
  readonly preferences: PreferencesStore;
  private readonly secrets: SecretStore;
  private readonly secretDrafts: SecretDraftPort;
  private readonly clock: ClockPort;
  private readonly ids: IdPort;
  private initialized: boolean = false;

  constructor(rdb: RdbStore, preferences: PreferencesStore, secrets: SecretStore,
    secretDrafts: SecretDraftPort, clock: ClockPort, ids: IdPort) {
    this.rdb = rdb;
    this.preferences = preferences;
    this.secrets = secrets;
    this.secretDrafts = secretDrafts;
    this.clock = clock;
    this.ids = ids;
  }

  async initialize(): Promise<void> {
    try {
      await this.rdb.query('SELECT gateway_id FROM gw_route LIMIT 0');
      await this.rdb.query('SELECT gateway_id FROM gw_sequence LIMIT 0');
    } catch (error) {
      throw GatewayRepository.storageError(error as Error);
    }
    // Crash recovery: pending rotation aliases are never authoritative.
    let pending: ReadonlyArray<string> = [];
    try {
      pending = await this.secrets.list(StorageConstants.ASSET_PREFIX_GATEWAY_HMAC_PENDING);
    } catch (error) {
      throw GatewayRepository.storageError(error as Error);
    }
    for (let index = 0; index < pending.length; index++) {
      try {
        await this.secrets.remove(pending[index]);
      } catch (error) {
        if (!GatewayRepository.isCode(error as Error, 'ASSET_NOT_FOUND')) {
          throw GatewayRepository.storageError(error as Error);
        }
      }
    }
    this.initialized = true;
  }

  // ---- GatewayRoutePort ---------------------------------------------------

  async listRoutes(): Promise<ReadonlyArray<GatewayRoute>> {
    this.ensureInitialized();
    const rows = await this.rdb.query(SELECT_ROUTES +
      ' ORDER BY gateway_id ASC');
    return this.mapRoutes(rows);
  }

  async listRoutesByFamily(familyId: string): Promise<ReadonlyArray<GatewayRoute>> {
    this.ensureInitialized();
    if (familyId.length === 0 || familyId.length > 63) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'familyId');
    }
    const rows = await this.rdb.query(SELECT_ROUTES +
      ' WHERE family_id = ? ORDER BY gateway_id ASC', [familyId]);
    return this.mapRoutes(rows);
  }

  async getRoute(gatewayId: string): Promise<GatewayRoute | undefined> {
    this.ensureInitialized();
    return this.readRoute(GatewayRepository.requireGatewayId(gatewayId));
  }

  async isBound(gatewayId: string): Promise<boolean> {
    const route = await this.getRoute(gatewayId);
    return route !== undefined;
  }

  // ---- Binding ------------------------------------------------------------

  async commitBinding(result: BleProvisioningResult, draftId: string,
    familyId: string): Promise<GatewayRoute> {
    this.ensureInitialized();
    const gatewayId = result.identity.gatewayId;
    if (familyId.length === 0 || familyId.length > 63) {
      throw AppErrors.of('CONFIGURATION_ERROR', [new NameValue('field', 'familyId')]);
    }
    if (draftId !== result.credentialDraftId) {
      throw AppErrors.of('CONFIGURATION_ERROR', [new NameValue('field', 'draftId')]);
    }

    const existing = await this.readRoute(gatewayId);
    if (existing !== undefined && existing.familyId !== familyId) {
      throw AppErrors.of('CONFIGURATION_ERROR', [new NameValue('field', 'familyId')]);
    }

    if (draftId.length === 0) {
      // Reuse path: the existing secret must remain readable; never rewrite it.
      if (existing === undefined) {
        throw AppErrors.of('PROVISIONING_CREDENTIAL_MISSING', []);
      }
      await this.probeSecret(existing.credentialAlias);
      const route = await this.writeRoute(this.buildRoute(result, familyId, existing));
      await this.markSeen(gatewayId, this.clock.nowMs());
      const stored = await this.readRoute(gatewayId);
      if (stored === undefined) {
        throw AppErrors.of('STORAGE_RDB_ERROR', []);
      }
      return stored;
    }

    let draft: SecureBytes;
    try {
      draft = this.secretDrafts.take(draftId);
    } catch (error) {
      if (GatewayRepository.isCode(error as Error, 'PROVISIONING_CREDENTIAL_MISSING') ||
        GatewayRepository.isCode(error as Error, 'PROVISIONING_SECRET_DRAFT_EXPIRED')) {
        throw AppErrors.of('PROVISIONING_SECRET_DRAFT_EXPIRED', []);
      }
      GatewayRepository.rethrow(error as Error);
    }

    const route = this.buildRoute(result, familyId, existing);
    let oldSecret: SecureBytes | undefined = undefined;
    try {
      oldSecret = await this.tryReadSecret(route.credentialAlias);
      try {
        await this.secrets.put(route.credentialAlias, draft);
      } catch (error) {
        // Step 5 failure: no route is written. ASSET_* propagates unchanged.
        GatewayRepository.rethrow(error as Error);
      }
      try {
        await this.writeRoute(route);
      } catch (error) {
        await this.rollbackSecret(route.credentialAlias, oldSecret);
        throw AppErrors.of('STORAGE_RDB_ERROR', []);
      }
      this.secretDrafts.destroy(draftId);
      await this.markSeen(gatewayId, this.clock.nowMs());
      const stored = await this.readRoute(gatewayId);
      if (stored === undefined) {
        throw AppErrors.of('STORAGE_RDB_ERROR', []);
      }
      return stored;
    } finally {
      draft.destroy();
      if (oldSecret !== undefined) {
        oldSecret.destroy();
      }
    }
  }

  async applyInvitedGateway(entry: InvitedGateway): Promise<void> {
    this.ensureInitialized();
    const existing = await this.readRoute(entry.gatewayId);
    if (existing !== undefined && existing.familyId !== entry.familyId) {
      throw AppErrors.of('CONFIGURATION_ERROR', [new NameValue('field', 'familyId')]);
    }
    const now = DateTimeUtil.formatUtcCompact(this.clock.nowMs());
    const tls = entry.tls;
    const init = new GatewayRouteInit();
    init.gatewayId = entry.gatewayId;
    init.familyId = entry.familyId;
    init.gatewayName = entry.gatewayName;
    init.localIp = existing === undefined ? '' : existing.localIp;
    init.port = tls === undefined ? ProtocolConstants.DEFAULT_GATEWAY_PORT : tls.port;
    init.profile = tls === undefined ? TransportProfile.P_HMAC : TransportProfile.P_TLS_PIN;
    init.tlsEnabled = tls !== undefined;
    init.pins = tls === undefined ? [] : GatewayRepository.copyPins(tls.pins);
    init.pinAlg = tls === undefined ? '' : tls.pinAlg;
    init.keyId = ProtocolConstants.KEY_ID_V1;
    init.credentialAlias = StorageConstants.gatewayHmacAlias(entry.gatewayId);
    init.lastKnownIp = existing === undefined ? '' : existing.lastKnownIp;
    init.lastSeenAt = existing === undefined ? undefined : existing.lastSeenAt;
    init.createdAt = existing === undefined ? now : existing.createdAt;
    init.updatedAt = now;
    const route = GatewayRoute.create(init);

    const oldSecret = await this.tryReadSecret(route.credentialAlias);
    try {
      try {
        await this.secrets.put(route.credentialAlias, entry.commandSecret);
      } catch (error) {
        GatewayRepository.rethrow(error as Error);
      }
      try {
        await this.writeRoute(route);
      } catch (error) {
        await this.rollbackSecret(route.credentialAlias, oldSecret);
        throw AppErrors.of('STORAGE_RDB_ERROR', []);
      }
    } finally {
      if (oldSecret !== undefined) {
        oldSecret.destroy();
      }
    }
  }

  async updateLastKnownAddress(gatewayId: string, address: GatewayAddress): Promise<void> {
    this.ensureInitialized();
    const checked = GatewayRepository.requireGatewayId(gatewayId);
    const route = await this.readRoute(checked);
    if (route === undefined) {
      throw AppErrors.gateway('GATEWAY_NOT_BOUND', checked);
    }
    const now = DateTimeUtil.formatUtcCompact(this.clock.nowMs());
    await this.rdb.execute('UPDATE gw_route SET local_ip = ?, last_known_ip = ?, ' +
      'port = ?, updated_at = ? WHERE gateway_id = ?',
    [address.ip, address.ip, address.port, now, checked]);
  }

  async markSeen(gatewayId: string, atMs: number): Promise<void> {
    this.ensureInitialized();
    const checked = GatewayRepository.requireGatewayId(gatewayId);
    const route = await this.readRoute(checked);
    if (route === undefined) {
      throw AppErrors.gateway('GATEWAY_NOT_BOUND', checked);
    }
    if (!Number.isInteger(atMs) || atMs < 0) {
      throw AppErrors.protocol('PROTOCOL_VALUE_OUT_OF_RANGE', 'atMs');
    }
    const text = DateTimeUtil.formatUtcCompact(atMs);
    await this.rdb.execute('UPDATE gw_route SET last_seen_at = ?, updated_at = ? ' +
      'WHERE gateway_id = ?', [text, text, checked]);
  }

  // ---- Profile and pin rotation ------------------------------------------

  async setPersistentProfile(gatewayId: string, profile: TransportProfile): Promise<void> {
    this.ensureInitialized();
    const checked = GatewayRepository.requireGatewayId(gatewayId);
    if (profile === TransportProfile.P_BLOCKED) {
      // P-BLOCKED is a runtime-only failure state (ADR-002 §6.3).
      throw AppErrors.of('GATEWAY_PROFILE_BLOCKED', []);
    }
    const route = await this.readRoute(checked);
    if (route === undefined) {
      throw AppErrors.gateway('GATEWAY_NOT_BOUND', checked);
    }
    const now = DateTimeUtil.formatUtcCompact(this.clock.nowMs());
    if (profile === TransportProfile.P_HMAC) {
      await this.rdb.execute('UPDATE gw_route SET profile = ?, tls_enabled = ?, ' +
        'pins_json = ?, pin_alg = ?, port = ?, updated_at = ? WHERE gateway_id = ?',
      [TransportProfile.P_HMAC, 0, '[]', '', ProtocolConstants.DEFAULT_GATEWAY_PORT, now, checked]);
      return;
    }
    if (profile !== TransportProfile.P_TLS_PIN) {
      throw AppErrors.of('TLS_PROFILE_INCONSISTENT', []);
    }
    if (route.pins.length === 0) {
      throw AppErrors.of('TLS_PROFILE_INCONSISTENT', []);
    }
    for (let index = 0; index < route.pins.length; index++) {
      if (!ProtocolConstants.PIN_PATTERN.test(route.pins[index])) {
        throw AppErrors.of('TLS_PIN_CONFIG_INVALID', []);
      }
    }
    await this.rdb.execute('UPDATE gw_route SET profile = ?, tls_enabled = ?, ' +
      'pins_json = ?, pin_alg = ?, updated_at = ? WHERE gateway_id = ?',
    [TransportProfile.P_TLS_PIN, 1, GatewayRepository.serializePins(route.pins),
      'sha256-spki-der', now, checked]);
  }

  async pinVerified(gatewayId: string, matchedPin: string): Promise<void> {
    this.ensureInitialized();
    const checked = GatewayRepository.requireGatewayId(gatewayId);
    if (!ProtocolConstants.PIN_PATTERN.test(matchedPin)) {
      throw AppErrors.of('TLS_PIN_CONFIG_INVALID', []);
    }
    const route = await this.readRoute(checked);
    if (route === undefined) {
      throw AppErrors.gateway('GATEWAY_NOT_BOUND', checked);
    }
    if (route.profile !== TransportProfile.P_TLS_PIN) {
      throw AppErrors.of('TLS_PROFILE_INCONSISTENT', []);
    }
    let matched = false;
    for (let index = 0; index < route.pins.length; index++) {
      if (route.pins[index] === matchedPin) {
        matched = true;
        break;
      }
    }
    if (!matched) {
      // Cross-gateway/unknown pin: fail closed, keep the existing pins.
      throw AppErrors.of('TLS_PIN_CONFIG_INVALID', []);
    }
    if (route.pins.length === 1) {
      // Single-pin match is a successful verification no-op.
      return;
    }
    // ADR-002 §4.4: first success during the overlap window collapses the set.
    const now = DateTimeUtil.formatUtcCompact(this.clock.nowMs());
    const single: string[] = [matchedPin];
    await this.rdb.execute('UPDATE gw_route SET pins_json = ?, updated_at = ? ' +
      'WHERE gateway_id = ?', [GatewayRepository.serializePins(single), now, checked]);
  }

  async rotateSecret(gatewayId: string, newSecret: SecureBytes,
    verifier: SecretVerifier): Promise<void> {
    this.ensureInitialized();
    const checked = GatewayRepository.requireGatewayId(gatewayId);
    if (newSecret.length < 16 || newSecret.length > 4096) {
      throw AppErrors.of('CONFIGURATION_ERROR', [new NameValue('field', 'secret')]);
    }
    const route = await this.readRoute(checked);
    if (route === undefined) {
      throw AppErrors.gateway('GATEWAY_NOT_BOUND', checked);
    }
    const pendingAlias = StorageConstants.gatewayHmacPendingAlias(checked,
      this.newRotationId());
    SecretAlias.require(pendingAlias);
    await this.secrets.put(pendingAlias, newSecret);
    let verified = false;
    let verificationSecret: Uint8Array = new Uint8Array(0);
    try {
      verificationSecret = newSecret.withView(
        (view: Uint8Array): Uint8Array => BytesUtil.copyOf(view));
      verified = await verifier.verify(checked, verificationSecret);
    } catch (error) {
      await this.bestEffortRemoveSecret(pendingAlias);
      GatewayRepository.rethrow(error as Error);
    } finally {
      BytesUtil.zeroize(verificationSecret);
    }
    if (!verified) {
      await this.bestEffortRemoveSecret(pendingAlias);
      throw AppErrors.of('SIGNATURE_INVALID', []);
    }
    try {
      await this.secrets.put(route.credentialAlias, newSecret);
    } catch (error) {
      await this.bestEffortRemoveSecret(pendingAlias);
      GatewayRepository.rethrow(error as Error);
    }
    // Active value is now the new secret; pending cleanup is best effort and
    // initialize() retries it after a crash.
    await this.bestEffortRemoveSecret(pendingAlias);
  }

  async removeLocalBinding(gatewayId: string): Promise<void> {
    this.ensureInitialized();
    const checked = GatewayRepository.requireGatewayId(gatewayId);
    const route = await this.readRoute(checked);
    if (route === undefined) {
      throw AppErrors.gateway('GATEWAY_NOT_BOUND', checked);
    }
    try {
      await this.secrets.remove(route.credentialAlias);
    } catch (error) {
      if (!GatewayRepository.isCode(error as Error, 'ASSET_NOT_FOUND')) {
        GatewayRepository.rethrow(error as Error);
      }
    }
    const pendingPrefix = StorageConstants.ASSET_PREFIX_GATEWAY_HMAC_PENDING +
      checked + '.';
    const pending = await this.secrets.list(pendingPrefix);
    for (let index = 0; index < pending.length; index++) {
      await this.safeRemoveSecret(pending[index]);
    }
    await this.rdb.transaction<void>(async (tx: RdbTransaction): Promise<void> => {
      await tx.execute('DELETE FROM gw_sequence WHERE gateway_id = ?', [checked]);
      await tx.execute('DELETE FROM gw_route WHERE gateway_id = ?', [checked]);
    });
    // No transport dependency exists here by design: local unbinding never
    // contacts the physical gateway (SC-12).
  }

  // ---- Sequence -----------------------------------------------------------

  async nextSequence(gatewayId: string): Promise<number> {
    this.ensureInitialized();
    const checked = GatewayRepository.requireGatewayId(gatewayId);
    await this.requireBound(checked);
    return this.rdb.transaction<number>(async (tx: RdbTransaction): Promise<number> => {
      await GatewayRepository.ensureRouteRow(tx, checked);
      await GatewayRepository.ensureSequenceRow(tx, checked);
      const rows = await tx.query('SELECT next_seq FROM gw_sequence WHERE gateway_id = ?',
        [checked]);
      if (rows.length === 0) {
        throw AppErrors.of('STORAGE_RDB_ERROR', []);
      }
      const current = GatewayRepository.requiredNumber(rows[0], 'next_seq');
      if (!Number.isInteger(current) || current < 0 || current >= ProtocolConstants.MAX_SEQ) {
        // Exact retransmission is owned by C-17; without its in-flight view a
        // saturated counter must not silently wrap.
        throw AppErrors.of('CONFIGURATION_ERROR', [new NameValue('state', 'seq_exhausted')]);
      }
      await tx.execute('UPDATE gw_sequence SET next_seq = ? WHERE gateway_id = ?',
        [current + 1, checked]);
      return current;
    });
  }

  async peekSequence(gatewayId: string): Promise<number> {
    this.ensureInitialized();
    const checked = GatewayRepository.requireGatewayId(gatewayId);
    await this.requireBound(checked);
    const rows = await this.rdb.query('SELECT next_seq FROM gw_sequence WHERE gateway_id = ?',
      [checked]);
    if (rows.length === 0) {
      return 0;
    }
    return GatewayRepository.requiredNumber(rows[0], 'next_seq');
  }

  async resetSequenceIfIdle(gatewayId: string): Promise<number> {
    this.ensureInitialized();
    const checked = GatewayRepository.requireGatewayId(gatewayId);
    await this.requireBound(checked);
    return this.rdb.transaction<number>(async (tx: RdbTransaction): Promise<number> => {
      await GatewayRepository.ensureRouteRow(tx, checked);
      await GatewayRepository.ensureSequenceRow(tx, checked);
      await tx.execute('UPDATE gw_sequence SET next_seq = ? WHERE gateway_id = ?', [0, checked]);
      return 0;
    });
  }

  // ---- Credentials --------------------------------------------------------

  async withCommandSecret<T>(gatewayId: string,
    fn: (secret: Uint8Array) => Promise<T>): Promise<T> {
    this.ensureInitialized();
    const checked = GatewayRepository.requireGatewayId(gatewayId);
    const route = await this.readRoute(checked);
    if (route === undefined) {
      throw AppErrors.gateway('GATEWAY_NOT_BOUND', checked);
    }
    return this.secrets.withSecret(route.credentialAlias, fn);
  }

  async tlsMaterial(gatewayId: string): Promise<TlsMaterial | undefined> {
    this.ensureInitialized();
    const checked = GatewayRepository.requireGatewayId(gatewayId);
    const route = await this.readRoute(checked);
    if (route === undefined) {
      throw AppErrors.gateway('GATEWAY_NOT_BOUND', checked);
    }
    if (route.profile === TransportProfile.P_HMAC) {
      return undefined;
    }
    if (route.profile === TransportProfile.P_BLOCKED) {
      throw AppErrors.of('GATEWAY_PROFILE_BLOCKED', []);
    }
    if (route.pins.length === 0) {
      throw AppErrors.of('TLS_PROFILE_INCONSISTENT', []);
    }
    return new TlsMaterial(route.pins, route.port, route.pinAlg);
  }

  // ---- Internals ----------------------------------------------------------

  private buildRoute(result: BleProvisioningResult, familyId: string,
    existing: GatewayRoute | undefined): GatewayRoute {
    const identity = result.identity;
    const tls = identity.tls;
    const now = DateTimeUtil.formatUtcCompact(this.clock.nowMs());
    const init = new GatewayRouteInit();
    init.gatewayId = identity.gatewayId;
    init.familyId = familyId;
    init.gatewayName = identity.gatewayName;
    init.localIp = result.ip;
    init.port = tls === undefined ? ProtocolConstants.DEFAULT_GATEWAY_PORT : tls.port;
    init.profile = tls === undefined ? TransportProfile.P_HMAC : TransportProfile.P_TLS_PIN;
    init.tlsEnabled = tls !== undefined;
    init.pins = tls === undefined ? [] : GatewayRepository.copyPins(tls.pins);
    init.pinAlg = tls === undefined ? '' : tls.pinAlg;
    init.keyId = ProtocolConstants.KEY_ID_V1;
    init.credentialAlias = StorageConstants.gatewayHmacAlias(identity.gatewayId);
    init.lastKnownIp = result.ip;
    init.lastSeenAt = existing === undefined ? undefined : existing.lastSeenAt;
    init.createdAt = existing === undefined ? now : existing.createdAt;
    init.updatedAt = now;
    return GatewayRoute.create(init);
  }

  private async writeRoute(route: GatewayRoute): Promise<GatewayRoute> {
    const lastSeen: string | null = route.lastSeenAt === undefined ? null : route.lastSeenAt;
    await this.rdb.transaction<void>(async (tx: RdbTransaction): Promise<void> => {
      await tx.execute(INSERT_ROUTE, [
        route.gatewayId,
        route.familyId,
        route.gatewayName,
        route.localIp,
        route.port,
        route.profile,
        route.tlsEnabled ? 1 : 0,
        GatewayRepository.serializePins(route.pins),
        route.pinAlg,
        route.keyId,
        route.credentialAlias,
        route.lastKnownIp,
        lastSeen,
        route.createdAt,
        route.updatedAt
      ]);
    });
    return route;
  }

  private async readRoute(gatewayId: string): Promise<GatewayRoute | undefined> {
    const rows = await this.rdb.query(SELECT_ROUTES + ' WHERE gateway_id = ?', [gatewayId]);
    if (rows.length === 0) {
      return undefined;
    }
    return this.routeFromRow(rows[0]);
  }

  private routeFromRow(row: RdbRow): GatewayRoute {
    const cells = new RouteCells(row);
    const init = new GatewayRouteInit();
    init.gatewayId = cells.gatewayId;
    init.familyId = cells.familyId;
    init.gatewayName = cells.gatewayName;
    init.localIp = cells.localIp;
    init.port = cells.port;
    init.profile = GatewayRepository.parseProfile(cells.profile);
    init.tlsEnabled = cells.tlsEnabled === 1;
    init.pins = GatewayRepository.parsePins(cells.pinsJson);
    init.pinAlg = cells.pinAlg;
    init.keyId = cells.keyId;
    init.credentialAlias = cells.credentialAlias;
    init.lastKnownIp = cells.lastKnownIp;
    init.lastSeenAt = cells.lastSeenAt === null ? undefined : cells.lastSeenAt;
    init.createdAt = cells.createdAt;
    init.updatedAt = cells.updatedAt;
    return GatewayRoute.create(init);
  }

  private mapRoutes(rows: ReadonlyArray<RdbRow>): ReadonlyArray<GatewayRoute> {
    const routes: GatewayRoute[] = [];
    for (let index = 0; index < rows.length; index++) {
      routes.push(this.routeFromRow(rows[index]));
    }
    return routes;
  }

  private async probeSecret(alias: string): Promise<void> {
    try {
      await this.secrets.withSecret(alias, async (secret: Uint8Array): Promise<void> => {
        if (secret.length === 0) {
          throw AppErrors.of('SECRET_ENCODING_INVALID', []);
        }
      });
    } catch (error) {
      if (GatewayRepository.isCode(error as Error, 'ASSET_NOT_FOUND')) {
        throw AppErrors.of('PROVISIONING_CREDENTIAL_MISSING', []);
      }
      GatewayRepository.rethrow(error as Error);
    }
  }

  private async tryReadSecret(alias: string): Promise<SecureBytes | undefined> {
    try {
      let copy: Uint8Array = new Uint8Array(0);
      await this.secrets.withSecret(alias, async (secret: Uint8Array): Promise<void> => {
        copy = BytesUtil.copyOf(secret);
      });
      const result = SecureBytes.from(copy);
      BytesUtil.zeroize(copy);
      return result;
    } catch (error) {
      if (GatewayRepository.isCode(error as Error, 'ASSET_NOT_FOUND')) {
        return undefined;
      }
      GatewayRepository.rethrow(error as Error);
    }
  }

  private async rollbackSecret(alias: string, oldSecret: SecureBytes | undefined):
    Promise<void> {
    try {
      if (oldSecret !== undefined) {
        await this.secrets.put(alias, oldSecret);
        return;
      }
    } catch (error) {
      // Restoring the previous value failed. Fall through to fail-closed
      // deletion so the persisted route never points at an unverified secret.
    }
    try {
      await this.safeRemoveSecret(alias);
    } catch (error) {
      // The route write already failed; report the primary storage failure.
    }
  }

  private async safeRemoveSecret(alias: string): Promise<void> {
    try {
      await this.secrets.remove(alias);
    } catch (error) {
      if (!GatewayRepository.isCode(error as Error, 'ASSET_NOT_FOUND')) {
        GatewayRepository.rethrow(error as Error);
      }
    }
  }

  private async bestEffortRemoveSecret(alias: string): Promise<void> {
    try {
      await this.secrets.remove(alias);
    } catch (error) {
      // Rotation already reached a terminal state; initialize() retries cleanup.
    }
  }

  private async requireBound(gatewayId: string): Promise<void> {
    const route = await this.readRoute(gatewayId);
    if (route === undefined) {
      throw AppErrors.gateway('GATEWAY_NOT_BOUND', gatewayId);
    }
  }

  private static async ensureRouteRow(tx: RdbTransaction, gatewayId: string): Promise<void> {
    const rows = await tx.query('SELECT gateway_id FROM gw_route WHERE gateway_id = ?',
      [gatewayId]);
    if (rows.length === 0) {
      throw AppErrors.gateway('GATEWAY_NOT_BOUND', gatewayId);
    }
  }

  private static async ensureSequenceRow(tx: RdbTransaction, gatewayId: string): Promise<void> {
    await tx.execute('INSERT OR IGNORE INTO gw_sequence (gateway_id, next_seq) VALUES (?, ?)',
      [gatewayId, 0]);
  }

  private newRotationId(): string {
    const raw = this.ids.newId();
    let sanitized = '';
    for (let index = 0; index < raw.length && sanitized.length < 24; index++) {
      const code = raw.charCodeAt(index);
      if ((code >= 0x30 && code <= 0x39) || (code >= 0x41 && code <= 0x5A) ||
        (code >= 0x61 && code <= 0x7A)) {
        sanitized += raw.charAt(index);
      }
    }
    if (sanitized.length === 0) {
      sanitized = this.clock.nowMs().toString(36);
    }
    return sanitized;
  }

  private ensureInitialized(): void {
    if (!this.initialized) {
      throw AppErrors.of('STORAGE_NOT_INITIALIZED', []);
    }
  }

  private static requireGatewayId(gatewayId: string): string {
    if (gatewayId.length === 0 || gatewayId.length > ProtocolConstants.MAX_DEVICE_ID_LENGTH ||
      gatewayId.indexOf(':') >= 0 || !ProtocolConstants.DEVICE_ID_PATTERN.test(gatewayId)) {
      throw AppErrors.protocol('PROTOCOL_INVALID_IDENTIFIER', 'gatewayId');
    }
    return gatewayId;
  }

  private static parseProfile(value: string): TransportProfile {
    if (value === TransportProfile.P_HMAC) {
      return TransportProfile.P_HMAC;
    }
    if (value === TransportProfile.P_TLS_PIN) {
      return TransportProfile.P_TLS_PIN;
    }
    if (value === TransportProfile.P_BLOCKED) {
      throw AppErrors.of('GATEWAY_PROFILE_BLOCKED', []);
    }
    throw AppErrors.of('TLS_PROFILE_INCONSISTENT', []);
  }

  private static copyPins(pins: ReadonlyArray<string>): ReadonlyArray<string> {
    const copy: string[] = [];
    for (let index = 0; index < pins.length; index++) {
      copy.push(pins[index]);
    }
    return copy;
  }

  private static serializePins(pins: ReadonlyArray<string>): string {
    let json = '[';
    for (let index = 0; index < pins.length; index++) {
      if (index > 0) {
        json += ',';
      }
      json += '"' + pins[index] + '"';
    }
    return json + ']';
  }

  private static parsePins(pinsJson: string): ReadonlyArray<string> {
    let node: JsonNode;
    try {
      node = JsonParser.parse(pinsJson, new JsonLimits(4096, 2, 128));
    } catch (error) {
      throw AppErrors.of('STORAGE_RDB_ERROR', []);
    }
    if (node.kind !== JsonKind.ARRAY) {
      throw AppErrors.of('STORAGE_RDB_ERROR', []);
    }
    const pins: string[] = [];
    for (let index = 0; index < node.arrayValue.length; index++) {
      const item = node.arrayValue[index];
      if (item.kind !== JsonKind.STRING) {
        throw AppErrors.of('STORAGE_RDB_ERROR', []);
      }
      pins.push(item.stringValue);
    }
    return pins;
  }

  static requiredString(row: RdbRow, column: string): string {
    const value = row.get(column);
    if (typeof value !== 'string') {
      throw AppErrors.of('STORAGE_RDB_ERROR', []);
    }
    return value;
  }

  static optionalString(row: RdbRow, column: string): string | null {
    const value = row.get(column);
    if (value === null || value === undefined) {
      return null;
    }
    if (typeof value !== 'string') {
      throw AppErrors.of('STORAGE_RDB_ERROR', []);
    }
    return value;
  }

  static requiredNumber(row: RdbRow, column: string): number {
    const value = row.get(column);
    if (typeof value !== 'number' || !Number.isFinite(value)) {
      throw AppErrors.of('STORAGE_RDB_ERROR', []);
    }
    return value;
  }

  private static rethrow(error: Error): never {
    if (error instanceof AppError) {
      throw error;
    }
    throw AppErrors.of('INTERNAL_ERROR', []);
  }

  private static isCode(error: Error, code: string): boolean {
    const candidate = error as AppError;
    return candidate instanceof AppError && candidate.code === code;
  }

  private static storageError(error: Error): Error {
    if (error instanceof AppError) {
      return error;
    }
    return AppErrors.of('STORAGE_RDB_ERROR', []);
  }
}
