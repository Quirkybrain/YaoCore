import type { Thing } from '../model/Thing';
import { Widget } from '../components/Widget';
import type { ThingViewModel } from '../viewmodel/ViewModel';
import { NavigationService } from '../app/NavigationService';
import type { PageVmFactoryPort } from '../app/PageVmFactory';
export class Index { thing?: Thing; widget = new Widget(); navigation = new NavigationService(); vm?: ThingViewModel; factory?: PageVmFactoryPort; }
