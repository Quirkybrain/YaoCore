export interface UnregisteredStore {
  read(key: string): Promise<string | undefined>;
}
