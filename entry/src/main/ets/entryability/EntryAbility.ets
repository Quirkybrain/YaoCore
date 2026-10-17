/*
 * Copyright (c) 2026 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/*
 * YaoCore C-28 EntryAbility.
 * Producer: agent:implementation-engineer | Task: T-17 / wp-067-ui-shell
 * Contract: DES-B §17.1.4, §17.3; DES-B-C28-API
 *
 * onCreate builds the one AppCompositionRoot + AppContext and starts
 * AppContext.initialize() without blocking or leaking an unhandled rejection.
 * onWindowStageCreate loads pages/Index only after initialization settles; the
 * context/error travel through one LocalStorage bootstrap. No auto discovery,
 * auto cloud polling or auto unlock happens at startup.
 */
import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { AppError, AppErrors } from '../common/types/AppError';
import { AppContext } from '../app/AppContext';
import { AppCompositionRoot } from '../app/AppCompositionRoot';
import { ShellBootstrap } from '../app/ShellBootstrap';

const DOMAIN = 0x0000;
const TAG = 'YaoCore';

export default class EntryAbility extends UIAbility {
  private root: AppCompositionRoot | undefined = undefined;
  private appContext: AppContext | undefined = undefined;
  private bootstrapError: AppError | undefined = undefined;
  private initPromise: Promise<void> = Promise.resolve();
  private windowStage: window.WindowStage | undefined = undefined;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(
        ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (error) {
      hilog.error(DOMAIN, TAG, '%{public}s', 'set_color_mode_failed');
    }
    try {
      this.root = AppCompositionRoot.create(this.context);
      this.appContext = this.root.appContext;
      this.initPromise = this.appContext.initialize();
    } catch (error) {
      this.bootstrapError = EntryAbility.asAppError(error as Error);
      hilog.error(DOMAIN, TAG, '%{public}s', 'composition_root_create_failed');
    }
    hilog.info(DOMAIN, TAG, '%{public}s', 'onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'onDestroy');
    const root = this.root;
    this.root = undefined;
    this.appContext = undefined;
    if (root !== undefined) {
      root.dispose().catch((error: Object): void => {
        hilog.warn(DOMAIN, TAG, '%{public}s', 'dispose_failed');
      });
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'onWindowStageCreate');
    this.windowStage = windowStage;
    this.initPromise.then((): void => {
      this.loadIndex(windowStage);
    }).catch((): void => {
      this.loadIndex(windowStage);
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'onWindowStageDestroy');
    this.windowStage = undefined;
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'onForeground');
    const context = this.appContext;
    if (context !== undefined) {
      context.onForeground().catch((error: Object): void => {
        hilog.warn(DOMAIN, TAG, '%{public}s', 'on_foreground_failed');
      });
    }
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'onBackground');
    const context = this.appContext;
    if (context !== undefined) {
      context.onBackground().catch((error: Object): void => {
        hilog.warn(DOMAIN, TAG, '%{public}s', 'on_background_failed');
      });
    }
  }

  private loadIndex(windowStage: window.WindowStage): void {
    if (this.windowStage !== windowStage) {
      return;
    }
    try {
      const storage = new LocalStorage();
      storage.setOrCreate('bootstrap',
        new ShellBootstrap(this.appContext, this.bootstrapError));
      windowStage.loadContent('pages/Index', storage, (err): void => {
        if (err.code) {
          hilog.error(DOMAIN, TAG, '%{public}s', 'load_content_failed');
          return;
        }
        hilog.info(DOMAIN, TAG, '%{public}s', 'load_content_ok');
      });
    } catch (error) {
      hilog.error(DOMAIN, TAG, '%{public}s', 'load_content_threw');
    }
  }

  private static asAppError(error: Error): AppError {
    if (error instanceof AppError) {
      return error as AppError;
    }
    return AppErrors.of('INTERNAL_ERROR', []);
  }
}
