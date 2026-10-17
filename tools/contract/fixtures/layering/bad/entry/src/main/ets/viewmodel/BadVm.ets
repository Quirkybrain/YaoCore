import { http } from '@ohos.net.http';
import { OhosHttpTransport } from '../service/gateway/adapters/OhosHttpTransport';
import { FamilyService } from '../service/family/FamilyService';
export class BadVm { client = http; transport = new OhosHttpTransport(); service = new FamilyService(); }
