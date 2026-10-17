/*
 * YaoCore C-16 Gree AC adapter.
 * Producer: agent:implementation-engineer | Task: T-14 / wp-055-cloud
 * Contract: DES-B §9.1; original_app GreeAcAdapter behavior (ECO alias)
 */
import { AcMode } from '../../model/DeviceTypes';
import { AcBrand } from './AcModels';
import { GenericAcAdapter } from './GenericAcAdapter';

export class GreeAcAdapter extends GenericAcAdapter {
  constructor() {
    super(AcBrand.GREE);
  }

  protected aliasMode(raw: string): AcMode | undefined {
    if (raw === '节能') {
      return AcMode.ECO;
    }
    return undefined;
  }
}
