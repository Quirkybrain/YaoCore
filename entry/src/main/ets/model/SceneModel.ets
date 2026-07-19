/*
 * YaoCore (爻构) - Open-source smart home system
 * Copyright (c) 2026 Zhang HaoXuan
 * Author: Zhang HaoXuan
 * Created: 2026-07-17
 * Source: https://github.com/Quirkybrain/YaoCore
 * SPDX-License-Identifier: Apache-2.0
 */

import { CommandValue } from '../common/types/CommandTypes';

export interface SceneAction {
  targetDevice: string;
  /** 固化创建/编辑时的物理网关，防止切换网关后同名 deviceId 被误执行。 */
  gatewayId?: string;
  action: string;
  value?: CommandValue;
  delayMs?: number;
}

export interface SceneDefinition {
  sceneId: string;
  sceneName: string;
  description: string;
  accentColor: string;
  actions: SceneAction[];
  isPreset?: boolean;
}

export interface SceneDraft {
  sceneId?: string;
  sceneName: string;
  description: string;
  accentColor: string;
  actions: SceneAction[];
}

export interface SceneCleanupResult {
  removedActionCount: number;
  affectedSceneNames: string[];
}
