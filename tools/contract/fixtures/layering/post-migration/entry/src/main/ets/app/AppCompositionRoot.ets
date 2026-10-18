import { RoomRepository } from '../repository/RoomRepository';
import { RoomService } from '../service/room/RoomService';
import { RoomViewModel } from '../viewmodel/RoomViewModel';
export class AppCompositionRoot {
  build(): RoomViewModel {
    const repository = new RoomRepository();
    return new RoomViewModel(new RoomService(repository) as never);
  }
}
