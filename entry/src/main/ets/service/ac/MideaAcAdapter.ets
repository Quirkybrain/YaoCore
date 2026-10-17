/*
 * YaoCore C-16 Midea AC adapter.
 * Producer: agent:implementation-engineer | Task: T-14 / wp-055-cloud
 * Contract: DES-B §9.1; original_app MideaAcAdapter behavior (SLEEP alias)
 */
import { AcMode } from '../../model/DeviceTypes';
import { AcBrand } from './AcModels';
import { GenericAcAdapter } from './GenericAcAdapter';

export class MideaAcAdapter extends GenericAcAdapter {
  constructor() {
    super(AcBrand.MIDEA);
  }

  protected aliasMode(raw: string): AcMode | undefined {
    if (raw === '睡眠') {
      return AcMode.SLEEP;
    }
    return undefined;
  }
}
