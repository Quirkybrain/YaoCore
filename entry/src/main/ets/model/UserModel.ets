/*
 * YaoCore (爻构) - Open-source smart home system
 * Copyright (c) 2026 Zhang HaoXuan
 * Author: Zhang HaoXuan
 * Created: 2026-07-17
 * Source: https://github.com/Quirkybrain/YaoCore
 * SPDX-License-Identifier: Apache-2.0
 */

import { I18nService } from '../service/I18nService';

/**
 * A single device-local profile verifier.
 *
 * This is deliberately not a cloud account or an authorization record. The
 * password itself is never persisted; only a salted PBKDF2 verifier is stored.
 */
export interface LocalCredential {
  username: string;
  salt: string;
  passwordHash: string;
  iterations: number;
}

export interface AuthSession {
  signedIn: boolean;
  userId: string;
  email: string;
  displayName: string;
  token: string;
  updatedAt: string;
}

export function createAnonymousSession(): AuthSession {
  return {
    signedIn: false,
    userId: '',
    email: '',
    displayName: I18nService.t('未解锁'),
    token: '',
    updatedAt: ''
  };
}
