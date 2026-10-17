/*
 * YaoCore C-17 PB-03 path B: TLSSocket + manual SPKI pin verification.
 * Producer: agent:implementation-engineer | Task: T-11 / wp-035-transport
 * Contract: DES-A §19.3 path B, §14.1.3, §19.4; ADR-002 §4.1/§6.2
 *
 * COMPILED_ONLY / DEVICE-VERIFIED-PENDING. This file imports @ohos.net.socket
 * and @ohos.security.cert and must only be assembled by the composition root
 * (C-28) or ohosTest. Host tests exercise the pure pin-set logic through fakes;
 * the real handshake/SPKI extraction remains BLOCKED on a device runner.
 *
 * Path B handshake:
 *   TLSSocket.connect({skipRemoteValidation:true, TLSv1.2/TLSv1.3})
 *   -> getRemoteCertificate() -> cert.createX509Cert()
 *   -> X509Cert.getPublicKey().getEncoded() (X.509 SPKI DER)
 *   -> SHA-256 -> 64 lowercase hex -> constant-time compare with the pins.
 * The socket is closed immediately; a mismatch never sends HTTP bytes.
 */
import { socket } from '@kit.NetworkKit';
import { AppError, AppErrors } from '../../../common/types/AppError';
import { TlsVerification } from '../GatewayTransportPorts';
import type { TlsPinVerifier } from '../GatewayTransportPorts';
import type { CryptoPort } from '../../crypto/CryptoPort';
import { TlsPinCheck } from './TlsPinCheck';

interface PlatformErrorLike {
  code?: number;
}

const CODE_CONNECTION_TIMED_OUT: number = 2303210;
const CODE_SSL_NULL: number = 2303501;
const CODE_SSL_VERIFY: number = 2303504;
const CODE_SSL_SYSCALL: number = 2303505;
const CODE_SSL_CLOSE: number = 2303506;
const CODE_ADDRESS_IN_USE: number = 2303198;
const CODE_ADDRESS_UNASSIGNABLE: number = 2303199;
const CODE_NOT_SOCKET: number = 2303188;
const CODE_BAD_FD: number = 2303109;
const CODE_INTERRUPTED: number = 2303104;
const CODE_TRY_AGAIN: number = 2303111;
const CODE_PROTOCOL_TYPE: number = 2303191;

export class SocketTlsPinVerifier implements TlsPinVerifier {
  private readonly crypto: CryptoPort;

  constructor(crypto: CryptoPort) {
    this.crypto = crypto;
  }

  async verify(host: string, port: number, pins: ReadonlyArray<string>,
    timeoutMs: number): Promise<TlsVerification> {
    TlsPinCheck.validatePins(pins);
    let tlsSocket: socket.TLSSocket | undefined = undefined;
    try {
      tlsSocket = socket.constructTLSSocketInstance();
      await SocketTlsPinVerifier.connect(tlsSocket, host, port, timeoutMs);
      const raw = await tlsSocket.getRemoteCertificate();
      const digestHex = await TlsPinCheck.spkiSha256Hex(this.crypto, raw);
      const matched = await TlsPinCheck.matchPin(this.crypto, digestHex, pins);
      if (matched === undefined) {
        throw AppErrors.of('TLS_PIN_MISMATCH', []);
      }
      let protocolVersion = 'unknown';
      try {
        protocolVersion = await tlsSocket.getProtocol();
      } catch (error) {
        // Protocol evidence is diagnostic only; the pin already matched.
        protocolVersion = 'unknown';
      }
      return new TlsVerification(matched, protocolVersion, digestHex);
    } catch (error) {
      throw SocketTlsPinVerifier.mapError(error);
    } finally {
      if (tlsSocket !== undefined) {
        try {
          await tlsSocket.close();
        } catch (error) {
          // Closing a failed handshake must never mask the classification.
        }
      }
    }
  }

  private static connect(tlsSocket: socket.TLSSocket, host: string, port: number,
    timeoutMs: number): Promise<void> {
    return new Promise<void>((resolve, reject): void => {
      let settled = false;
      const timer = setTimeout(() => {
        if (!settled) {
          settled = true;
          reject(AppErrors.of('GATEWAY_TIMEOUT', []));
        }
      }, timeoutMs);
      tlsSocket.connect({
        address: {
          address: host,
          port: port
        },
        secureOptions: {
          protocols: [socket.Protocol.TLSv12, socket.Protocol.TLSv13]
        },
        skipRemoteValidation: true
      }).then(() => {
        if (!settled) {
          settled = true;
          clearTimeout(timer);
          resolve();
        }
      }).catch((error: Object) => {
        if (!settled) {
          settled = true;
          clearTimeout(timer);
          reject(SocketTlsPinVerifier.mapError(error));
        }
      });
    });
  }

  private static mapError(error: Object): AppError {
    if (error instanceof AppError) {
      return error;
    }
    const code = (error as PlatformErrorLike).code;
    if (code === CODE_CONNECTION_TIMED_OUT) {
      return AppErrors.of('GATEWAY_TIMEOUT', []);
    }
    if (code === CODE_INTERRUPTED || code === CODE_BAD_FD || code === CODE_TRY_AGAIN ||
      code === CODE_NOT_SOCKET || code === CODE_PROTOCOL_TYPE || code === CODE_ADDRESS_IN_USE ||
      code === CODE_ADDRESS_UNASSIGNABLE) {
      return AppErrors.of('GATEWAY_UNREACHABLE', []);
    }
    if (code === CODE_SSL_NULL || code === CODE_SSL_VERIFY || code === CODE_SSL_SYSCALL ||
      code === CODE_SSL_CLOSE) {
      return AppErrors.of('TLS_HANDSHAKE_FAILED', []);
    }
    return AppErrors.of('TLS_HANDSHAKE_FAILED', []);
  }
}
