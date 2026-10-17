/*
 * YaoCore C-24 pure UI state vocabulary.
 * Producer: agent:implementation-engineer | Task: T-18 / wp-073-ui-pages
 * Contract: DES-B §13.1.2, §13.3; UIUX §4.3
 *
 * Kept free of ArkUI globals so the host test runner can import this module.
 */
export enum AsyncUiState {
  LOADING = 'LOADING',
  READY = 'READY',
  EMPTY = 'EMPTY',
  ERROR = 'ERROR',
  DISABLED = 'DISABLED',
  READ_ONLY = 'READ_ONLY'
}

export enum CardVisualState {
  IDLE = 'IDLE',
  PENDING = 'PENDING',
  COMMITTED = 'COMMITTED',
  REVERT = 'REVERT',
  OFFLINE = 'OFFLINE',
  DISABLED = 'DISABLED',
  READ_ONLY = 'READ_ONLY'
}

export class UiAction {
  readonly id: string;
  readonly labelKey: string;
  readonly enabled: boolean;
  readonly destructive: boolean;

  constructor(id: string, labelKey: string, enabled: boolean = true,
    destructive: boolean = false) {
    this.id = id;
    this.labelKey = labelKey;
    this.enabled = enabled;
    this.destructive = destructive;
  }
}
