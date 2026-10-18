import type { Room } from '../model/Room';
import type { RoomPort } from '../contracts/RoomPorts';
import type { RoomViewModel } from '../viewmodel/RoomViewModel';
export class RoomPage {
  room?: Room;
  constructor(private readonly port: RoomPort, private readonly vm: RoomViewModel) {}
}
