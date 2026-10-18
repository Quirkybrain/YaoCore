import type { UnregisteredStore } from '../service/storage/UnregisteredStore';
export class BadVm {
  constructor(private readonly store: UnregisteredStore) {}
}
