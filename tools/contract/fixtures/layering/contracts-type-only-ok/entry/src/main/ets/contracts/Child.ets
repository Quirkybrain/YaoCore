import type { Base } from './Base';
import { Thing } from '../model/Thing';
import type { Util } from '../common/Util';

export type { Base } from './Base';

export interface Child extends Base {
  thing: Thing;
  util: Util;
}
