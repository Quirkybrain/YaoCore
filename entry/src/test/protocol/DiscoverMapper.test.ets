/*
 * YaoCore Hypium host suite: C-03 DiscoverMapper.
 * Producer: agent:implementation-engineer | Task: T-06 / wp-012-foundation
 * Traceability: DES-A §6.1.2/§6.3; V-04.
 *
 * PUBLIC TEST DATA ONLY: the embedded golden is copied from
 * entry/src/ohosTest/ets/test/contract/fixtures/discover-response.json.
 */
import { describe, expect, it } from '@ohos/hypium';
import { DiscoverMapContext, DiscoverMapper } from '../../main/ets/service/protocol/DiscoverMapper';
import { DeviationCounter } from '../../main/ets/service/protocol/ProtocolDeviation';
import { DeviationCode } from '../../main/ets/common/types/ProtocolDeviation';
import { Utf8 } from '../../main/ets/common/utils/Utf8';

const GOLDEN: string = '{"protocolVersion":"2.0","gatewayId":"gateway_01",' +
  '"gatewayName":"YaoCore DEV Contract Simulator","serviceId":"SmartHomeService",' +
  '"generatedAt":"20261016T155534Z","security":{"alg":"HMAC-SHA256","keyId":"app-key-v1",' +
  '"timeWindowSeconds":120,"nonceTtlSeconds":300},"devices":[' +
  '{"deviceId":"Door_01","deviceName":"智能门禁","roomName":"玄关","deviceType":"door",' +
  '"brand":"YaoCore-Simulator","online":true,"open":false,"updatedAt":"20261016T155533Z"},' +
  '{"deviceId":"Light_01","deviceName":"客厅灯光","roomName":"客厅","deviceType":"light",' +
  '"brand":"YaoCore-Simulator","online":true,"power":true,"brightness":68,' +
  '"updatedAt":"20261016T155533Z"},' +
  '{"deviceId":"Sensor_01","deviceName":"温湿度传感器","roomName":"客厅","deviceType":"sensor",' +
  '"brand":"YaoCore-Simulator","online":true,"temperature":26.8,"humidity":58,' +
  '"updatedAt":"20261016T155533Z"},' +
  '{"deviceId":"AC_01","deviceName":"客厅空调","roomName":"客厅","deviceType":"ac",' +
  '"brand":"YaoCore-Simulator","online":true,"power":true,"targetTemp":24,"mode":"COOL",' +
  '"updatedAt":"20261016T155533Z"}]}';

const ALIAS: string = '{"protocolVersion":"2.0","gatewayId":"gw_01","gatewayName":"GW",' +
  '"serviceId":"SmartHomeService","generatedAt":"20261017T120000Z",' +
  '"security":{"alg":"HMAC-SHA256","keyId":"app-key-v1","timeWindowSeconds":120,' +
  '"nonceTtlSeconds":300},"devices":[{"deviceId":"Light_01","deviceName":"Light",' +
  '"roomName":"Living","deviceType":"light","isOnline":true,"powerStatus":true,' +
  '"success":true,"updatedAt":"20261017T120000Z"}]}';

export function DiscoverMapperSuite(): void {
  describe('C03 DiscoverMapper', () => {
    it('C03_DiscoverMapper_goldenMapsFourDevices', 0, () => {
      const counter = new DeviationCounter();
      const snapshot = DiscoverMapper.map(Utf8.encode(GOLDEN),
        new DiscoverMapContext(undefined, 0), counter);
      expect(snapshot.gatewayId).assertEqual('gateway_01');
      expect(snapshot.devices.length).assertEqual(4);
      expect(snapshot.isPartial).assertFalse();
      expect(counter.total()).assertEqual(0);
      expect(snapshot.devices[3].deviceId).assertEqual('AC_01');
      expect(snapshot.devices[3].targetTemperature).assertEqual(24);
      expect(snapshot.devices[3].modeStandard).assertTrue();
    });

    it('C03_DiscoverMapper_aliasFallbackCountsDeviations', 0, () => {
      const counter = new DeviationCounter();
      const snapshot = DiscoverMapper.map(Utf8.encode(ALIAS),
        new DiscoverMapContext(undefined, 0), counter);
      expect(snapshot.devices[0].isOnline).assertTrue();
      expect(snapshot.devices[0].powerStatus).assertTrue();
      expect(snapshot.isPartial).assertFalse();
      expect(snapshot.aliasUsed).assertTrue();
      expect(counter.counts().get(DeviationCode.ALIAS_FIELD_USED)).assertEqual(2);
      expect(counter.counts().get(DeviationCode.SUCCESS_FIELD_IGNORED)).assertEqual(1);
    });

    it('C03_DiscoverMapper_invalidEnvelopeFailsClosed', 0, () => {
      let code: string = '';
      try {
        DiscoverMapper.map(Utf8.encode('{"a":1,"a":2}'),
          new DiscoverMapContext(undefined, 0), new DeviationCounter());
      } catch (error) {
        code = (error as Error).message;
      }
      expect(code).assertEqual('PROTOCOL_DUPLICATE_KEY');
    });
  });
}
