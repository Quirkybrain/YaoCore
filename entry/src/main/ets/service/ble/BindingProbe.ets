/*
 * YaoCore C-19 binding probe (LAN identity + board LED confirmation).
 * Producer: agent:implementation-engineer | Task: T-12 / wp-040-ble
 * Contract: DES-A §16.8; BLE设计 §5-143; README L48-53; project-constraints
 *           PR-06/PR-13, SC-13/SC-14
 *
 * BLE success is never binding success. The probe requires a signed /discover
 * response whose gatewayId is byte-for-byte identical to the Security1
 * identity, the expected channel profile, and an executed board-LED ACK
 * (ackAccepted + boardLed=true + stateVerification=MATCH). Retries are finite
 * (ProbeBackoff, 5 attempts). A gatewayId mismatch is terminal and never
 * retried against a different candidate.
 */
import { AppErrors } from '../../common/types/AppError';
import { NameValue } from '../../common/types/NameValue';
import { StorageConstants } from '../../common/constants/StorageConstants';
import { ProtocolConstants } from '../../common/constants/ProtocolConstants';
import { BytesUtil } from '../../common/utils/BytesUtil';
import type { ClockPort, LoggerPort, CancellationToken } from '../../common/types/Ports';
import { DeviceAction } from '../../common/constants/DeviceConstants';
import { ControlOutcome, DeviceControlCommand, StateVerification } from '../../model/ControlModels';
import {
  BleProvisioningIdentity,
  ProvisioningTlsMaterial
} from '../../model/ProvisioningModels';
import { GatewayAddress, TlsMaterial } from '../../model/GatewayRoute';
import { TransportProfile } from '../../model/DeviceTypes';
import type { GatewayCredentialPort } from '../../repository/GatewayPorts';
import type { SecretDraftPort } from '../storage/SecretDraftPort';
import { SecureBytes } from '../../common/types/SecureBytes';
import { ProbeBackoff } from '../gateway/ProbeBackoff';
import {
  GatewayTarget,
  ProbeResult
} from '../gateway/GatewayTransportPorts';
import type { IGatewayClient } from '../gateway/GatewayTransportPorts';
import { defaultBleDelay, isCode, throwIfCancelled } from './BleSupport';
import type { BleDelay } from './BleSupport';

const MAX_PROBE_ATTEMPTS: number = 5;

export class BindingProbeOutcome {
  readonly credentialDraftId: string;
  readonly boardLedConfirmed: boolean;

  constructor(credentialDraftId: string, boardLedConfirmed: boolean) {
    this.credentialDraftId = credentialDraftId;
    this.boardLedConfirmed = boardLedConfirmed;
  }
}

/** Command-secret adapter over an already-resolved one-shot draft. */
export class DraftCredentialPort implements GatewayCredentialPort {
  private readonly secret: SecureBytes;
  private readonly tls?: ProvisioningTlsMaterial;

  constructor(secret: SecureBytes, tls?: ProvisioningTlsMaterial) {
    this.secret = secret;
    this.tls = tls;
  }

  async withCommandSecret<T>(gatewayId: string,
    fn: (secret: Uint8Array) => Promise<T>): Promise<T> {
    const copy = this.secret.withView((view: Uint8Array): Uint8Array => BytesUtil.copyOf(view));
    try {
      return await fn(copy);
    } finally {
      BytesUtil.zeroize(copy);
    }
  }

  async tlsMaterial(gatewayId: string): Promise<TlsMaterial | undefined> {
    if (this.tls === undefined) {
      return undefined;
    }
    return new TlsMaterial(this.tls.pins, this.tls.port, this.tls.pinAlg);
  }

  destroy(): void {
    this.secret.destroy();
  }
}

/**
 * Lazily consumes a draft on first probe use. The draft is re-issued under a
 * fresh id only after a fully successful probe; C-07 then consumes the new id
 * in commitBinding. On failure/cancel the secret is destroyed and never
 * persisted. This keeps SecretDraftPort's one-shot semantics intact without
 * mutating the C-06 port for a non-consuming peek.
 */
class LazyDraftCredentialPort implements GatewayCredentialPort {
  private readonly drafts: SecretDraftPort;
  private readonly draftId: string;
  private readonly tls?: ProvisioningTlsMaterial;
  private taken: SecureBytes | undefined = undefined;

  constructor(drafts: SecretDraftPort, draftId: string, tls?: ProvisioningTlsMaterial) {
    this.drafts = drafts;
    this.draftId = draftId;
    this.tls = tls;
  }

  async withCommandSecret<T>(gatewayId: string,
    fn: (secret: Uint8Array) => Promise<T>): Promise<T> {
    const resolved = this.resolve();
    const copy = resolved.withView((view: Uint8Array): Uint8Array => BytesUtil.copyOf(view));
    try {
      return await fn(copy);
    } finally {
      BytesUtil.zeroize(copy);
    }
  }

  async tlsMaterial(gatewayId: string): Promise<TlsMaterial | undefined> {
    if (this.tls === undefined) {
      return undefined;
    }
    return new TlsMaterial(this.tls.pins, this.tls.port, this.tls.pinAlg);
  }

  /** Consumes the original draft id and returns a fresh id for C-07. */
  reissue(): string {
    const resolved = this.resolve();
    const newId = this.drafts.put(resolved);
    resolved.destroy();
    this.taken = undefined;
    return newId;
  }

  destroy(): void {
    if (this.taken !== undefined) {
      this.taken.destroy();
      this.taken = undefined;
    }
  }

  private resolve(): SecureBytes {
    if (this.taken === undefined) {
      this.taken = this.drafts.take(this.draftId);
    }
    return this.taken;
  }
}

export class BindingProber {
  private readonly gatewayClient: IGatewayClient;
  private readonly credentials: GatewayCredentialPort;
  private readonly clock: ClockPort;
  private readonly logger?: LoggerPort;
  private readonly delay: BleDelay;

  constructor(gatewayClient: IGatewayClient, credentials: GatewayCredentialPort,
    clock: ClockPort, logger?: LoggerPort, delay: BleDelay = defaultBleDelay) {
    this.gatewayClient = gatewayClient;
    this.credentials = credentials;
    this.clock = clock;
    this.logger = logger;
    this.delay = delay;
  }

  async probe(identity: BleProvisioningIdentity, ip: string, familyId: string,
    draftId: string | undefined, drafts: SecretDraftPort,
    cancellation?: CancellationToken): Promise<BindingProbeOutcome> {
    if (familyId.length === 0 || familyId.length > 63) {
      throw AppErrors.of('CONFIGURATION_ERROR', [new NameValue('field', 'familyId')]);
    }
    const profile = identity.tls === undefined ? TransportProfile.P_HMAC : TransportProfile.P_TLS_PIN;
    const port = identity.tls === undefined ? ProtocolConstants.DEFAULT_GATEWAY_PORT :
      identity.tls.port;
    const pins: ReadonlyArray<string> = identity.tls === undefined ? [] : identity.tls.pins;
    const target = new GatewayTarget(identity.gatewayId, familyId, new GatewayAddress(ip, port),
      profile, pins, port, StorageConstants.gatewayHmacAlias(identity.gatewayId));

    const draftPort = (draftId !== undefined && draftId.length > 0) ?
      new LazyDraftCredentialPort(drafts, draftId, identity.tls) : undefined;
    const probeCredentials: GatewayCredentialPort = draftPort === undefined ?
      this.credentials : draftPort;
    const backoff = ProbeBackoff.forBindingProbe();
    // Hard total budget (DES-A §16.8-4123 / §19): 5 attempts with
    // 500/1000/2000/4000 ms between them must finish within 30s.
    const deadline = this.clock.nowMs() + ProbeBackoff.bindingProbeTotalBudgetMs();
    try {
      let verified = false;
      for (let attempt = 1; attempt <= MAX_PROBE_ATTEMPTS; attempt++) {
        throwIfCancelled(cancellation);
        if (this.clock.nowMs() >= deadline) {
          throw AppErrors.of('PROVISIONING_BINDING_PROBE_FAILED', []);
        }
        if (attempt > 1) {
          // ProbeBackoff is 1-based: the first retry waits 500ms (attempt - 1).
          const delayMs = backoff.nextDelayMs(attempt - 1);
          if (this.clock.nowMs() + delayMs > deadline) {
            throw AppErrors.of('PROVISIONING_BINDING_PROBE_FAILED', []);
          }
          await Promise.resolve(this.delay(delayMs));
          throwIfCancelled(cancellation);
        }
        try {
          const result = await this.gatewayClient.probe(target, probeCredentials);
          this.verifyProbeResult(result, identity, profile);
          verified = true;
          break;
        } catch (error) {
          const typed = error as Error;
          if (isCode(typed, 'PROVISIONING_BINDING_IDENTITY_MISMATCH') ||
            isCode(typed, 'GATEWAY_ID_MISMATCH')) {
            throw AppErrors.of('PROVISIONING_BINDING_IDENTITY_MISMATCH',
              [new NameValue('gatewayId', identity.gatewayId)]);
          }
          if (isCode(typed, 'PROVISIONING_CANCELLED') ||
            isCode(typed, 'PROVISIONING_CREDENTIAL_MISSING') ||
            isCode(typed, 'PROVISIONING_SECRET_DRAFT_EXPIRED')) {
            throw typed;
          }
          if (isCode(typed, 'GATEWAY_NOT_BOUND') || isCode(typed, 'ASSET_NOT_FOUND')) {
            throw AppErrors.of('PROVISIONING_CREDENTIAL_MISSING', []);
          }
          if (attempt === MAX_PROBE_ATTEMPTS) {
            throw AppErrors.of('PROVISIONING_BINDING_PROBE_FAILED', []);
          }
        }
      }
      if (!verified) {
        throw AppErrors.of('PROVISIONING_BINDING_PROBE_FAILED', []);
      }
      throwIfCancelled(cancellation);
      await this.confirmBoardLed(target, identity, cancellation);
      const issuedDraftId = draftPort === undefined ? '' : draftPort.reissue();
      return new BindingProbeOutcome(issuedDraftId, true);
    } catch (error) {
      if (draftPort !== undefined) {
        draftPort.destroy();
      }
      throw error as Error;
    }
  }

  private verifyProbeResult(result: ProbeResult, identity: BleProvisioningIdentity,
    profile: TransportProfile): void {
    if (!result.reachable) {
      throw AppErrors.of('PROVISIONING_BINDING_PROBE_FAILED', []);
    }
    if (result.gatewayId !== identity.gatewayId) {
      throw AppErrors.of('PROVISIONING_BINDING_IDENTITY_MISMATCH',
        [new NameValue('gatewayId', identity.gatewayId)]);
    }
    if (result.snapshot === undefined || result.snapshot.gatewayId !== identity.gatewayId) {
      throw AppErrors.of('PROVISIONING_BINDING_IDENTITY_MISMATCH',
        [new NameValue('gatewayId', identity.gatewayId)]);
    }
    if (result.profile !== profile) {
      throw AppErrors.of('PROVISIONING_BINDING_IDENTITY_MISMATCH',
        [new NameValue('field', 'profile')]);
    }
    if (profile === TransportProfile.P_TLS_PIN) {
      if (identity.tls === undefined || result.tlsPinMatched === undefined ||
        identity.tls.pins.indexOf(result.tlsPinMatched) < 0) {
        throw AppErrors.of('PROVISIONING_BINDING_PROBE_FAILED', []);
      }
    }
  }

  private async confirmBoardLed(target: GatewayTarget, identity: BleProvisioningIdentity,
    cancellation?: CancellationToken): Promise<void> {
    throwIfCancelled(cancellation);
    const command = new DeviceControlCommand(identity.gatewayId, identity.gatewayId,
      DeviceAction.BOARD_LED_ON, this.clock.nowMs(), true);
    let outcome: ControlOutcome;
    try {
      outcome = await this.gatewayClient.control(target, command);
    } catch (error) {
      throw AppErrors.of('PROVISIONING_BOARD_LED_UNCONFIRMED', []);
    }
    if (!outcome.ackAccepted || outcome.gatewayBoardState === undefined ||
      outcome.gatewayBoardState.gatewayId !== identity.gatewayId ||
      !outcome.gatewayBoardState.boardLed ||
      outcome.stateVerification !== StateVerification.MATCH) {
      throw AppErrors.of('PROVISIONING_BOARD_LED_UNCONFIRMED', []);
    }
    // Best-effort reset; a failure does not invalidate the confirmed binding.
    try {
      const reset = new DeviceControlCommand(identity.gatewayId, identity.gatewayId,
        DeviceAction.BOARD_LED_OFF, this.clock.nowMs(), false);
      await this.gatewayClient.control(target, reset);
    } catch (error) {
      if (this.logger !== undefined) {
        this.logger.warn('BleProvisioning', 'board LED reset failed',
          [new NameValue('gatewayId', identity.gatewayId)]);
      }
    }
  }
}
