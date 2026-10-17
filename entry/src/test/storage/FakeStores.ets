/*
 * YaoCore T-08 host fakes.
 * Producer: agent:implementation-engineer | Task: T-08 / wp-020-storage
 * Contract: DES-A §9.4, §10.5, §22.4, §23.2-§23.3
 *
 * PUBLIC TEST DATA ONLY. These fakes implement only the seam behaviour that
 * C-06/C-07 need. They never default to success when misconfigured: unknown
 * SQL, missing tables/columns, and injected failures throw AppError with the
 * production code. The mini RDB supports exactly the gw_* statement shapes
 * used by GatewayRepository and the v1 migrations so repository logic is not
 * coupled to real SQLite syntax.
 */
import { AppError, AppErrors } from '../../main/ets/common/types/AppError';
import type { RdbRow, RdbStore, RdbTransaction, RdbValue } from '../../main/ets/service/storage/RdbStore';
import type { PreferencesStore } from '../../main/ets/service/storage/PreferencesStore';
import { SecretAlias } from '../../main/ets/service/storage/SecretStore';
import type { SecretStore } from '../../main/ets/service/storage/SecretStore';
import type { ClockPort, IdPort, RandomPort } from '../../main/ets/common/types/Ports';
import type { SecureBytes } from '../../main/ets/common/types/SecureBytes';
import { BytesUtil } from '../../main/ets/common/utils/BytesUtil';

export class InMemoryPreferencesStore implements PreferencesStore {
  readonly values: Map<string, string> = new Map<string, string>();
  failGet: boolean = false;
  failPut: boolean = false;
  failDelete: boolean = false;
  failFlush: boolean = false;
  getCalls: number = 0;
  putCalls: number = 0;
  flushCalls: number = 0;

  async getString(key: string): Promise<string | undefined> {
    this.getCalls++;
    if (this.failGet) {
      throw AppErrors.of('STORAGE_PREFERENCES_ERROR', []);
    }
    return this.values.get(key);
  }

  async putString(key: string, value: string): Promise<void> {
    this.putCalls++;
    if (this.failPut) {
      throw AppErrors.of('STORAGE_PREFERENCES_ERROR', []);
    }
    this.values.set(key, value);
  }

  async delete(key: string): Promise<void> {
    if (this.failDelete) {
      throw AppErrors.of('STORAGE_PREFERENCES_ERROR', []);
    }
    this.values.delete(key);
  }

  async flush(): Promise<void> {
    this.flushCalls++;
    if (this.failFlush) {
      throw AppErrors.of('STORAGE_PREFERENCES_ERROR', []);
    }
  }

  dumpValuesForTest(): string[] {
    const values: string[] = [];
    this.values.forEach((value: string): void => {
      values.push(value);
    });
    return values;
  }
}

class ColumnDef {
  readonly name: string;
  readonly primary: boolean;

  constructor(name: string, primary: boolean) {
    this.name = name;
    this.primary = primary;
  }
}

class FakeTable {
  readonly columns: Map<string, ColumnDef> = new Map<string, ColumnDef>();
  readonly rows: Map<string, Map<string, RdbValue>> = new Map<string, Map<string, RdbValue>>();
  readonly primaryKey: ReadonlyArray<string>;

  constructor(columns: ReadonlyArray<ColumnDef>, primaryKey: ReadonlyArray<string>) {
    for (let index = 0; index < columns.length; index++) {
      this.columns.set(columns[index].name, columns[index]);
    }
    this.primaryKey = primaryKey;
  }

  clone(): FakeTable {
    const columns: ColumnDef[] = [];
    this.columns.forEach((column: ColumnDef): void => {
      columns.push(column);
    });
    const copy = new FakeTable(columns, this.primaryKey);
    this.rows.forEach((row: Map<string, RdbValue>, key: string): void => {
      const rowCopy = new Map<string, RdbValue>();
      row.forEach((value: RdbValue, name: string): void => {
        rowCopy.set(name, value);
      });
      copy.rows.set(key, rowCopy);
    });
    return copy;
  }
}

function isAppCode(error: Error, code: string): boolean {
  const candidate = error as AppError;
  return candidate instanceof AppError && candidate.code === code;
}

export class InMemoryRdbStore implements RdbStore {
  private tables: Map<string, FakeTable> = new Map<string, FakeTable>();
  private version: number = 0;
  private chain: Promise<void> = Promise.resolve();
  private inTransaction: boolean = false;
  failAll: boolean = false;
  failNextExecuteContaining: string = '';
  failGetVersion: boolean = false;
  failSetVersion: boolean = false;
  failTransaction: boolean = false;
  executeCalls: number = 0;

  async execute(sql: string, args?: ReadonlyArray<RdbValue>): Promise<void> {
    this.executeCalls++;
    if (this.failAll) {
      throw AppErrors.of('STORAGE_RDB_ERROR', []);
    }
    if (this.failNextExecuteContaining.length > 0 && sql.includes(this.failNextExecuteContaining)) {
      this.failNextExecuteContaining = '';
      throw AppErrors.of('STORAGE_RDB_ERROR', []);
    }
    try {
      this.executeInternal(sql, args === undefined ? [] : args);
    } catch (error) {
      if (error instanceof AppError) {
        throw error;
      }
      throw AppErrors.of('STORAGE_RDB_ERROR', []);
    }
  }

  async query(sql: string, args?: ReadonlyArray<RdbValue>):
    Promise<ReadonlyArray<RdbRow>> {
    if (this.failAll) {
      throw AppErrors.of('STORAGE_RDB_ERROR', []);
    }
    try {
      return this.queryInternal(sql, args === undefined ? [] : args);
    } catch (error) {
      if (error instanceof AppError) {
        throw error;
      }
      throw AppErrors.of('STORAGE_RDB_ERROR', []);
    }
  }

  async transaction<T>(fn: (tx: RdbTransaction) => Promise<T>): Promise<T> {
    if (this.failTransaction) {
      throw AppErrors.of('STORAGE_RDB_ERROR', []);
    }
    const run: Promise<T> = this.chain.then((): Promise<T> => {
      return this.runTransaction(fn);
    });
    this.chain = run.then((): void => {
    }, (): void => {
    });
    return run;
  }

  async getVersion(): Promise<number> {
    if (this.failGetVersion || this.failAll) {
      throw AppErrors.of('STORAGE_RDB_ERROR', []);
    }
    return this.version;
  }

  async setVersion(version: number): Promise<void> {
    if (this.failSetVersion || this.failAll) {
      throw AppErrors.of('STORAGE_RDB_ERROR', []);
    }
    if (!Number.isInteger(version) || version < 0) {
      throw AppErrors.of('STORAGE_RDB_ERROR', []);
    }
    this.version = version;
  }

  private async runTransaction<T>(fn: (tx: RdbTransaction) => Promise<T>): Promise<T> {
    if (this.inTransaction) {
      throw AppErrors.of('STORAGE_RDB_ERROR', []);
    }
    const snapshot = this.snapshotTables();
    const versionSnapshot = this.version;
    this.inTransaction = true;
    try {
      const result = await fn(this);
      return result;
    } catch (error) {
      this.tables = snapshot;
      this.version = versionSnapshot;
      if (error instanceof AppError) {
        throw error;
      }
      throw AppErrors.of('STORAGE_RDB_ERROR', []);
    } finally {
      this.inTransaction = false;
    }
  }

  private snapshotTables(): Map<string, FakeTable> {
    const copy = new Map<string, FakeTable>();
    this.tables.forEach((table: FakeTable, name: string): void => {
      copy.set(name, table.clone());
    });
    return copy;
  }

  private executeInternal(sql: string, args: ReadonlyArray<RdbValue>): void {
    const normalized = sql.trim();
    if (normalized.length === 0) {
      throw AppErrors.of('STORAGE_RDB_ERROR', []);
    }
    const upper = normalized.toUpperCase();
    if (upper.startsWith('CREATE TABLE')) {
      this.createTable(normalized);
      return;
    }
    if (upper.startsWith('CREATE INDEX')) {
      // Index metadata is irrelevant to the fake; the statement shape is
      // still validated so a typo fails the test.
      if (!/^CREATE INDEX IF NOT EXISTS [A-Za-z0-9_]+ ON [A-Za-z0-9_]+ ?\([A-Za-z0-9_, ]+\)$/i
        .test(normalized)) {
        throw AppErrors.of('STORAGE_RDB_ERROR', []);
      }
      return;
    }
    if (upper.startsWith('INSERT')) {
      this.insertRow(normalized, args);
      return;
    }
    if (upper.startsWith('UPDATE')) {
      this.updateRows(normalized, args);
      return;
    }
    if (upper.startsWith('DELETE')) {
      this.deleteRows(normalized, args);
      return;
    }
    throw AppErrors.of('STORAGE_RDB_ERROR', []);
  }

  private createTable(sql: string): void {
    const match = /^CREATE TABLE(?: IF NOT EXISTS)? ([A-Za-z0-9_]+) \(([\s\S]*)\)$/i
      .exec(sql);
    if (match === null) {
      throw AppErrors.of('STORAGE_RDB_ERROR', []);
    }
    const name = match[1];
    if (this.tables.has(name)) {
      return;
    }
    const defs = InMemoryRdbStore.splitTopLevel(match[2]);
    const columns: ColumnDef[] = [];
    const primary: string[] = [];
    for (let index = 0; index < defs.length; index++) {
      const def = defs[index].trim();
      if (def.length === 0) {
        continue;
      }
      if (def.toUpperCase().startsWith('PRIMARY KEY')) {
        const open = def.indexOf('(');
        const close = def.lastIndexOf(')');
        if (open < 0 || close <= open) {
          throw AppErrors.of('STORAGE_RDB_ERROR', []);
        }
        const names = def.substring(open + 1, close).split(',');
        for (let keyIndex = 0; keyIndex < names.length; keyIndex++) {
          primary.push(names[keyIndex].trim());
        }
        continue;
      }
      const firstSpace = def.indexOf(' ');
      const columnName = firstSpace < 0 ? def : def.substring(0, firstSpace);
      const inlinePrimary = def.toUpperCase().includes('PRIMARY KEY');
      columns.push(new ColumnDef(columnName, inlinePrimary));
    }
    for (let index = 0; index < columns.length; index++) {
      if (columns[index].primary) {
        primary.push(columns[index].name);
      }
    }
    if (primary.length === 0) {
      throw AppErrors.of('STORAGE_RDB_ERROR', []);
    }
    this.tables.set(name, new FakeTable(columns, primary));
  }

  private insertRow(sql: string, args: ReadonlyArray<RdbValue>): void {
    const match = /^INSERT (OR REPLACE |OR IGNORE )?INTO ([A-Za-z0-9_]+) \(([^)]+)\) VALUES \(([^)]+)\)$/i
      .exec(sql);
    if (match === null) {
      throw AppErrors.of('STORAGE_RDB_ERROR', []);
    }
    const mode = match[1] === undefined ? '' : match[1].trim().toUpperCase();
    const table = this.requireTable(match[2]);
    const columns = match[3].split(',').map((value: string): string => value.trim());
    const placeholders = match[4].split(',').map((value: string): string => value.trim());
    if (columns.length !== placeholders.length || columns.length !== args.length) {
      throw AppErrors.of('STORAGE_RDB_ERROR', []);
    }
    const row = new Map<string, RdbValue>();
    table.columns.forEach((column: ColumnDef, name: string): void => {
      row.set(name, null);
    });
    for (let index = 0; index < columns.length; index++) {
      InMemoryRdbStore.requirePlaceholder(placeholders[index]);
      if (!table.columns.has(columns[index])) {
        throw AppErrors.of('STORAGE_RDB_ERROR', []);
      }
      row.set(columns[index], args[index]);
    }
    const key = InMemoryRdbStore.primaryKeyOf(table, row);
    if (table.rows.has(key)) {
      if (mode === 'OR IGNORE') {
        return;
      }
      if (mode !== 'OR REPLACE') {
        throw AppErrors.of('STORAGE_RDB_ERROR', []);
      }
    }
    table.rows.set(key, row);
  }

  private updateRows(sql: string, args: ReadonlyArray<RdbValue>): void {
    const match = /^UPDATE ([A-Za-z0-9_]+) SET (.+) WHERE (.+)$/i.exec(sql);
    if (match === null) {
      throw AppErrors.of('STORAGE_RDB_ERROR', []);
    }
    const table = this.requireTable(match[1]);
    const assignments = InMemoryRdbStore.splitTopLevel(match[2]);
    const whereColumns = InMemoryRdbStore.parseWhere(match[3]);
    if (assignments.length + whereColumns.length !== args.length) {
      throw AppErrors.of('STORAGE_RDB_ERROR', []);
    }
    const setColumns: string[] = [];
    for (let index = 0; index < assignments.length; index++) {
      const pair = /^([A-Za-z0-9_]+) = \?$/i.exec(assignments[index].trim());
      if (pair === null || !table.columns.has(pair[1])) {
        throw AppErrors.of('STORAGE_RDB_ERROR', []);
      }
      setColumns.push(pair[1]);
    }
    for (let index = 0; index < whereColumns.length; index++) {
      if (!table.columns.has(whereColumns[index])) {
        throw AppErrors.of('STORAGE_RDB_ERROR', []);
      }
    }
    table.rows.forEach((row: Map<string, RdbValue>): void => {
      let matches = true;
      for (let index = 0; index < whereColumns.length; index++) {
        if (row.get(whereColumns[index]) !== args[assignments.length + index]) {
          matches = false;
          break;
        }
      }
      if (matches) {
        for (let index = 0; index < setColumns.length; index++) {
          row.set(setColumns[index], args[index]);
        }
      }
    });
  }

  private deleteRows(sql: string, args: ReadonlyArray<RdbValue>): void {
    const match = /^DELETE FROM ([A-Za-z0-9_]+)(?: WHERE (.+))?$/i.exec(sql);
    if (match === null) {
      throw AppErrors.of('STORAGE_RDB_ERROR', []);
    }
    const table = this.requireTable(match[1]);
    if (match[2] === undefined) {
      table.rows.clear();
      return;
    }
    const whereColumns = InMemoryRdbStore.parseWhere(match[2]);
    if (whereColumns.length !== args.length) {
      throw AppErrors.of('STORAGE_RDB_ERROR', []);
    }
    for (let index = 0; index < whereColumns.length; index++) {
      if (!table.columns.has(whereColumns[index])) {
        throw AppErrors.of('STORAGE_RDB_ERROR', []);
      }
    }
    const keys: string[] = [];
    table.rows.forEach((row: Map<string, RdbValue>, key: string): void => {
      let matches = true;
      for (let index = 0; index < whereColumns.length; index++) {
        if (row.get(whereColumns[index]) !== args[index]) {
          matches = false;
          break;
        }
      }
      if (matches) {
        keys.push(key);
      }
    });
    for (let index = 0; index < keys.length; index++) {
      table.rows.delete(keys[index]);
    }
  }

  private queryInternal(sql: string, args: ReadonlyArray<RdbValue>): ReadonlyArray<RdbRow> {
    const match = /^SELECT (.+) FROM ([A-Za-z0-9_]+)([\s\S]*)$/i.exec(sql.trim());
    if (match === null) {
      throw AppErrors.of('STORAGE_RDB_ERROR', []);
    }
    const table = this.requireTable(match[2]);
    const selectText = match[1].trim();
    const rest = match[3].trim();
    let whereColumns: string[] = [];
    const whereArgs: RdbValue[] = [];
    let orderColumn = '';
    let orderDesc = false;
    let limit = -1;
    let remainder = rest;

    if (/^WHERE /i.test(remainder)) {
      let clauseEnd = remainder.length;
      const upper = remainder.toUpperCase();
      const orderIndex = upper.indexOf(' ORDER BY ');
      const limitIndex = upper.indexOf(' LIMIT ');
      if (orderIndex >= 0 && orderIndex < clauseEnd) {
        clauseEnd = orderIndex;
      }
      if (limitIndex >= 0 && limitIndex < clauseEnd) {
        clauseEnd = limitIndex;
      }
      const whereText = remainder.substring(6, clauseEnd).trim();
      whereColumns = InMemoryRdbStore.parseWhere(whereText);
      if (whereColumns.length !== args.length) {
        throw AppErrors.of('STORAGE_RDB_ERROR', []);
      }
      for (let index = 0; index < whereColumns.length; index++) {
        if (!table.columns.has(whereColumns[index])) {
          throw AppErrors.of('STORAGE_RDB_ERROR', []);
        }
        whereArgs.push(args[index]);
      }
      remainder = remainder.substring(clauseEnd).trim();
    } else if (args.length > 0) {
      throw AppErrors.of('STORAGE_RDB_ERROR', []);
    }
    const orderMatch = /^ORDER BY ([A-Za-z0-9_]+) (ASC|DESC)/i.exec(remainder);
    if (orderMatch !== null) {
      if (!table.columns.has(orderMatch[1])) {
        throw AppErrors.of('STORAGE_RDB_ERROR', []);
      }
      orderColumn = orderMatch[1];
      orderDesc = orderMatch[2].toUpperCase() === 'DESC';
      remainder = remainder.substring(orderMatch[0].length).trim();
    }
    const limitMatch = /^LIMIT ([0-9]+)$/i.exec(remainder);
    if (limitMatch !== null) {
      limit = Number.parseInt(limitMatch[1], 10);
      remainder = '';
    }
    if (remainder.length > 0) {
      throw AppErrors.of('STORAGE_RDB_ERROR', []);
    }

    const selected: string[] = [];
    if (selectText === '*') {
      table.columns.forEach((column: ColumnDef, name: string): void => {
        selected.push(name);
      });
    } else {
      const parts = selectText.split(',');
      for (let index = 0; index < parts.length; index++) {
        const name = parts[index].trim();
        if (!table.columns.has(name)) {
          throw AppErrors.of('STORAGE_RDB_ERROR', []);
        }
        selected.push(name);
      }
    }

    let rows: Array<Map<string, RdbValue>> = [];
    table.rows.forEach((row: Map<string, RdbValue>): void => {
      let matches = true;
      for (let index = 0; index < whereColumns.length; index++) {
        if (row.get(whereColumns[index]) !== whereArgs[index]) {
          matches = false;
          break;
        }
      }
      if (matches) {
        rows.push(row);
      }
    });
    if (orderColumn.length > 0) {
      rows.sort((left: Map<string, RdbValue>, right: Map<string, RdbValue>): number => {
        const a = left.get(orderColumn);
        const b = right.get(orderColumn);
        const compare = InMemoryRdbStore.compareValues(a, b);
        return orderDesc ? -compare : compare;
      });
    }
    if (limit >= 0 && rows.length > limit) {
      rows = rows.slice(0, limit);
    }
    const result: RdbRow[] = [];
    for (let rowIndex = 0; rowIndex < rows.length; rowIndex++) {
      const selectedRow = new Map<string, RdbValue>();
      for (let columnIndex = 0; columnIndex < selected.length; columnIndex++) {
        const cell = rows[rowIndex].get(selected[columnIndex]);
        selectedRow.set(selected[columnIndex], cell === undefined ? null : cell);
      }
      result.push(selectedRow);
    }
    return result;
  }

  private requireTable(name: string): FakeTable {
    const table = this.tables.get(name);
    if (table === undefined) {
      throw AppErrors.of('STORAGE_RDB_ERROR', []);
    }
    return table;
  }

  /** Parses `a = ? AND b = ?` into ordered column names, validating shape. */
  private static parseWhere(text: string): string[] {
    const trimmed = text.trim();
    if (trimmed.length === 0) {
      throw AppErrors.of('STORAGE_RDB_ERROR', []);
    }
    const parts = trimmed.split(/\s+AND\s+/i);
    const columns: string[] = [];
    for (let index = 0; index < parts.length; index++) {
      const match = /^([A-Za-z0-9_]+) = \?$/i.exec(parts[index].trim());
      if (match === null) {
        throw AppErrors.of('STORAGE_RDB_ERROR', []);
      }
      columns.push(match[1]);
    }
    return columns;
  }

  private static splitTopLevel(text: string): string[] {    const parts: string[] = [];
    let depth = 0;
    let current = '';
    for (let index = 0; index < text.length; index++) {
      const char = text.charAt(index);
      if (char === '(') {
        depth++;
      } else if (char === ')') {
        depth--;
      }
      if (char === ',' && depth === 0) {
        parts.push(current);
        current = '';
      } else {
        current += char;
      }
    }
    if (current.trim().length > 0) {
      parts.push(current);
    }
    return parts;
  }

  private static requirePlaceholder(value: string): void {
    if (value !== '?') {
      throw AppErrors.of('STORAGE_RDB_ERROR', []);
    }
  }

  private static primaryKeyOf(table: FakeTable, row: Map<string, RdbValue>): string {
    let key = '';
    for (let index = 0; index < table.primaryKey.length; index++) {
      const value = row.get(table.primaryKey[index]);
      if (value === undefined || value === null) {
        throw AppErrors.of('STORAGE_RDB_ERROR', []);
      }
      key += '|' + InMemoryRdbStore.valueKey(value);
    }
    return key;
  }

  private static valueKey(value: RdbValue): string {
    if (value instanceof Uint8Array) {
      return BytesUtil.hexLower(value);
    }
    if (value === null) {
      return 'null';
    }
    return String(value);
  }

  private static compareValues(left: RdbValue | undefined, right: RdbValue | undefined): number {
    const a = left === undefined || left === null ? '' : String(left);
    const b = right === undefined || right === null ? '' : String(right);
    if (a < b) {
      return -1;
    }
    if (a > b) {
      return 1;
    }
    return 0;
  }

  /** Test-only leak audit hook: every persisted scalar rendered as text. */
  dumpAllValuesForTest(): string[] {
    const values: string[] = [];
    this.tables.forEach((table: FakeTable): void => {
      table.rows.forEach((row: Map<string, RdbValue>): void => {
        row.forEach((value: RdbValue): void => {
          if (value instanceof Uint8Array) {
            values.push(BytesUtil.hexLower(value));
          } else if (value !== null) {
            values.push(String(value));
          }
        });
      });
    });
    return values;
  }

  tableNamesForTest(): string[] {
    const names: string[] = [];
    this.tables.forEach((table: FakeTable, name: string): void => {
      names.push(name);
    });
    names.sort();
    return names;
  }
}

export class InMemorySecretStore implements SecretStore {
  private readonly secrets: Map<string, Uint8Array> = new Map<string, Uint8Array>();
  failPut: boolean = false;
  failWith: boolean = false;
  failRemove: boolean = false;
  failList: boolean = false;
  putCalls: number = 0;
  withCalls: number = 0;
  removeCalls: number = 0;
  zeroizedViews: number = 0;
  lastView: Uint8Array | undefined = undefined;

  async put(alias: string, secret: SecureBytes): Promise<void> {
    const checked = SecretAlias.require(alias);
    this.putCalls++;
    if (this.failPut) {
      throw AppErrors.of('ASSET_IO_FAILED', []);
    }
    const copy = secret.withView((view: Uint8Array): Uint8Array => BytesUtil.copyOf(view));
    const previous = this.secrets.get(checked);
    if (previous !== undefined) {
      BytesUtil.zeroize(previous);
    }
    this.secrets.set(checked, copy);
  }

  async withSecret<T>(alias: string, fn: (secret: Uint8Array) => Promise<T>): Promise<T> {
    const checked = SecretAlias.require(alias);
    this.withCalls++;
    if (this.failWith) {
      throw AppErrors.of('ASSET_IO_FAILED', []);
    }
    const stored = this.secrets.get(checked);
    if (stored === undefined) {
      throw AppErrors.of('ASSET_NOT_FOUND', []);
    }
    const copy = BytesUtil.copyOf(stored);
    this.lastView = copy;
    try {
      return await fn(copy);
    } finally {
      BytesUtil.zeroize(copy);
      this.zeroizedViews++;
    }
  }

  async remove(alias: string): Promise<void> {
    const checked = SecretAlias.require(alias);
    this.removeCalls++;
    if (this.failRemove) {
      throw AppErrors.of('ASSET_IO_FAILED', []);
    }
    const stored = this.secrets.get(checked);
    if (stored === undefined) {
      throw AppErrors.of('ASSET_NOT_FOUND', []);
    }
    BytesUtil.zeroize(stored);
    this.secrets.delete(checked);
  }

  async list(prefix: string): Promise<ReadonlyArray<string>> {
    if (this.failList) {
      throw AppErrors.of('ASSET_IO_FAILED', []);
    }
    const aliases: string[] = [];
    this.secrets.forEach((value: Uint8Array, alias: string): void => {
      if (prefix.length === 0 || alias.startsWith(prefix)) {
        aliases.push(alias);
      }
    });
    aliases.sort();
    return aliases;
  }

  has(alias: string): boolean {
    return this.secrets.has(alias);
  }

  size(): number {
    return this.secrets.size;
  }

  peekHexForTest(alias: string): string | undefined {
    const value = this.secrets.get(alias);
    if (value === undefined) {
      return undefined;
    }
    return BytesUtil.hexLower(value);
  }

  /** Test-only: assert no stored buffer still contains the probe byte. */
  anyStoredBufferContains(value: number): boolean {
    let found = false;
    this.secrets.forEach((bytes: Uint8Array): void => {
      for (let index = 0; index < bytes.length; index++) {
        if (bytes[index] === value) {
          found = true;
        }
      }
    });
    return found;
  }

  zeroAllForTest(): void {
    this.secrets.forEach((bytes: Uint8Array): void => {
      BytesUtil.zeroize(bytes);
    });
    this.secrets.clear();
  }
}

export class FixedClock implements ClockPort {
  value: number;

  constructor(value: number) {
    this.value = value;
  }

  nowMs(): number {
    return this.value;
  }
}

export class SequenceIds implements IdPort {
  private counter: number = 0;

  newId(): string {
    this.counter++;
    return '123e4567-e89b-12d3-a456-' + String(this.counter).padStart(12, '0');
  }
}

export class SyncRandom implements RandomPort {
  private counter: number = 0;

  async nextBytes(length: number): Promise<Uint8Array> {
    return this.nextBytesSync(length);
  }

  nextBytesSync(length: number): Uint8Array {
    const bytes = new Uint8Array(length);
    for (let index = 0; index < length; index++) {
      this.counter++;
      bytes[index] = this.counter & 0xFF;
    }
    return bytes;
  }
}

export function expectAppCode(error: Error, code: string): boolean {
  return isAppCode(error, code);
}
