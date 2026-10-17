/*
 * YaoCore C-10 DeviceCommandRunner.
 * Producer: agent:implementation-engineer | Task: T-09 / wp-024-domain
 * Contract: DES-B §5.1.4
 *
 * Prechecks the local SSOT, sends exactly one command through DeviceControlPort
 * (no platform import, no network code here), then applies the ACK state.
 * A rejected precheck never calls the port.
 *
 * T-11 F-04: the precheck now includes the DES-A §14.2.3 action x deviceType
 * matrix via ControlPolicy, so a direct C-10 command (e.g. door + SET_BRIGHTNESS)
 * is rejected locally instead of being sent to the gateway.
 */
import { AppError, AppErrors } from '../../common/types/AppError';
import { NameValue } from '../../common/types/NameValue';
import { DeviceAction } from '../../common/constants/DeviceConstants';
import type { ClockPort, LoggerPort, MetricsPort } from '../../common/types/Ports';
import { DeviceControlCommand, ControlOutcome } from '../../model/ControlModels';
import { DeviceKey } from '../../model/DeviceKey';
import { DeviceRepository } from '../../repository/DeviceRepository';
import type { DeviceControlPort } from '../../repository/DomainPorts';
import { ControlPolicy } from '../gateway/GatewayRequestPolicy';
import {
  ControlApplyContext,
  ControlApplyResult,
  DeviceCommandExecution,
  DeviceCommandOptions,
  DeviceRecord
} from '../../repository/DomainModels';

export class DeviceCommandRunner {
  private readonly port: DeviceControlPort;
  private readonly devices: DeviceRepository;
  private readonly clock: ClockPort;
  private readonly logger: LoggerPort;
  private readonly metrics: MetricsPort;

  constructor(port: DeviceControlPort, devices: DeviceRepository, clock: ClockPort,
    logger: LoggerPort, metrics: MetricsPort) {
    this.port = port;
    this.devices = devices;
    this.clock = clock;
    this.logger = logger;
    this.metrics = metrics;
  }

  async run(command: DeviceControlCommand,
    options?: DeviceCommandOptions): Promise<DeviceCommandExecution> {
    const startedAt = this.clock.nowMs();
    const gatewayAction = DeviceCommandRunner.isGatewayAction(command);
    const precheck = options === undefined ? true : options.precheck;
    let record: DeviceRecord | undefined = undefined;
    let familyId = options === undefined ? '' : options.familyId;
    if (!gatewayAction) {
      const key = new DeviceKey(command.gatewayId, command.target);
      record = await this.devices.getRecord(key);
      if (record === undefined && precheck) {
        if (await this.devices.isDismissed(key)) {
          return this.reject(command, startedAt, 'DEVICE_DISMISSED');
        }
        return this.reject(command, startedAt, 'DEVICE_NOT_FOUND');
      }
      if (record !== undefined) {
        if (precheck && familyId.length > 0 && record.state.familyId !== familyId) {
          return this.reject(command, startedAt, 'DEVICE_NOT_FOUND');
        }
        if (familyId.length === 0) {
          familyId = record.state.familyId;
        }
        if (precheck && !record.state.isEnabled) {
          return this.reject(command, startedAt, 'DEVICE_DISABLED');
        }
        if (precheck && record.state.isUnassigned) {
          return this.reject(command, startedAt, 'DEVICE_UNASSIGNED');
        }
        if (precheck && !record.isSupported) {
          // Read-only degraded device types never receive a command (D-011).
          return this.reject(command, startedAt, 'CONFIGURATION_ERROR');
        }
        if (precheck) {
          // DES-A §14.2.3 matrix: sensor/read-only and action != deviceType are
          // rejected before any transport call (T-11 F-04).
          try {
            ControlPolicy.validate(record.state.snapshot.deviceType, record.isSupported,
              command.action, command.value);
          } catch (failure) {
            const code = failure instanceof AppError ? failure.code : 'CONFIGURATION_ERROR';
            return this.reject(command, startedAt, code);
          }
        }
      }
    }

    let outcome: ControlOutcome | undefined = undefined;
    let apply: ControlApplyResult | undefined = undefined;
    let error: AppError | undefined = undefined;
    try {
      outcome = await this.port.send(command);
    } catch (failure) {
      error = failure instanceof AppError ? failure : AppErrors.of('INTERNAL_ERROR', []);
    }
    if (outcome !== undefined && !gatewayAction) {
      const context = new ControlApplyContext(familyId, command.gatewayId, command.target,
        command.action, command.requestedAtMs, command.value);
      try {
        apply = await this.devices.applyControlAck(context, outcome);
      } catch (failure) {
        // ACK accepted but state application failed: the VM must not show a
        // confirmed state (DES-B §5.1.4).
        error = failure instanceof AppError ? failure : AppErrors.of('INTERNAL_ERROR', []);
      }
    }
    const elapsed = this.clock.nowMs() - startedAt;
    this.metrics.record('device_control_ms', elapsed,
      [new NameValue('action', command.action)]);
    if (error !== undefined) {
      this.logger.warn('DeviceCommandRunner', 'control_failed',
        [new NameValue('gatewayId', command.gatewayId),
          new NameValue('action', command.action)]);
    }
    return new DeviceCommandExecution(command, elapsed,
      outcome !== undefined && outcome.ackAccepted, outcome, apply, error);
  }

  private reject(command: DeviceControlCommand, startedAt: number,
    code: string): DeviceCommandExecution {
    const elapsed = this.clock.nowMs() - startedAt;
    this.metrics.record('device_control_rejected_ms', elapsed,
      [new NameValue('code', code)]);
    return new DeviceCommandExecution(command, elapsed, false, undefined, undefined,
      AppErrors.of(code, [new NameValue('gatewayId', command.gatewayId)]));
  }

  private static isGatewayAction(command: DeviceControlCommand): boolean {
    if (command.target !== command.gatewayId) {
      return false;
    }
    return command.action === DeviceAction.BOARD_LED_ON ||
      command.action === DeviceAction.BOARD_LED_OFF ||
      command.action === DeviceAction.PING;
  }
}
