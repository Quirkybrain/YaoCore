/*
 * YaoCore C-17 device-side transport/TLS skeleton.
 * Producer: agent:implementation-engineer | Task: T-11 / wp-035-transport
 * Contract: DES-A §14.6 (device/ohosTest), §19.3 path B, §19.5; PB-03.
 *
 * STATUS: BLOCKED_ON_DEVICE_RUNNER — no device/emulator and no signing config
 * in this environment. This suite is COMPILED_ONLY and must never be reported
 * as PASS from the host Node runner.
 *
 * What it will prove once a runner exists:
 * - the real @ohos.net.http cleartext adapter maps network failures to AppError;
 * - TLSSocket + getRemoteCertificate + SPKI-SHA256 path B is available at the
 *   project API baseline and fails closed on an unreachable TLS peer;
 * - pin mismatch/handshake failure are distinguishable against the Python
 *   simulator (`--tls`, SPKI printed at startup) on a real LAN.
 *
 * PUBLIC TEST DATA ONLY. No real gateway secret or certificate is embedded.
 */
import { describe, expect, it } from '@ohos/hypium';
import { AppError } from '../../../../main/ets/common/types/AppError';
import { HttpHeaders } from '../../../../main/ets/common/types/HttpHeaders';
import { ProtocolConstants } from '../../../../main/ets/common/constants/ProtocolConstants';
import type { ClockPort } from '../../../../main/ets/common/types/Ports';
import { CryptoService } from '../../../../main/ets/service/crypto/CryptoService';
import { OhosCryptoProvider } from '../../../../main/ets/service/crypto/OhosCryptoProvider';
import { OhosHttpTransport } from '../../../../main/ets/service/gateway/adapters/OhosHttpTransport';
import { SocketTlsPinVerifier } from '../../../../main/ets/service/gateway/adapters/SocketTlsPinVerifier';
import {
  HttpRequest,
  TlsPolicy
} from '../../../../main/ets/service/gateway/GatewayTransportPorts';

const PIN_A: string = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

class DeviceClock implements ClockPort {
  nowMs(): number {
    return Date.now();
  }
}

const crypto: CryptoService = new CryptoService(new OhosCryptoProvider());

export default function gatewayTransportDeviceTest() {
  describe('BLOCKED_ON_DEVICE_RUNNER C17 transport/PB-03 path B', () => {
    it('C17_deviceTlsPinVerifierRejectsMalformedPinsBeforeNetwork', 0, async () => {
      const verifier = new SocketTlsPinVerifier(crypto);
      let code = '';
      try {
        await verifier.verify('127.0.0.1', 9200, ['not-a-pin'], 1000);
      } catch (error) {
        code = (error as AppError).code;
      }
      expect(code).assertEqual('TLS_PIN_CONFIG_INVALID');
    });

    it('C17_deviceCleartextAdapterMapsUnreachablePeer', 0, async () => {
      const transport = new OhosHttpTransport(crypto, new DeviceClock());
      const request = new HttpRequest('GET', 'http://127.0.0.1:1/health',
        HttpHeaders.from([]), undefined, 500, 500);
      let code = '';
      try {
        await transport.send(request, undefined);
      } catch (error) {
        code = (error as AppError).code;
      }
      // A closed local port must never resolve as a successful response.
      expect(code === 'GATEWAY_UNREACHABLE' || code === 'GATEWAY_TIMEOUT' ||
        code === 'LOCAL_REQUEST_FAILED').assertTrue();
    });

    it('C17_deviceTlsPinPathBFailsClosedOnUnreachablePeer', 0, async () => {
      const transport = new OhosHttpTransport(crypto, new DeviceClock());
      const policy = new TlsPolicy(true, [PIN_A], 1, 'sha256-spki-der');
      const request = new HttpRequest('GET', 'https://127.0.0.1:1/discover',
        HttpHeaders.from([]), undefined, 500, 500);
      let code = '';
      try {
        await transport.send(request, policy);
      } catch (error) {
        code = (error as AppError).code;
      }
      expect(code === 'TLS_HANDSHAKE_FAILED' || code === 'GATEWAY_UNREACHABLE' ||
        code === 'GATEWAY_TIMEOUT').assertTrue();
      expect(code.length > 0).assertTrue();
    });

    it('C17_deviceSimulatorTlsPinContractIsPendingRunner', 0, async () => {
      // Requires: python3 tools/simulator/gateway_contract_server.py --tls \
      //   --cert tools/simulator/certs/dev-test-cert.pem \
      //   --key tools/simulator/certs/dev-test-key.pem
      // and the printed SPKI-SHA256 as PIN_A on the same LAN. Until then this
      // assertion intentionally documents the blocking condition only.
      expect(ProtocolConstants.DEFAULT_GATEWAY_PORT).assertEqual(9200);
    });
  });
}
