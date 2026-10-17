import { readFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { stripTypeScriptTypes } from 'node:module';

const FALLBACK_EXTENSIONS = ['.ets', '.ts', '.mjs', '.js'];
const INDEX_FILES = ['index.ets', 'index.ts', 'index.mjs', 'index.js'];

/**
 * Resolve extensionless relative imports to .ets/.ts/.mjs/.js.
 * This lets host tests import pure ArkTS/TypeScript modules that contain no
 * ArkUI or @ohos platform dependencies.
 */
export async function resolve(specifier, context, nextResolve) {
  if (specifier.startsWith('.') || specifier.startsWith('/')) {
    const base = specifier.startsWith('/')
      ? new URL(`file://${specifier}`)
      : new URL(specifier, context.parentURL);
    if (existsSync(fileURLToPath(base))) {
      return { url: base.href, shortCircuit: true };
    }
    if (!path.extname(base.pathname)) {
      for (const extension of FALLBACK_EXTENSIONS) {
        const candidate = new URL(base.href + extension);
        if (existsSync(fileURLToPath(candidate))) {
          return { url: candidate.href, shortCircuit: true };
        }
      }
      const directory = base.href.endsWith('/') ? base.href : `${base.href}/`;
      for (const indexFile of INDEX_FILES) {
        const candidate = new URL(directory + indexFile);
        if (existsSync(fileURLToPath(candidate))) {
          return { url: candidate.href, shortCircuit: true };
        }
      }
    }
  }
  return nextResolve(specifier, context);
}

/**
 * Load .ets/.ts as ESM after stripping TypeScript syntax.
 * ArkTS decorators/structs are intentionally unsupported: host tests must not
 * import UI or platform-dependent files.
 */
export async function load(url, context, nextLoad) {
  if (url.endsWith('.ets') || url.endsWith('.ts')) {
    const source = await readFile(fileURLToPath(url), 'utf8');
    const transformed = stripTypeScriptTypes(source, {
      mode: 'transform',
      sourceMap: false,
    });
    return { format: 'module', source: transformed, shortCircuit: true };
  }
  return nextLoad(url, context);
}
