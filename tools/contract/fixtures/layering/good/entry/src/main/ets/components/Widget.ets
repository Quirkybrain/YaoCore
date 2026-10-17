import type { Thing } from '../model/Thing';
import type { I18nService } from '../service/i18n/I18nService';
import { LoadPhase } from '../viewmodel/core/ViewModelCore';
export class Widget { phase: LoadPhase = LoadPhase.IDLE; thing?: Thing; i18n?: I18nService; }
