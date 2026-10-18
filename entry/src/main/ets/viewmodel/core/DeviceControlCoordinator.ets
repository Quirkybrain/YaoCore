/*
 * YaoCore C-21 DeviceControlCoordinator (LAN first, cloud fallback).
 * Producer: agent:implementation-engineer | Task: T-15 / wp-060-vm
 * Contract: DES-B §10.1.5, §10.3.1; CB §2.3; ADR-001 §2
 *
 * Fallback is intentionally narrow: only a LAN transport failure (gateway
 * unreachable, timeout, local request failure) may be retried through cloud
 * when the cloud transport is persistently CONFIGURED. Device errors,
 * security/profile errors, DEV-ONLY and cloud token failures never fall back,
 * and no cloud "accepted" result is treated as COMMITTED by itself.
 */
import { AppError, AppErrors } from '../../common/types/AppError';
import { NameValue } from '../../common/types/NameValue';
import type { ClockPort } from '../../common/types/Ports';
import type { LoggerPort } from '../../contracts/Ports';
import { DeviceControlCommand, StateVerification } from '../../model/ControlModels';
import type { DeviceCommandExecution, ControlApplyResult } from '../../model/DeviceRecord';
import { ControlApplyContext, DeviceCommandOptions } from '../../model/DeviceRecord';
import { DeviceRepository } from '../../repository/DeviceRepository';
import type { CloudConfigView } from '../../service/cloud/CloudModels';
import type { CloudControlOutcome } from '../../model/CloudControlModels';
import { CloudTransportState } from '../../service/cloud/CloudModels';
import { CloudService } from '../../service/cloud/CloudService';
import { DeviceCommandRunner } from '../../service/device/DeviceCommandRunner';

import { ControlExecution, ControlTransport } from '../../model/ControlExecution';
import type { DeviceControlCoordinatorPort } from '../../contracts/ControlPorts';

const FALLBACK_CODES: ReadonlyArray<string> = [
  'GATEWAY_UNREACHABLE',
  'GATEWAY_TIMEOUT',
  'LOCAL_REQUEST_FAILED'
];

export class DeviceControlCoordinator implements DeviceControlCoordinatorPort {
  private readonly lan: DeviceCommandRunner;
  private readonly cloud: CloudService;
  private readonly devices: DeviceRepository;
  private readonly clock: ClockPort;
  private readonly logger: LoggerPort;

  constructor(lan: DeviceCommandRunner, cloud: CloudService, devices: DeviceRepository,
    clock: ClockPort, logger: LoggerPort) {
    this.lan = lan;
    this.cloud = cloud;
    this.devices = devices;
    this.clock = clock;
    this.logger = logger;
  }

  async execute(command: DeviceControlCommand, familyId: string): Promise<ControlExecution> {
    const startedAtMs = this.clock.nowMs();
    const lan = await this.lan.run(command, new DeviceCommandOptions(familyId, true));
    if (lan.error === undefined || !DeviceControlCoordinator.shouldFallback(lan.error)) {
      return new ControlExecution(command, ControlTransport.LAN,
        this.clock.nowMs() - startedAtMs, lan.ackAccepted,
        DeviceControlCoordinator.verificationOf(undefined, lan.apply), lan, undefined, lan.apply,
        lan.error);
    }

    let cloudView: CloudConfigView;
    try {
      cloudView = await this.cloud.getState();
    } catch (error) {
      return new ControlExecution(command, ControlTransport.LAN,
        this.clock.nowMs() - startedAtMs, lan.ackAccepted,
        DeviceControlCoordinator.verificationOf(undefined, lan.apply), lan, undefined, lan.apply,
        lan.error);
    }
    if (cloudView.state !== CloudTransportState.CONFIGURED) {
      return new ControlExecution(command, ControlTransport.LAN,
        this.clock.nowMs() - startedAtMs, lan.ackAccepted,
        DeviceControlCoordinator.verificationOf(undefined, lan.apply), lan, undefined, lan.apply,
        lan.error);
    }

    this.logger.info('DeviceControlCoordinator', 'cloud_fallback',
      [new NameValue('gatewayId', command.gatewayId),
        new NameValue('code', lan.error.code)]);
    let cloudOutcome: CloudControlOutcome | undefined = undefined;
    let apply: ControlApplyResult | undefined = undefined;
    let error: AppError | undefined = undefined;
    try {
      cloudOutcome = await this.cloud.sendAndConfirm(command);
      if (cloudOutcome.executionAccepted && cloudOutcome.verdict.reportedState !== undefined) {
        const context = new ControlApplyContext(familyId, command.gatewayId, command.target,
          command.action, command.requestedAtMs, command.value);
        apply = await this.devices.applyCloudState(context, cloudOutcome.verdict.reportedState,
          cloudOutcome.verdict.stateVerification, cloudOutcome.receipt.requestId,
          cloudOutcome.receipt.seq, true);
      }
      if (cloudOutcome.error !== undefined) {
        error = cloudOutcome.error;
      }
    } catch (failure) {
      error = failure instanceof AppError ? failure as AppError : AppErrors.internal('cloudFallback');
    }
    const verification = DeviceControlCoordinator.verificationOf(
      cloudOutcome === undefined ? undefined : cloudOutcome.verdict.stateVerification, apply);
    return new ControlExecution(command, ControlTransport.CLOUD,
      this.clock.nowMs() - startedAtMs,
      cloudOutcome !== undefined && cloudOutcome.executionAccepted, verification,
      lan, cloudOutcome, apply, error);
  }

  static verificationOf(cloudVerification: StateVerification | undefined,
    apply: ControlApplyResult | undefined): StateVerification {
    if (apply !== undefined) {
      return apply.stateVerification;
    }
    if (cloudVerification !== undefined) {
      return cloudVerification;
    }
    return StateVerification.UNVERIFIED;
  }

  static verificationFor(execution: ControlExecution): StateVerification {
    if (execution.apply !== undefined) {
      return execution.apply.stateVerification;
    }
    if (execution.lan !== undefined && execution.lan.apply !== undefined) {
      return execution.lan.apply.stateVerification;
    }
    if (execution.cloud !== undefined) {
      return execution.cloud.verdict.stateVerification;
    }
    return StateVerification.UNVERIFIED;
  }

  static succeeded(execution: ControlExecution): boolean {
    return execution.error === undefined && execution.ackAccepted &&
      DeviceControlCoordinator.verificationFor(execution) !== StateVerification.MISMATCH;
  }

  private static shouldFallback(error: AppError): boolean {
    return FALLBACK_CODES.indexOf(error.code) >= 0;
  }
}
