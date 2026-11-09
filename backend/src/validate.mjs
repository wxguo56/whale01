const DATE_TIME = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?(?:Z|[+-]\d{2}:\d{2})$/;

function typeMatches(type, value) {
  switch (type) {
    case "object": return value !== null && typeof value === "object" && !Array.isArray(value);
    case "array": return Array.isArray(value);
    case "string": return typeof value === "string";
    case "number": return typeof value === "number" && Number.isFinite(value);
    case "integer": return Number.isInteger(value);
    case "boolean": return typeof value === "boolean";
    case "null": return value === null;
    default: return true;
  }
}

export function validateSchema(schema, value, path = "$") {
  const errors = [];
  walk(schema, value, path, errors);
  return { ok: errors.length === 0, errors };
}

function walk(schema, value, path, errors) {
  if (!schema || typeof schema !== "object") return;

  if (Array.isArray(schema.oneOf)) {
    const matched = schema.oneOf.some((option) => validateSchema(option, value, path).ok);
    if (!matched) errors.push(`${path}: 不满足 oneOf 中任一分支`);
    return;
  }

  if (schema.enum && !schema.enum.includes(value)) {
    errors.push(`${path}: 值 ${JSON.stringify(value)} 不在枚举 ${JSON.stringify(schema.enum)} 内`);
    return;
  }

  const type = schema.type;
  if (type && !typeMatches(type, value)) {
    errors.push(`${path}: 期望 ${type}，实际为 ${value === null ? "null" : typeof value}`);
    return;
  }

  if (type === "object" || (!type && value !== null && typeof value === "object" && !Array.isArray(value))) {
    const required = schema.required ?? [];
    for (const key of required) {
      if (!(key in value)) errors.push(`${path}.${key}: 缺少必填字段`);
    }
    const properties = schema.properties ?? {};
    if (schema.additionalProperties === false) {
      for (const key of Object.keys(value)) {
        if (!(key in properties)) errors.push(`${path}.${key}: 不允许的额外字段`);
      }
    }
    for (const [key, child] of Object.entries(properties)) {
      if (key in value) walk(child, value[key], `${path}.${key}`, errors);
    }
  }

  if (type === "array" && Array.isArray(value)) {
    if (schema.minItems !== undefined && value.length < schema.minItems) {
      errors.push(`${path}: 至少需要 ${schema.minItems} 项`);
    }
    if (schema.maxItems !== undefined && value.length > schema.maxItems) {
      errors.push(`${path}: 最多允许 ${schema.maxItems} 项`);
    }
    if (schema.uniqueItems) {
      const seen = new Set(value.map((item) => JSON.stringify(item)));
      if (seen.size !== value.length) errors.push(`${path}: 数组元素必须唯一`);
    }
    if (schema.items) {
      value.forEach((item, index) => walk(schema.items, item, `${path}[${index}]`, errors));
    }
  }

  if (type === "string" && typeof value === "string") {
    if (schema.minLength !== undefined && value.length < schema.minLength) {
      errors.push(`${path}: 长度不能小于 ${schema.minLength}`);
    }
    if (schema.maxLength !== undefined && value.length > schema.maxLength) {
      errors.push(`${path}: 长度不能超过 ${schema.maxLength}`);
    }
    if (schema.pattern && !new RegExp(schema.pattern).test(value)) {
      errors.push(`${path}: 不匹配格式 ${schema.pattern}`);
    }
    if (schema.format === "date-time" && (!DATE_TIME.test(value) || Number.isNaN(Date.parse(value)))) {
      errors.push(`${path}: 必须是带时区偏移的 ISO 8601 时间`);
    }
  }

  if ((type === "number" || type === "integer") && typeof value === "number") {
    if (schema.minimum !== undefined && value < schema.minimum) errors.push(`${path}: 不能小于 ${schema.minimum}`);
    if (schema.maximum !== undefined && value > schema.maximum) errors.push(`${path}: 不能大于 ${schema.maximum}`);
  }
}
