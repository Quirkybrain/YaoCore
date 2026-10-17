// Fixture: all user-visible text goes through t()/$r().
export class IndexFixture {
  label(): string {
    return this.i18n.t('common.ok');
  }

  title(): string {
    return this.$r('app.string.app_name');
  }
}
