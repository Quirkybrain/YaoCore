import { ThingService } from '../service/protocol/Service';
import { ThingRepository } from '../repository/Repo';
import { ThingViewModel } from '../viewmodel/ViewModel';
export class AppCompositionRoot {
  build(): ThingViewModel { return new ThingViewModel(new ThingRepository(), new ThingService() as never); }
}
