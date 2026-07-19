/*
 * YaoCore (爻构) - Open-source smart home system
 * Copyright (c) 2026 Zhang HaoXuan
 * Author: Zhang HaoXuan
 * Created: 2026-07-17
 * Source: https://github.com/Quirkybrain/YaoCore
 * SPDX-License-Identifier: Apache-2.0
 */

import { I18nService } from './I18nService';
import cryptoFramework from '@ohos.security.cryptoFramework';
import { DateTimeUtil } from '../common/utils/DateTimeUtil';
import { AuthSession, createAnonymousSession, LocalCredential } from '../model/UserModel';
import { AppStorageService } from './AppStorageService';

export interface AuthResult {
  success: boolean;
  message: string;
  session: AuthSession;
}

/**
 * Maintains one device-local display profile.
 *
 * This profile is not an identity provider and is not used as an authorization
 * gate for device control. It only provides a local lock around the profile
 * name shown by this app.
 */
export class AuthService {
  private static instance: AuthService | undefined;
  private static readonly PASSWORD_ITERATIONS: number = 120000;
  private static readonly PASSWORD_KEY_BYTES: number = 32;
  private static readonly SALT_BYTES: number = 16;
  private static readonly SESSION_TOKEN_BYTES: number = 32;
  private credential: LocalCredential | undefined = undefined;
  private session: AuthSession = createAnonymousSession();
  private profileNotice: string = '';
  private loaded: boolean = false;

  static getInstance(): AuthService {
    if (AuthService.instance === undefined) {
      AuthService.instance = new AuthService();
    }
    return AuthService.instance;
  }

  async load(): Promise<void> {
    if (this.loaded) {
      return;
    }
    this.credential = await AppStorageService.loadLocalCredential();
    if (AppStorageService.consumeLocalProfileResetNotice()) {
      this.profileNotice = I18nService.t('旧版本机档案使用不安全的可逆存储，已失效并清除，请重新创建。');
    }
    const storedSession = await AppStorageService.loadSession();
    if (this.credential === undefined || !storedSession.signedIn ||
      storedSession.email !== this.credential.username) {
      this.session = createAnonymousSession();
      if (storedSession.signedIn) {
        await AppStorageService.saveSession(this.session);
      }
    } else {
      try {
        this.session = this.createUnlockedSession(this.credential.username);
        await AppStorageService.saveSession(this.session);
      } catch (error) {
        this.session = createAnonymousSession();
        await AppStorageService.saveSession(this.session);
      }
    }
    this.loaded = true;
  }

  getSession(): AuthSession {
    return {
      signedIn: this.session.signedIn,
      userId: this.session.userId,
      email: this.session.email,
      displayName: this.session.displayName,
      token: this.session.token,
      updatedAt: this.session.updatedAt
    };
  }

  consumeProfileNotice(): string {
    const notice = this.profileNotice;
    this.profileNotice = '';
    return notice;
  }

  async register(email: string, password: string): Promise<AuthResult> {
    await this.load();
    const username = email.trim();
    if (username.length < 2) {
      return this.result(false, I18nService.t('用户名至少 2 位'));
    }
    if (password.length < 8) {
      return this.result(false, I18nService.t('密码至少 8 位'));
    }
    if (this.credential !== undefined) {
      return this.result(false, I18nService.t('本机已有使用档案，请直接解锁'));
    }

    try {
      const saltBytes = this.secureRandomBytes(AuthService.SALT_BYTES);
      const passwordHash = await this.derivePassword(
        password,
        saltBytes,
        AuthService.PASSWORD_ITERATIONS
      );
      const credential: LocalCredential = {
        username: username,
        salt: this.toHex(saltBytes),
        passwordHash: this.toHex(passwordHash),
        iterations: AuthService.PASSWORD_ITERATIONS
      };
      const saved = await AppStorageService.saveLocalCredential(credential);
      if (!saved) {
        return this.result(false, I18nService.t('本机安全档案保存失败'));
      }
      this.credential = credential;
      const unlockedSession = this.createUnlockedSession(username);
      const sessionSaved = await AppStorageService.saveSession(unlockedSession);
      if (!sessionSaved) {
        this.session = createAnonymousSession();
        return this.result(false, I18nService.t('档案已创建，但解锁状态未保存，请重新解锁'));
      }
      this.session = unlockedSession;
      return this.result(true, I18nService.t('本机使用档案已创建并解锁'));
    } catch (error) {
      return this.result(false, I18nService.t('本机安全组件不可用，请稍后重试'));
    }
  }

  async login(email: string, password: string): Promise<AuthResult> {
    await this.load();
    const username = email.trim();
    if (username.length < 2) {
      return this.result(false, I18nService.t('用户名至少 2 位'));
    }
    if (password.length < 8) {
      return this.result(false, I18nService.t('密码至少 8 位'));
    }
    if (this.credential === undefined) {
      return this.result(false, I18nService.t('请先创建本机使用档案'));
    }

    try {
      const credential = this.credential;
      const candidateHash = await this.derivePassword(
        password,
        this.fromHex(credential.salt),
        credential.iterations
      );
      const usernameMatches = this.constantTimeEqual(username, credential.username);
      const passwordMatches = this.constantTimeEqual(this.toHex(candidateHash), credential.passwordHash);
      if (!usernameMatches || !passwordMatches) {
        return this.result(false, I18nService.t('用户名或密码不正确'));
      }

      const unlockedSession = this.createUnlockedSession(credential.username);
      const saved = await AppStorageService.saveSession(unlockedSession);
      if (!saved) {
        return this.result(false, I18nService.t('本机解锁状态保存失败'));
      }
      this.session = unlockedSession;
      return this.result(true, I18nService.t('本机使用档案已解锁'));
    } catch (error) {
      return this.result(false, I18nService.t('本机安全组件不可用，请稍后重试'));
    }
  }

  async logout(): Promise<AuthResult> {
    await this.load();
    const lockedSession = createAnonymousSession();
    const saved = await AppStorageService.saveSession(lockedSession);
    if (!saved) {
      return this.result(false, I18nService.t('本机使用档案锁定失败'));
    }
    this.session = lockedSession;
    return this.result(true, I18nService.t('本机使用档案已锁定'));
  }

  hasLocalAccount(): boolean {
    return this.credential !== undefined;
  }

  private async derivePassword(
    password: string,
    salt: Uint8Array,
    iterations: number
  ): Promise<Uint8Array> {
    try {
      const spec: cryptoFramework.PBKDF2Spec = {
        algName: 'PBKDF2',
        password: password,
        salt: salt,
        iterations: iterations,
        keySize: AuthService.PASSWORD_KEY_BYTES
      };
      const kdf = cryptoFramework.createKdf('PBKDF2|SHA256');
      return (await kdf.generateSecret(spec)).data;
    } catch (error) {
      throw new Error('PBKDF2_FAILED');
    }
  }

  private createUnlockedSession(username: string): AuthSession {
    return {
      signedIn: true,
      userId: 'local-profile',
      email: username,
      displayName: username,
      token: this.toHex(this.secureRandomBytes(AuthService.SESSION_TOKEN_BYTES)),
      updatedAt: DateTimeUtil.nowDisplay()
    };
  }

  private secureRandomBytes(byteLength: number): Uint8Array {
    try {
      return cryptoFramework.createRandom().generateRandomSync(byteLength).data;
    } catch (error) {
      throw new Error('SECURE_RANDOM_FAILED');
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

  private fromHex(value: string): Uint8Array {
    const output = new Uint8Array(value.length / 2);
    for (let index = 0; index < output.length; index++) {
      output[index] = parseInt(value.substring(index * 2, index * 2 + 2), 16);
    }
    return output;
  }

  private toHex(bytes: Uint8Array): string {
    let output = '';
    for (let index = 0; index < bytes.length; index++) {
      let part = bytes[index].toString(16);
      if (part.length < 2) {
        part = `0${part}`;
      }
      output += part;
    }
    return output;
  }

  private result(success: boolean, message: string): AuthResult {
    return {
      success: success,
      message: message,
      session: this.getSession()
    };
  }
}
