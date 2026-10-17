import type { RdbTransaction } from '../service/storage/RdbStore';
export class Repo { tx(): RdbTransaction | undefined { return undefined; } }
