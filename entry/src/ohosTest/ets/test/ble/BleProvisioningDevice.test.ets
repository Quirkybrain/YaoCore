/*
 * YaoCore C-19 BLE provisioning device-side skeleton.
 * Producer: agent:implementation-engineer | Task: T-12 / wp-040-ble
 * Contract: DES-A §16.2/§16.4/§16.5/§16.6; BLE设计 §4/§5;
 *           TEST-001 V-10/V-11; project-constraints CP-03.
 *
 * STATUS: COMPILED_ONLY / BLOCKED_ON_DEVICE_RUNNER.
 * This environment has no device/emulator/signing config. The suite is
 * registered so a future device run executes:
 * - the frozen step0/protobuf vectors,
 * - 0x2901 endpoint mapping,
 * - v2.0 identity fail-closed,
 * - a full Security1 handshake against a test-side gateway using the real
 *   platform X25519/SHA-256/AES-256-CTR implementation,
 * - construction of the production OhosBleTransport adapter.
 * It must never be reported as PASS from the host Node runner.
 *
 * PUBLIC TEST DATA ONLY.
 */
import { describe, expect, it } from '@ohos/hypium';
import { CryptoService } from '../../../../main/ets/service/crypto/CryptoService';
import { OhosCryptoProvider } from '../../../../main/ets/service/crypto/OhosCryptoProvider';
import { BytesUtil } from '../../../../main/ets/common/utils/BytesUtil';
import { ProtobufReader, ProtobufWriter } from '../../../../main/ets/service/ble/Protobuf';
import { ProtocommCodec } from '../../../../main/ets/service/ble/ProtocommCodec';
import {
  BleCharacteristicRef,
  BlePermissionGate
} from '../../../../main/ets/service/ble/BleProvisioningPorts';
import { GattEndpointMap } from '../../../../main/ets/service/ble/GattEndpointMap';
import {
  Security1Session,
  Security1State
} from '../../../../main/ets/service/ble/Security1Session';
import { IdentityNegotiator } from '../../../../main/ets/service/ble/IdentityNegotiator';
import { OhosBleTransport } from '../../../../main/ets/service/ble/adapters/OhosBleTransport';
import type { RandomPort } from '../../../../main/ets/common/types/Ports';

const provider: OhosCryptoProvider = new OhosCryptoProvider();
const crypto: CryptoService = new CryptoService(provider);

class DeviceTestRandom implements RandomPort {
  async nextBytes(length: number): Promise<Uint8Array> {
    return new Uint8Array(length).fill(7);
  }
}

class NoopPermissionGate implements BlePermissionGate {
  async ensurePermission(): Promise<void> {
  }
}

function requireBytes(payload: Uint8Array, fieldNumber: number): Uint8Array {
  const reader = new ProtobufReader(payload);
  while (reader.hasMore()) {
    const tag = reader.readTag();
    if (tag.fieldNumber === fieldNumber && tag.wireType === 2) {
      return reader.readBytes();
    }
    reader.skip(tag);
  }
  throw new Error('required protobuf field missing');
}

function encodeSessionResponse0(devicePublic: Uint8Array,
  deviceRandom: Uint8Array): Uint8Array {
  const response = new ProtobufWriter();
  response.varint(1, 0);
  response.bytes(2, devicePublic);
  response.bytes(3, deviceRandom);
  const sec1 = new ProtobufWriter();
  sec1.varint(1, 1);
  sec1.message(21, response);
  const session = new ProtobufWriter();
  session.varint(2, 1);
  session.message(11, sec1);
  return session.toBytes();
}

function encodeSessionResponse1(deviceVerify: Uint8Array): Uint8Array {
  const response = new ProtobufWriter();
  response.varint(1, 0);
  response.bytes(3, deviceVerify);
  const sec1 = new ProtobufWriter();
  sec1.varint(1, 3);
  sec1.message(23, response);
  const session = new ProtobufWriter();
  session.varint(2, 1);
  session.message(11, sec1);
  return session.toBytes();
}

export default function bleProvisioningDeviceTest() {
  describe('BLOCKED_ON_DEVICE_RUNNER C19 BLE provisioning', () => {
    it('C19_ProtocommCodec_step0FrozenVector', 0, () => {
      const publicKey = new Uint8Array(32);
      for (let index = 0; index < 32; index++) {
        publicKey[index] = index;
      }
      expect(BytesUtil.hexLower(ProtocommCodec.encodeSessionDataStep0(publicKey)))
        .assertEqual('10015a25a201220a20000102030405060708090a0b0c0d0e0f10' +
          '1112131415161718191a1b1c1d1e1f');
      expect(BytesUtil.hexLower(ProtocommCodec.encodeGetStatus())).assertEqual('5200');
      expect(BytesUtil.hexLower(ProtocommCodec.encodeApplyConfig())).assertEqual('08047200');
      expect(BytesUtil.hexLower(ProtocommCodec.encodeScanStart()))
        .assertEqual('52080801100018002078');
    });

    it('C19_GattEndpointMap_usesOnly2901Descriptions', 0, () => {
      const serviceUuid = GattEndpointMap.SERVICE_UUID;
      const names: string[] = ['proto-ver', 'prov-session', 'prov-scan', 'prov-config',
        'prov-ctrl', 'yaocore-id', 'yaocore-done'];
      const characteristics: BleCharacteristicRef[] = [];
      const descriptors: Map<string, Uint8Array> = new Map<string, Uint8Array>();
      for (let index = 0; index < names.length; index++) {
        const characteristic = new BleCharacteristicRef(serviceUuid, 'char-' + names[index],
          true, true, false);
        characteristics.push(characteristic);
        descriptors.set(serviceUuid + '|char-' + names[index],
          BytesUtil.utf8(names[index] + '\u0000'));
      }
      const map = GattEndpointMap.build(characteristics, descriptors);
      expect(map.get('proto-ver').characteristicUuid).assertEqual('char-proto-ver');
      expect(map.get('yaocore-id').characteristicUuid).assertEqual('char-yaocore-id');
      expect(map.requiresDoneEndpoint()).assertTrue();
    });

    it('C19_IdentityNegotiator_v20ExtraFieldFailsClosed', 0, () => {
      const payload = BytesUtil.utf8('{"protocolVersion":"2.0",' +
        '"serviceId":"YaoCoreGateway","gatewayId":"gateway_01",' +
        '"gatewayName":"Gateway","extra":true}');
      let code = '';
      try {
        new IdentityNegotiator().parseV20(payload);
      } catch (error) {
        code = (error as Error).message;
      }
      expect(code).assertEqual('PROVISIONING_IDENTITY_INVALID');
    });

    it('C19_Security1_fullHandshakeWithPlatformCrypto', 0, async () => {
      const pop = BytesUtil.utf8('device-pop');
      const session = new Security1Session(crypto, new DeviceTestRandom(), pop);
      const step0 = await session.createStep0();
      const clientPublic = requireBytes(requireBytes(requireBytes(step0, 11), 20), 1);

      const devicePair = await crypto.generateX25519KeyPair();
      const shared = await crypto.computeX25519(devicePair.privateKey, clientPublic);
      const popDigest = await crypto.sha256(pop);
      const sessionKey = new Uint8Array(shared.length);
      for (let index = 0; index < shared.length; index++) {
        sessionKey[index] = shared[index] ^ popDigest[index];
      }
      const deviceRandom = new Uint8Array(16);
      for (let index = 0; index < 16; index++) {
        deviceRandom[index] = index;
      }
      const deviceStream = await crypto.createAesCtrStream(sessionKey, deviceRandom);
      const expectedClientVerify = await deviceStream.process(devicePair.publicKeyRaw);
      const step1 = await session.handleStep0Response(
        encodeSessionResponse0(devicePair.publicKeyRaw, deviceRandom));
      const clientVerify = requireBytes(requireBytes(requireBytes(step1, 11), 22), 2);
      expect(BytesUtil.hexLower(clientVerify))
        .assertEqual(BytesUtil.hexLower(expectedClientVerify));

      const deviceVerify = await deviceStream.process(clientPublic);
      await session.handleStep1Response(encodeSessionResponse1(deviceVerify));
      expect(session.state).assertEqual(Security1State.ESTABLISHED);

      const request = BytesUtil.utf8('{"op":"get_status"}');
      const ciphertext = await session.encrypt(request);
      const recovered = await deviceStream.process(ciphertext);
      expect(BytesUtil.hexLower(recovered)).assertEqual(BytesUtil.hexLower(request));
      session.destroy();
      expect(session.state).assertEqual(Security1State.DESTROYED);
    });

    it('C19_OhosBleTransport_adapterCompiles', 0, () => {
      const transport = new OhosBleTransport(new NoopPermissionGate());
      expect(transport !== undefined).assertTrue();
    });
  });
}
