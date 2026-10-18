import type { UnregisteredStore } from '../service/storage/UnregisteredStore';
export class BadRepo {
  constructor(private readonly store: UnregisteredStore) {}
}
