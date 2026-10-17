/*
 * YaoCore C-16 Haier AC adapter.
 * Producer: agent:implementation-engineer | Task: T-14 / wp-055-cloud
 * Contract: DES-B §9.1; original_app HaierAcAdapter behavior (COOL alias)
 */
import { AcMode } from '../../model/DeviceTypes';
import { AcBrand } from './AcModels';
import { GenericAcAdapter } from './GenericAcAdapter';

export class HaierAcAdapter extends GenericAcAdapter {
  constructor() {
    super(AcBrand.HAIER);
  }

  protected aliasMode(raw: string): AcMode | undefined {
    if (raw === '制冷') {
      return AcMode.COOL;
    }
    return undefined;
  }
}
