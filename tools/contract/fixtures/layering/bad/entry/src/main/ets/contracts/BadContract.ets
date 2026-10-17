import { FamilyService } from '../service/family/FamilyService';
import { BadRepo } from '../repository/BadRepo';
export class BadContract { service = new FamilyService(); repo = new BadRepo(); }
