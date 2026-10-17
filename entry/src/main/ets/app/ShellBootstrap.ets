/*
 * YaoCore C-28 shell bootstrap value.
 * Producer: agent:implementation-engineer | Task: T-17 / wp-067-ui-shell
 * Contract: DES-B §17.1.4/§17.1.5
 *
 * EntryAbility writes one ShellBootstrap into the ability LocalStorage before
 * loadContent(). Index reads it via @LocalStorageProp. A missing context is a
 * startup error state, never an implicit second composition root.
 */
import type { AppError } from '../common/types/AppError';
import type { AppContext } from './AppContext';

export class ShellBootstrap {
  readonly appContext?: AppContext;
  readonly startupError?: AppError;

  constructor(appContext?: AppContext, startupError?: AppError) {
    this.appContext = appContext;
    this.startupError = startupError;
  }
}
