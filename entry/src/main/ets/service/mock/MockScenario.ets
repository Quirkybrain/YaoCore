/*
 * YaoCore C-20 Mock scenarios.
 * Producer: agent:implementation-engineer | Task: T-11 / wp-035-transport
 * Contract: DES-A §17.1, §17.2, §17.4
 *
 * TEST ONLY. These types and MockGatewayService/MockBleProvisioningClient must
 * never be imported by the production composition root (SC-11; DES-A §17.3).
 * The boundary is checked by entry/src/test/host/TransportBoundary.test.mjs.
 */
import { AppErrors } from '../../common/types/AppError';

export enum MockMode {
  NORMAL = 'normal',
  OFFLINE = 'offline',
  ACK_LOST = 'ack-lost',
  REPLAY = 'replay',
  TIMEOUT = 'timeout',
  DEV_ONLY = 'dev-only'
}

export enum MockTlsMode {
  DISABLED = 'disabled',
  PIN_MATCH = 'pin-match',
  PIN_MISMATCH = 'pin-mismatch',
  HANDSHAKE_FAIL = 'handshake-fail'
}

export class MockScenario {
  readonly mode: MockMode;
  readonly tlsMode: MockTlsMode;
  readonly seed: number;
  readonly latencyMs: number;
  readonly failAtAttempt: number;
  readonly resultCode?: number;
  readonly errorCode?: string;
  readonly idempotentReplay?: boolean;
  readonly omitReportedState?: boolean;
  readonly badSignature?: boolean;
  readonly badCorrelation?: boolean;

  constructor(mode: MockMode, tlsMode: MockTlsMode, seed: number = 1, latencyMs: number = 0,
    failAtAttempt: number = 0, resultCode?: number, errorCode?: string,
    idempotentReplay?: boolean, omitReportedState?: boolean, badSignature?: boolean,
    badCorrelation?: boolean) {
    if (!Number.isFinite(seed) || !Number.isInteger(latencyMs) || latencyMs < 0 ||
      !Number.isInteger(failAtAttempt) || failAtAttempt < 0) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    if (resultCode !== undefined && (!Number.isInteger(resultCode) || resultCode < 0 ||
      resultCode > 9999)) {
      throw AppErrors.of('CONFIGURATION_ERROR', []);
    }
    this.mode = mode;
    this.tlsMode = tlsMode;
    this.seed = seed;
    this.latencyMs = latencyMs;
    this.failAtAttempt = failAtAttempt;
    this.resultCode = resultCode;
    this.errorCode = errorCode;
    this.idempotentReplay = idempotentReplay;
    this.omitReportedState = omitReportedState;
    this.badSignature = badSignature;
    this.badCorrelation = badCorrelation;
  }

  static normal(): MockScenario {
    return new MockScenario(MockMode.NORMAL, MockTlsMode.DISABLED, 1, 0, 0);
  }

  static offline(): MockScenario {
    return new MockScenario(MockMode.OFFLINE, MockTlsMode.DISABLED, 1, 0, 0);
  }

  static ackLost(): MockScenario {
    return new MockScenario(MockMode.ACK_LOST, MockTlsMode.DISABLED, 1, 0, 0);
  }

  static replay(): MockScenario {
    return new MockScenario(MockMode.REPLAY, MockTlsMode.DISABLED, 1, 0, 0);
  }

  static timeout(): MockScenario {
    return new MockScenario(MockMode.TIMEOUT, MockTlsMode.DISABLED, 1, 6000, 0);
  }

  static devOnly(): MockScenario {
    return new MockScenario(MockMode.DEV_ONLY, MockTlsMode.DISABLED, 1, 0, 0);
  }

  static tlsPinMatch(): MockScenario {
    return new MockScenario(MockMode.NORMAL, MockTlsMode.PIN_MATCH, 1, 0, 0);
  }

  static tlsPinMismatch(): MockScenario {
    return new MockScenario(MockMode.NORMAL, MockTlsMode.PIN_MISMATCH, 1, 0, 0);
  }

  static tlsHandshakeFail(): MockScenario {
    return new MockScenario(MockMode.NORMAL, MockTlsMode.HANDSHAKE_FAIL, 1, 0, 0);
  }
}
