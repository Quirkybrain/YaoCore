/*
 * YaoCore C-01..C-03 device-side test skeleton.
 * Producer: agent:implementation-engineer | Task: T-06 / wp-012-foundation
 *
 * STATUS: BLOCKED — the current environment has no device/emulator and no
 * signing config, so `onDeviceTest` cannot run. This file exists to compile
 * the device-side verification path; it must not be reported as PASS.
 *
 * Public test data only. No secrets, no @ohos platform crypto here.
 */
import { describe, expect, it } from '@ohos/hypium';
import { Utf8 } from '../../../../main/ets/common/utils/Utf8';
import { DeviceAction } from '../../../../main/ets/common/constants/DeviceConstants';
import { DiscoverMapContext, DiscoverMapper } from '../../../../main/ets/service/protocol/DiscoverMapper';
import { DeviationCounter } from '../../../../main/ets/service/protocol/ProtocolDeviation';
import { AckExpectation, ControlAckMapper } from '../../../../main/ets/service/protocol/ControlAckMapper';
import { ShadowMapContext, StateReportMapper } from '../../../../main/ets/service/protocol/StateReportMapper';
import { StateVerification } from '../../../../main/ets/model/ControlModels';

const DISCOVER: string = '{"protocolVersion":"2.0","gatewayId":"gateway_01",' +
  '"gatewayName":"YaoCore DEV Contract Simulator","serviceId":"SmartHomeService",' +
  '"generatedAt":"20261016T155534Z","security":{"alg":"HMAC-SHA256","keyId":"app-key-v1",' +
  '"timeWindowSeconds":120,"nonceTtlSeconds":300},"devices":[{"deviceId":"Light_01",' +
  '"deviceName":"客厅灯光","roomName":"客厅","deviceType":"light","online":true,' +
  '"power":true,"brightness":68,"updatedAt":"20261016T155533Z"}]}';

const ACK: string = '{"request_id":"req-wp002-live-0001","seq":1,"result_code":0,' +
  '"message":"command executed by DEV simulator","server_time":"20261016T155534Z",' +
  '"reported_state":{"deviceId":"Light_01","online":true,"power":true,"brightness":42,' +
  '"updatedAt":"20261016T155534Z"}}';

const REPORT: string = '{"services":[{"service_id":"SmartHomeService","properties":{' +
  '"Light_01_Online":true,"Light_01_Status":"ON","Light_01_Brightness":68,' +
  '"Gateway_Online":true,"Gateway_RSSI":-55},"event_time":"20261017T120000Z"}]}';

export default function foundationDeviceTest() {
  describe('BLOCKED_ON_DEVICE_RUNNER C01..C03 foundation', () => {
    it('C03_DiscoverMapper_goldenIsMapped', 0, () => {
      const snapshot = DiscoverMapper.map(Utf8.encode(DISCOVER),
        new DiscoverMapContext(undefined, 0), new DeviationCounter());
      expect(snapshot.devices.length).assertEqual(1);
      expect(snapshot.devices[0].brightness).assertEqual(68);
    });

    it('C03_ControlAckMapper_goldenIsAccepted', 0, () => {
      const outcome = ControlAckMapper.map(Utf8.encode(ACK),
        new AckExpectation('req-wp002-live-0001', 1, 'Light_01',
          DeviceAction.SET_BRIGHTNESS, 42, false), new DeviationCounter());
      expect(outcome.ackAccepted).assertTrue();
      expect(outcome.stateVerification).assertEqual(StateVerification.MATCH);
    });

    it('C03_StateReportMapper_fixedPathIsMapped', 0, () => {
      const snapshot = StateReportMapper.map(Utf8.encode(REPORT),
        new ShadowMapContext('gw-device-1', Date.UTC(2026, 9, 17, 12, 0, 1)));
      expect(snapshot.devices.length).assertEqual(1);
      expect(snapshot.devices[0].brightness).assertEqual(68);
    });
  });
}
