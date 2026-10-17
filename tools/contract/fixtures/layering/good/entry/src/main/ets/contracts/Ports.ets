import type { Thing } from '../model/Thing';
export interface ThingPort { read(): Thing; }
