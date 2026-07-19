/*
 * YaoCore (爻构) - Open-source smart home system
 * Copyright (c) 2026 Zhang HaoXuan
 * Author: Zhang HaoXuan
 * Created: 2026-07-17
 * Source: https://github.com/Quirkybrain/YaoCore
 * SPDX-License-Identifier: Apache-2.0
 */

import { I18nService } from './I18nService';
import common from '@ohos.app.ability.common';
import notificationManager from '@ohos.notificationManager';
import { DateTimeUtil } from '../common/utils/DateTimeUtil';
import { DeviceState } from '../model/DeviceModel';
import { GatewayState } from '../model/GatewayModel';

export class LiveActivityService {
  private static readonly NOTICE_ID: number = 6006;
  private static readonly NOTICE_LABEL: string = 'YaoCoreMonitor';
  private static context: common.UIAbilityContext | undefined;

  static initialize(context: common.UIAbilityContext): void {
    LiveActivityService.context = context;
  }

  static async requestNotificationEnabled(): Promise<boolean> {
    if (LiveActivityService.context === undefined) {
      return false;
    }
    try {
      await notificationManager.requestEnableNotification(LiveActivityService.context);
      return true;
    } catch (error) {
      return false;
    }
  }

  static async publishSnapshot(devices: DeviceState[], gateway: GatewayState): Promise<boolean> {
    const onlineCount = LiveActivityService.countOnline(devices);
    const doorLabel = LiveActivityService.resolveDoorLabel(devices);
    const text = `${onlineCount}/${devices.length} 设备在线 · ${doorLabel}`;
    const additionalText = gateway.localAvailable ?
      (I18nService.isChinese() ? `快照来源：局域网 ${gateway.localIp}` : `Snapshot source: LAN ${gateway.localIp}`) :
      I18nService.t('快照来源：App 最后同步缓存');
    const request: notificationManager.NotificationRequest = {
      id: LiveActivityService.NOTICE_ID,
      label: LiveActivityService.NOTICE_LABEL,
      notificationSlotType: notificationManager.SlotType.SERVICE_INFORMATION,
      isOngoing: false,
      tapDismissed: true,
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: {
          title: I18nService.t('YaoCore 最近同步快照'),
          text: text,
          additionalText: `${additionalText} · ${DateTimeUtil.nowReadable()}`
        }
      }
    };
    try {
      await notificationManager.publish(request);
      await notificationManager.setBadgeNumber(devices.length - onlineCount);
      return true;
    } catch (error) {
      return false;
    }
  }

  static async cancelSnapshot(): Promise<void> {
    try {
      await notificationManager.cancel(LiveActivityService.NOTICE_ID, LiveActivityService.NOTICE_LABEL);
      await notificationManager.setBadgeNumber(0);
    } catch (error) {
    }
  }

  static getDesignNote(): string {
    return I18nService.t('通知仅展示 App 最后一次同步快照，不代表后台持续监控；打开 App 并同步后才会更新。');
  }

  private static countOnline(devices: DeviceState[]): number {
    let count = 0;
    for (let index = 0; index < devices.length; index++) {
      if (devices[index].isOnline) {
        count += 1;
      }
    }
    return count;
  }

  private static resolveDoorLabel(devices: DeviceState[]): string {
    let hasDoor = false;
    let hasUnknown = false;
    for (let index = 0; index < devices.length; index++) {
      if (devices[index].deviceType === 'door') {
        hasDoor = true;
        if (!devices[index].isOnline || devices[index].openStatus === undefined) {
          hasUnknown = true;
        } else if (devices[index].openStatus === true) {
          return I18nService.t('有门禁开启');
        }
      }
    }
    if (!hasDoor) return I18nService.t('门禁未绑定');
    return hasUnknown ? I18nService.t('门禁状态不完整') : I18nService.t('全部门禁上锁');
  }
}
