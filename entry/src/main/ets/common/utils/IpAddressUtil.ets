/*
 * YaoCore C-01 IPv4 helpers for manual address/diagnostics.
 * Producer: agent:implementation-engineer | Task: T-06 / wp-012-foundation
 * Contract: DES-A §4.1.7
 */
export class IpAddressUtil {
  static isValidIpv4(value: string): boolean {
    const parts = value.split('.');
    if (parts.length !== 4) {
      return false;
    }
    for (let index = 0; index < parts.length; index++) {
      const part = parts[index];
      if (part.length === 0 || part.length > 3) {
        return false;
      }
      if (part.length > 1 && part.charAt(0) === '0') {
        return false;
      }
      for (let i = 0; i < part.length; i++) {
        const code = part.charCodeAt(i);
        if (code < 0x30 || code > 0x39) {
          return false;
        }
      }
      const octet = Number.parseInt(part, 10);
      if (octet < 0 || octet > 255) {
        return false;
      }
    }
    return true;
  }

  static isAllowedLanIpv4(value: string): boolean {
    if (!IpAddressUtil.isValidIpv4(value)) {
      return false;
    }
    const parts = value.split('.');
    const first = Number.parseInt(parts[0], 10);
    const second = Number.parseInt(parts[1], 10);
    if (first === 0 || first === 127) {
      return false;
    }
    if (first === 169 && second === 254) {
      return false;
    }
    if (first >= 224 && first <= 239) {
      return false;
    }
    if (value === '255.255.255.255') {
      return false;
    }
    return true;
  }

  static isValidPort(port: number): boolean {
    return Number.isInteger(port) && port >= 1 && port <= 65535;
  }

  static format(address: string, port: number): string {
    return address + ':' + String(port);
  }
}
