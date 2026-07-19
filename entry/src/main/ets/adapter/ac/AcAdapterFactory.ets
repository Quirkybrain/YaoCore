/*
 * YaoCore (爻构) - Open-source smart home system
 * Copyright (c) 2026 Zhang HaoXuan
 * Author: Zhang HaoXuan
 * Created: 2026-07-17
 * Source: https://github.com/Quirkybrain/YaoCore
 * SPDX-License-Identifier: Apache-2.0
 */

import { I18nService } from '../../service/I18nService';
import { AcAdapter } from './AcAdapter';
import { GenericAcAdapter } from './GenericAcAdapter';
import { GreeAcAdapter } from './GreeAcAdapter';
import { HaierAcAdapter } from './HaierAcAdapter';
import { MideaAcAdapter } from './MideaAcAdapter';

export class AcAdapterFactory {
  static create(brand: string | undefined, targetDevice: string): AcAdapter {
    const normalized = brand === undefined ? '' : brand.trim().toLowerCase();
    // Protocol routing must never depend on the current display language.
    if (normalized === 'gree' || normalized === '格力' || normalized === 'gree/格力') {
      return new GreeAcAdapter(targetDevice);
    }
    if (normalized === 'haier' || normalized === '海尔' || normalized === 'haier/海尔') {
      return new HaierAcAdapter(targetDevice);
    }
    if (normalized === 'midea' || normalized === '美的' || normalized === 'midea/美的') {
      return new MideaAcAdapter(targetDevice);
    }
    return new GenericAcAdapter(brand === undefined || brand.trim().length === 0 ? 'Generic' : brand.trim(), targetDevice);
  }

  static supportedBrands(): string[] {
    return [I18nService.t('通用'), I18nService.t('格力'), I18nService.t('海尔'), I18nService.t('美的')];
  }
}
