/*
 * YaoCore C-01 shared name/value pair.
 * Producer: agent:implementation-engineer | Task: T-06 / wp-012-foundation
 * Contract: DES-A §3.1/§3.7/§4.1.8
 *
 * Pure value object. Never place secrets in `value`.
 */
export class NameValue {
  readonly name: string;
  readonly value: string;

  constructor(name: string, value: string) {
    this.name = name;
    this.value = value;
  }
}
