/*
 * YaoCore (爻构) - Open-source smart home system
 * Copyright (c) 2026 Zhang HaoXuan
 * Author: Zhang HaoXuan
 * Created: 2026-07-17
 * Source: https://github.com/Quirkybrain/YaoCore
 * SPDX-License-Identifier: Apache-2.0
 */

import { I18nService } from '../../service/I18nService';
import { DeviceIds } from '../../common/constants/DeviceConstants';
import { ControlResult } from '../../common/types/CommandTypes';
import { GenericAcAdapter } from './GenericAcAdapter';

export class GreeAcAdapter extends GenericAcAdapter {
  constructor(targetDevice: string = DeviceIds.AC) {
    super('Gree', targetDevice);
  }

  async setMode(mode: string): Promise<ControlResult> {
    const normalized = mode === I18nService.t('节能') ? 'ECO' : mode;
    return await super.setMode(normalized);
  }
}
