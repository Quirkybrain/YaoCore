/*
 * YaoCore Hypium host suite: C-03 StateReportMapper.
 * Producer: agent:implementation-engineer | Task: T-06 / wp-012-foundation
 * Traceability: DES-B §8.1.5/§8.3.3; D-014 fixed property paths.
 */
import { describe, expect, it } from '@ohos/hypium';
import { StateReportMapper, ShadowMapContext } from '../../main/ets/service/protocol/StateReportMapper';
import { Utf8 } from '../../main/ets/common/utils/Utf8';

const REPORT: string = '{"services":[{"service_id":"SmartHomeService","properties":{' +
  '"Door_01_Online":true,"Door_01_Status":"OPEN",' +
  '"Light_01_Online":true,"Light_01_Status":"ON","Light_01_Brightness":68,' +
  '"Sensor_01_Online":true,"Room_01_Temperature":26.8,"Room_01_Humidity":58,' +
  '"Presence_01_Online":true,"Presence_01_Detected":false,' +
  '"AC_01_Online":true,"AC_01_Status":"ON","AC_01_TargetTemp":24,"AC_01_Mode":"COOL",' +
  '"Gateway_Online":true,"Gateway_RSSI":-55},"event_time":"20261017T120000Z"}]}';

export function StateReportMapperSuite(): void {
  describe('C03 StateReportMapper', () => {
    it('C03_StateReportMapper_servicesShapeMapsFixedPaths', 0, () => {
      const snapshot = StateReportMapper.map(Utf8.encode(REPORT),
        new ShadowMapContext('gw-device-1', Date.UTC(2026, 9, 17, 12, 0, 1)));
      expect(snapshot.shape).assertEqual('SERVICES');
      expect(snapshot.devices.length).assertEqual(5);
      expect(snapshot.gatewayOnline).assertTrue();
      expect(snapshot.devices[0].open).assertTrue();
      expect(snapshot.devices[1].brightness).assertEqual(68);
      expect(snapshot.devices[2].temperature).assertEqual(26.8);
      expect(snapshot.devices[4].mode).assertEqual('COOL');
    });

    it('C03_StateReportMapper_unknownShapeFailsClosed', 0, () => {
      let code: string = '';
      try {
        StateReportMapper.map(Utf8.encode('{"foo":1}'),
          new ShadowMapContext('gw-device-1', Date.UTC(2026, 9, 17, 12, 0, 1)));
      } catch (error) {
        code = (error as Error).message;
      }
      expect(code).assertEqual('CLOUD_SHADOW_INVALID');
    });
  });
}
