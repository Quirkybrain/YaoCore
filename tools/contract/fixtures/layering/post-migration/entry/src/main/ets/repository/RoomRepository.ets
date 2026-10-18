import type { Room } from '../model/Room';
import type { RoomPort } from '../contracts/RoomPorts';
export class RoomRepository implements RoomPort {
  async getRoom(roomId: string): Promise<Room | undefined> {
    return roomId.length > 0 ? new Room() : undefined;
  }
}
