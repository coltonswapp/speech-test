/**
 * Deterministic JSON for feedback HMAC hashes.
 * Object keys are sorted; `undefined` properties are omitted; arrays keep order.
 */

export function canonicalJSON(value: unknown): string {
  return encode(value);
}

function encode(value: unknown): string {
  if (value === null) return "null";
  switch (typeof value) {
    case "boolean":
      return value ? "true" : "false";
    case "number":
      return encodeNumber(value);
    case "string":
      return JSON.stringify(value);
    case "object":
      break;
    default:
      throw new Error("unsupported JSON value");
  }
  if (Array.isArray(value)) {
    return `[${value.map((item) => encode(item)).join(",")}]`;
  }
  const record = value as Record<string, unknown>;
  const keys = Object.keys(record)
    .filter((key) => record[key] !== undefined)
    .sort();
  return `{${keys.map((key) => `${JSON.stringify(key)}:${encode(record[key])}`).join(",")}}`;
}

function encodeNumber(value: number): string {
  if (!Number.isFinite(value)) {
    throw new Error("unsupported JSON number");
  }
  if (Object.is(value, -0)) return "0";
  if (Number.isInteger(value) && Math.abs(value) <= Number.MAX_SAFE_INTEGER) {
    return String(value);
  }
  return JSON.stringify(value);
}

/** Parsed JSON with `undefined` fields removed, safe to store in Firestore. */
export function jsonReady(value: unknown): unknown {
  return JSON.parse(canonicalJSON(value)) as unknown;
}
