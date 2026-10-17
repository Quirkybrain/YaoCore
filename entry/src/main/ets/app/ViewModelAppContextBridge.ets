/*
 * YaoCore C-28 ViewModel session-gate bridge.
 * Producer: agent:implementation-engineer | Task: T-17 / wp-067-ui-shell
 * Contract: DES-B §10.1/§11.1/§17.1.3; DES-B-C28-SEAM
 *
 * ViewModel AppContextPort is synchronous (`refreshSessionGate(): void`,
 * `lock(): void`), while AppContext exposes the async DES-B signatures. This
 * adapter is the single fire-and-forget boundary; failures are logged and
 * never rethrown into a UI event handler.
 */
import type { LoggerPort } from '../common/types/Ports';
import type { AppContextPort } from '../viewmodel/core/ViewModelCore';
import { AppContext } from './AppContext';

export class ViewModelAppContextBridge implements AppContextPort {
  private readonly context: AppContext;
  private readonly logger: LoggerPort;

  constructor(context: AppContext, logger: LoggerPort) {
    this.context = context;
    this.logger = logger;
  }

  refreshSessionGate(): void {
    this.context.refreshSessionGate().catch((error: Object): void => {
      this.logger.warn('AppContextBridge', 'refresh_session_gate_failed');
    });
  }

  lock(): void {
    this.context.lock().catch((error: Object): void => {
      this.logger.warn('AppContextBridge', 'lock_failed');
    });
  }
}
