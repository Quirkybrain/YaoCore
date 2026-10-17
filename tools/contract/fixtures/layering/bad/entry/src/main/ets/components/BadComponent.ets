import { BadApp } from '../app/BadApp';
import { BadVm } from '../viewmodel/BadVm';
import { FamilyService } from '../service/family/FamilyService';
export class BadComponent { app = new BadApp(); vm = new BadVm(); service = new FamilyService(); }
