/*
 * YaoCore (爻构) - Open-source smart home system
 * Copyright (c) 2026 Zhang HaoXuan
 * Author: Zhang HaoXuan
 * Created: 2026-07-17
 * Source: https://github.com/Quirkybrain/YaoCore
 * SPDX-License-Identifier: Apache-2.0
 */

import cryptoFramework from '@ohos.security.cryptoFramework';
import util from '@ohos.util';
import { DateTimeUtil } from '../common/utils/DateTimeUtil';
import { DeviceControlCommand } from '../common/types/CommandTypes';
import { AppStorageService } from './AppStorageService';

export interface CommandSigningContext {
  requestId: string;
  commandId: number;
  sequence: number;
}

export interface SignedCommandMeta {
  timestamp: string;
  nonce: string;
  sign: string;
  algorithm: string;
  keyId: string;
}

export interface SignedDiscoveryMeta {
  timestamp: string;
  nonce: string;
  sign: string;
  algorithm: string;
  keyId: string;
}

export class SecurityService {
  private static instance: SecurityService | undefined;
  private static readonly ALGORITHM: string = 'HMAC-SHA256';
  private static readonly KEY_ID: string = 'app-key-v1';
  private sessionSecret: string = '';
  private loaded: boolean = false;

  static getInstance(): SecurityService {
    if (SecurityService.instance === undefined) {
      SecurityService.instance = new SecurityService();
    }
    return SecurityService.instance;
  }

  async load(): Promise<void> {
    if (this.loaded) {
      return;
    }
    this.sessionSecret = await AppStorageService.loadCommandSecret();
    this.loaded = true;
  }

  async setSessionSecret(secret: string): Promise<boolean> {
    const normalized = secret.trim();
    const saved = await AppStorageService.saveCommandSecret(normalized);
    if (saved) {
      this.sessionSecret = normalized;
      this.loaded = true;
    }
    return saved;
  }

  async clearSessionSecret(): Promise<boolean> {
    return await this.setSessionSecret('');
  }

  hasSessionSecret(): boolean {
    return this.sessionSecret.length >= 16;
  }

  getAlgorithm(): string {
    return SecurityService.ALGORITHM;
  }

  getKeyId(): string {
    return SecurityService.KEY_ID;
  }

  createRequestId(): string {
    return `${new Date().getTime().toString(16)}-${this.randomHex(12)}`;
  }

  createResponseChallenge(): string {
    return this.randomHex(16);
  }

  signDiscoveryRequest(challenge: string): SignedDiscoveryMeta {
    if (!this.hasSessionSecret() || !this.isLowerHex(challenge, 32)) {
      throw new Error('COMMAND_KEY_NOT_CONFIGURED');
    }
    const timestamp = DateTimeUtil.nowIsoCompact();
    const nonce = this.randomHex(16);
    const canonical = `YAOCORE-DISCOVER-V2\n${challenge}\n${timestamp}\n${nonce}\n${SecurityService.ALGORITHM}\n${SecurityService.KEY_ID}`;
    return {
      timestamp: timestamp,
      nonce: nonce,
      sign: this.hmacSha256(canonical, this.sessionSecret),
      algorithm: SecurityService.ALGORITHM,
      keyId: SecurityService.KEY_ID
    };
  }

  verifyResponseAuthentication(
    kind: string,
    expectedCorrelation: string,
    responseBody: string,
    algorithm: string,
    keyId: string,
    responseCorrelation: string,
    signature: string
  ): boolean {
    if (!this.hasSessionSecret() || (kind !== 'discover' && kind !== 'control')) {
      return false;
    }
    if (algorithm !== SecurityService.ALGORITHM || keyId !== SecurityService.KEY_ID ||
      expectedCorrelation.length === 0 || !this.constantTimeEqual(responseCorrelation, expectedCorrelation) ||
      !this.isLowerHex(signature, 64)) {
      return false;
    }
    try {
      const bodyHash = this.sha256(responseBody);
      const canonical = `YAOCORE-RESPONSE-V1\n${kind}\n${expectedCorrelation}\n${bodyHash}`;
      const expectedSignature = this.hmacSha256(canonical, this.sessionSecret);
      return this.constantTimeEqual(signature, expectedSignature);
    } catch (error) {
      return false;
    }
  }

  signCommand(command: DeviceControlCommand, context: CommandSigningContext): SignedCommandMeta {
    if (!this.hasSessionSecret()) {
      throw new Error('COMMAND_KEY_NOT_CONFIGURED');
    }
    const timestamp = DateTimeUtil.nowIsoCompact();
    const nonce = this.randomHex(16);
    const canonical = this.buildCanonical(command, context, timestamp, nonce);
    return {
      timestamp: timestamp,
      nonce: nonce,
      sign: this.hmacSha256(canonical, this.sessionSecret),
      algorithm: SecurityService.ALGORITHM,
      keyId: SecurityService.KEY_ID
    };
  }

  private buildCanonical(
    command: DeviceControlCommand,
    context: CommandSigningContext,
    timestamp: string,
    nonce: string
  ): string {
    const value = this.commandValueText(command);
    return `${context.requestId}\n${context.commandId}\n${context.sequence}\n${command.targetDevice}\n${command.action}\n${value}\n${timestamp}\n${nonce}\n${SecurityService.ALGORITHM}\n${SecurityService.KEY_ID}`;
  }

  private commandValueText(command: DeviceControlCommand): string {
    if (command.value === undefined) {
      return '';
    }
    if (typeof command.value === 'string') {
      return JSON.stringify(command.value);
    }
    return `${command.value}`;
  }

  private hmacSha256(input: string, secret: string): string {
    try {
      const encoder = util.TextEncoder.create('utf-8');
      let key = encoder.encodeInto(secret);
      if (key.length > 64) {
        key = this.sha256Bytes(key);
      }
      const innerPad = new Uint8Array(64);
      const outerPad = new Uint8Array(64);
      for (let index = 0; index < 64; index++) {
        const keyByte = index < key.length ? key[index] : 0;
        innerPad[index] = keyByte ^ 0x36;
        outerPad[index] = keyByte ^ 0x5c;
      }
      const message = encoder.encodeInto(input);
      const innerInput = new Uint8Array(innerPad.length + message.length);
      innerInput.set(innerPad, 0);
      innerInput.set(message, innerPad.length);
      const innerHash = this.sha256Bytes(innerInput);
      const outerInput = new Uint8Array(outerPad.length + innerHash.length);
      outerInput.set(outerPad, 0);
      outerInput.set(innerHash, outerPad.length);
      return this.toHex(this.sha256Bytes(outerInput));
    } catch (error) {
      throw new Error('HMAC_SHA256_FAILED');
    }
  }

  private sha256Bytes(input: Uint8Array): Uint8Array {
    const digest = cryptoFramework.createMd('SHA256');
    digest.updateSync({ data: input });
    return digest.digestSync().data;
  }

  private sha256(input: string): string {
    try {
      const encoder = util.TextEncoder.create('utf-8');
      return this.toHex(this.sha256Bytes(encoder.encodeInto(input)));
    } catch (error) {
      throw new Error('SHA256_FAILED');
    }
  }

  private constantTimeEqual(left: string, right: string): boolean {
    const maxLength = Math.max(left.length, right.length);
    let difference = left.length ^ right.length;
    for (let index = 0; index < maxLength; index++) {
      const leftCode = index < left.length ? left.charCodeAt(index) : 0;
      const rightCode = index < right.length ? right.charCodeAt(index) : 0;
      difference |= leftCode ^ rightCode;
    }
    return difference === 0;
  }

  private isLowerHex(value: string, expectedLength: number): boolean {
    if (value.length !== expectedLength) {
      return false;
    }
    for (let index = 0; index < value.length; index++) {
      const code = value.charCodeAt(index);
      const digit = code >= 48 && code <= 57;
      const lowerHex = code >= 97 && code <= 102;
      if (!digit && !lowerHex) {
        return false;
      }
    }
    return true;
  }

  private randomHex(byteLength: number): string {
    try {
      const random = cryptoFramework.createRandom();
      return this.toHex(random.generateRandomSync(byteLength).data);
    } catch (error) {
      throw new Error('SECURE_RANDOM_FAILED');
    }
  }

  private toHex(bytes: Uint8Array): string {
    let result = '';
    for (let index = 0; index < bytes.length; index++) {
      let part = bytes[index].toString(16);
      if (part.length < 2) {
        part = `0${part}`;
      }
      result += part;
    }
    return result;
  }
}
