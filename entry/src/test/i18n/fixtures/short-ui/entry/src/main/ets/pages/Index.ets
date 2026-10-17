// Fixture: short English UI text is advisory by default and blocking with --strict-ui.
export class IndexFixture {
  greeting: string = 'Welcome';

  title(): string {
    return this.$r('app.string.app_name');
  }
}
