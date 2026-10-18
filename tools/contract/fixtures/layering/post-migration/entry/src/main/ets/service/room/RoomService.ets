import type { Room } from '../../model/Room';
import type { RoomPort } from '../../contracts/RoomPorts';
export class RoomService {
  constructor(private readonly rooms: RoomPort) {}
  load(roomId: string): Promise<Room | undefined> { return this.rooms.getRoom(roomId); }
}
