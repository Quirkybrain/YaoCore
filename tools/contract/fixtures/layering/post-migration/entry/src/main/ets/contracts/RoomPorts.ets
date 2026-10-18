import type { Room } from '../model/Room';
export interface RoomPort {
  getRoom(roomId: string): Promise<Room | undefined>;
}
