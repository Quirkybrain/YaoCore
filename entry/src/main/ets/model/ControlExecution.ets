/*
 * YaoCore C-21 unified control execution result.
 * Producer: agent:implementation-engineer | Task: T-15/T-16 / wp-060-vm
 * Migrated: T-23 / wp-090-ports (2026-10-18) — DES-B §2.1 model/ControlExecution.ets;
 * the port DeviceControlCoordinatorPort returns this model type, so contracts/**
 * must not depend on viewmodel/**.
 * Contract: DES-B §10.1.1/§12.1
 *
 * Pure value object; no platform API.
 */
import type { AppError } from '../common/types/AppError';
import type { DeviceControlCommand, ControlOutcome, StateVerification } from './ControlModels';
import type { ControlApplyResult, DeviceCommandExecution } from './DeviceRecord';
import type { CloudControlOutcome } from './CloudControlModels';

export enum ControlTransport {
  LAN = 'LAN',
  CLOUD = 'CLOUD'
}

/** Unified LAN/cloud control result consumed by the ViewModels. */
export class ControlExecution {
  readonly command: DeviceControlCommand;
  readonly transport: ControlTransport;
  readonly lan?: DeviceCommandExecution;
  readonly cloud?: CloudControlOutcome;
  readonly apply?: ControlApplyResult;
  readonly error?: AppError;
  readonly elapsedMs: number;
  readonly ackAccepted: boolean;
  readonly stateVerification: StateVerification;

  constructor(command: DeviceControlCommand, transport: ControlTransport, elapsedMs: number,
    ackAccepted: boolean, stateVerification: StateVerification, lan?: DeviceCommandExecution,
    cloud?: CloudControlOutcome, apply?: ControlApplyResult, error?: AppError) {
    this.command = command;
    this.transport = transport;
    this.elapsedMs = elapsedMs;
    this.ackAccepted = ackAccepted;
    this.stateVerification = stateVerification;
    this.lan = lan;
    this.cloud = cloud;
    this.apply = apply;
    this.error = error;
  }
}
