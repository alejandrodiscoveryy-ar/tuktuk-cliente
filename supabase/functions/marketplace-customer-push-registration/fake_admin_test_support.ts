// Deterministic in-memory Supabase test double. Never connects to a database.
// deno-lint-ignore-file no-explicit-any
export class FakeAdmin {
  tables: Record<string, any[]> = {};
  calls: any[] = [];
  failures = new Set<string>();
  beforeQuery?: (table: string, operation: string) => void;
  onRpc: (name: string, args: any) => any = () => ({ data: [], error: null });
  from(table: string) { return new Query(this, table); }
  rpc(name: string, args: any) {
    this.calls.push({ rpc: name, args });
    return Promise.resolve(this.onRpc(name, args));
  }
}
class Query {
  filters: Array<(row: any) => boolean> = [];
  fields = "*"; operation = "select"; values: any; single = false; head = false;
  constructor(readonly db: FakeAdmin, readonly table: string) {}
  select(fields = "*", options: any = {}) { this.fields = fields; this.head = options.head ?? false; return this; }
  eq(key: string, value: any) { this.filters.push(row => row[key] === value); return this; }
  gt(key: string, value: any) { this.filters.push(row => row[key] > value); return this; }
  in(key: string, values: any[]) { this.filters.push(row => values.includes(row[key])); return this; }
  update(values: any) { this.operation = "update"; this.values = values; return this; }
  insert(values: any) { this.operation = "insert"; this.values = values; return this; }
  maybeSingle() { this.single = true; return this; }
  then(resolve: (value: any) => any, reject?: (reason: any) => any) {
    return Promise.resolve().then(() => {
      this.db.beforeQuery?.(this.table, this.operation);
      this.db.calls.push({ table: this.table, operation: this.operation });
      if (this.db.failures.has(this.table)) return { data: null, error: { code: "unavailable" } };
      const table = this.db.tables[this.table] ??= [];
      let rows = table.filter(row => this.filters.every(filter => filter(row)));
      if (this.operation === "insert") {
        if (table.some(row => row.token_hash === this.values.token_hash || row.secret_hash === this.values.secret_hash)) return { data: null, error: { code: "23505" } };
        const row = { id: crypto.randomUUID(), ...this.values };
        table.push(row); rows = [row];
      } else if (this.operation === "update") rows.forEach(row => Object.assign(row, this.values));
      const data = rows.map(row => this.fields === "*" ? { ...row } :
        Object.fromEntries(this.fields.split(",").map(key => [key, row[key]])));
      return { data: this.head ? null : this.single ? data[0] ?? null : data, error: null, count: rows.length };
    }).then(resolve, reject);
  }
}
