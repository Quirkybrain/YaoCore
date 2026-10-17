import type { Thing } from '../model/Thing';
import type { ThingRepository } from '../repository/Repo';
import { I18nService } from '../service/i18n/I18nService';
import { LoadPhase } from './core/ViewModelCore';
export class ThingViewModel {
  constructor(private readonly repo: ThingRepository, private readonly i18n: I18nService) {}
  phase(): LoadPhase { return LoadPhase.IDLE; }
  read(): Thing | undefined { this.i18n.t('thing'); return this.repo.read(); }
}
