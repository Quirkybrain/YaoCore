/*
 * YaoCore Hypium host suite: C-03 ControlAckMapper.
 * Producer: agent:implementation-engineer | Task: T-06 / wp-012-foundation
 * Traceability: DES-A §6.1.4/§18.7; V-05/V-06; SEC-N09/N10.
 *
 * PUBLIC TEST DATA ONLY: embedded ACK golden from contract fixture.
 */
import { describe, expect, it } from '@ohos/hypium';
import { AckExpectation, ControlAckMapper } from '../../main/ets/service/protocol/ControlAckMapper';
import { DeviationCounter } from '../../main/ets/service/protocol/ProtocolDeviation';
import { DeviceAction } from '../../main/ets/common/constants/DeviceConstants';
import { StateVerification } from '../../main/ets/model/ControlModels';
import { Utf8 } from '../../main/ets/common/utils/Utf8';

const ACK: string = '{"request_id":"req-wp002-live-0001","seq":1,"result_code":0,' +
  '"message":"command executed by DEV simulator","server_time":"20261016T155534Z",' +
  '"reported_state":{"deviceId":"Light_01","online":true,"power":true,"brightness":42,' +
  '"updatedAt":"20261016T155534Z"}}';

const REPLAY: string = '{"request_id":"req-wp002-live-0001","seq":1,"result_code":0,' +
  '"message":"command executed by DEV simulator","server_time":"20261016T155534Z",' +
  '"reported_state":{"deviceId":"Light_01","online":true,"power":true,"brightness":42,' +
  '"updatedAt":"20261016T155534Z"},"idempotent_replay":true}';

export function ControlAckMapperSuite(): void {
  describe('C03 ControlAckMapper', () => {
    it('C03_ControlAckMapper_goldenIsAcceptedWithMatch', 0, () => {
      const outcome = ControlAckMapper.map(Utf8.encode(ACK),
        new AckExpectation('req-wp002-live-0001', 1, 'Light_01',
          DeviceAction.SET_BRIGHTNESS, 42, false), new DeviationCounter());
      expect(outcome.ackAccepted).assertTrue();
      expect(outcome.stateVerification).assertEqual(StateVerification.MATCH);
      expect(outcome.shouldApplyState).assertTrue();
      const reported = outcome.reportedState;
      expect(reported === undefined).assertFalse();
      if (reported !== undefined) {
        expect(reported.brightness).assertEqual(42);
      }
    });

    it('C03_ControlAckMapper_replayAlreadyAppliedDoesNotReapply', 0, () => {
      const outcome = ControlAckMapper.map(Utf8.encode(REPLAY),
        new AckExpectation('req-wp002-live-0001', 1, 'Light_01',
          DeviceAction.SET_BRIGHTNESS, 42, true), new DeviationCounter());
      expect(outcome.idempotentReplay).assertTrue();
      expect(outcome.ackAccepted).assertTrue();
      expect(outcome.shouldApplyState).assertFalse();
    });

    it('C03_ControlAckMapper_nonZeroResultIsNotSuccess', 0, () => {
      const outcome = ControlAckMapper.map(
        Utf8.encode('{"request_id":"req-x","seq":1,"result_code":1007,' +
          '"message":"offline","server_time":"20261017T120000Z"}'),
        new AckExpectation('req-x', 1, 'Light_01', DeviceAction.TURN_ON, undefined, false),
        new DeviationCounter());
      expect(outcome.ackAccepted).assertFalse();
      expect(outcome.gatewayResult.success).assertFalse();
      expect(outcome.gatewayResult.retryable).assertTrue();
    });

    it('C03_ControlAckMapper_missingReportedStateThrows', 0, () => {
      let code: string = '';
      try {
        ControlAckMapper.map(
          Utf8.encode('{"request_id":"req-x","seq":1,"result_code":0,' +
            '"message":"ok","server_time":"20261017T120000Z"}'),
          new AckExpectation('req-x', 1, 'Light_01', DeviceAction.TURN_ON, undefined, false),
          new DeviationCounter());
      } catch (error) {
        code = (error as Error).message;
      }
      expect(code).assertEqual('ACK_PROTOCOL_VIOLATION');
    });
  });
}
