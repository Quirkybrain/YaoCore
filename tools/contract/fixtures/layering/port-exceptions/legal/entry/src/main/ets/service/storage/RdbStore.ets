export interface RdbStore { getVersion(): Promise<number>; }
export interface RdbTransaction { store: RdbStore; }
