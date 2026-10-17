/*
 * YaoCore C-16 AC adapter factory.
 * Producer: agent:implementation-engineer | Task: T-14 / wp-055-cloud
 * Contract: DES-B §9.1; original_app AcAdapterFactory behavior
 *
 * Brand strings are protocol metadata, never a display-language branch. The
 * allowlisted Chinese aliases are interoperability aliases only.
 */
import { AcBrand } from './AcModels';
import type { AcAdapter } from './AcAdapter';
import { GenericAcAdapter } from './GenericAcAdapter';
import { GreeAcAdapter } from './GreeAcAdapter';
import { HaierAcAdapter } from './HaierAcAdapter';
import { MideaAcAdapter } from './MideaAcAdapter';

export class AcAdapterFactory {
  static create(brand: string | undefined): AcAdapter {
    const normalized = AcAdapterFactory.normalizeBrand(brand);
    if (normalized === AcBrand.GREE) {
      return new GreeAcAdapter();
    }
    if (normalized === AcBrand.HAIER) {
      return new HaierAcAdapter();
    }
    if (normalized === AcBrand.MIDEA) {
      return new MideaAcAdapter();
    }
    return new GenericAcAdapter();
  }

  static normalizeBrand(brand: string | undefined): AcBrand {
    if (brand === undefined) {
      return AcBrand.GENERIC;
    }
    const normalized = brand.trim().toLowerCase();
    if (normalized === 'gree' || normalized === '格力' || normalized === 'gree/格力') {
      return AcBrand.GREE;
    }
    if (normalized === 'haier' || normalized === '海尔' || normalized === 'haier/海尔') {
      return AcBrand.HAIER;
    }
    if (normalized === 'midea' || normalized === '美的' || normalized === 'midea/美的') {
      return AcBrand.MIDEA;
    }
    return AcBrand.GENERIC;
  }

  static supportedBrands(): ReadonlyArray<AcBrand> {
    return [AcBrand.GENERIC, AcBrand.GREE, AcBrand.HAIER, AcBrand.MIDEA];
  }
}
