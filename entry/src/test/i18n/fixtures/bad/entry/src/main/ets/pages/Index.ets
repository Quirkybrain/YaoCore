// Fixture: deliberate violations for CHK-06/CHK-07.
export class BadFixture {
  label(): string {
    return this.i18n.t('common.missing');
  }

  hardcoded(): string {
    return '你好世界';
  }
}
