#!/usr/bin/env tsx

/**
 * OpenAPI Endpoint Coverage Checker
 *
 * Compares OpenAPI spec paths against actual app/api routes to ensure:
 * 1. All API routes are documented in OpenAPI spec
 * 2. All OpenAPI paths have corresponding implementations
 *
 * Usage: tsx scripts/check-endpoint-coverage.ts
 *
 * Exit codes:
 * - 0: All endpoints match
 * - 1: Mismatches detected
 */

import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import yaml from 'yaml';

// The package is ESM ("type": "module"), so __dirname isn't defined.
const __dirname = path.dirname(fileURLToPath(import.meta.url));

interface EndpointInfo {
  path: string;
  methods: string[];
}

interface CoverageResult {
  undocumented: EndpointInfo[];
  unimplemented: EndpointInfo[];
  matched: EndpointInfo[];
}

/**
 * Parse OpenAPI spec and extract all endpoint paths with their HTTP methods
 */
function parseOpenAPISpec(specPath: string): Map<string, Set<string>> {
  const specContent = fs.readFileSync(specPath, 'utf-8');
  const spec = yaml.parse(specContent);

  const endpoints = new Map<string, Set<string>>();

  for (const [path, pathItem] of Object.entries(spec.paths || {})) {
    const methods = new Set<string>();

    // Check for each HTTP method
    for (const method of ['get', 'post', 'put', 'delete', 'patch']) {
      if ((pathItem as any)[method]) {
        methods.add(method.toUpperCase());
      }
    }

    if (methods.size > 0) {
      endpoints.set(path, methods);
    }
  }

  return endpoints;
}

/**
 * Recursively scan app/api directory and extract all route files
 */
function scanAPIRoutes(apiDir: string): Map<string, Set<string>> {
  const endpoints = new Map<string, Set<string>>();

  function scanDirectory(dir: string, basePath: string = '') {
    const entries = fs.readdirSync(dir, { withFileTypes: true });

    for (const entry of entries) {
      const fullPath = path.join(dir, entry.name);

      if (entry.isDirectory()) {
        // Handle dynamic route segments: [id] -> {id}, [...path] -> {path}
        let segmentName = entry.name;

        if (entry.name.startsWith('[') && entry.name.endsWith(']')) {
          // Remove brackets
          const paramName = entry.name.slice(1, -1);

          // Handle catch-all routes: [...path] -> {path}
          const actualParam = paramName.startsWith('...') ? paramName.slice(3) : paramName;

          segmentName = `{${actualParam}}`;
        }

        scanDirectory(fullPath, `${basePath}/${segmentName}`);
      } else if (entry.name === 'route.ts') {
        // Read the route file to determine which HTTP methods are exported
        const routeContent = fs.readFileSync(fullPath, 'utf-8');
        const methods = new Set<string>();

        // Check for exported HTTP method handlers
        // Supports both: `export async function GET` and `export const GET = withLogging(...)`
        for (const method of ['GET', 'POST', 'PUT', 'DELETE', 'PATCH']) {
          const functionPattern = `export async function ${method}`;
          const constPattern = `export const ${method}`;
          if (routeContent.includes(functionPattern) || routeContent.includes(constPattern)) {
            methods.add(method);
          }
        }

        // Convert app/api path to OpenAPI path format
        const apiPath = `/api${basePath}`;

        if (methods.size > 0) {
          endpoints.set(apiPath, methods);
        }
      }
    }
  }

  scanDirectory(apiDir);
  return endpoints;
}

/**
 * Compare spec endpoints against implementation endpoints
 */
function compareEndpoints(
  specEndpoints: Map<string, Set<string>>,
  implEndpoints: Map<string, Set<string>>
): CoverageResult {
  const result: CoverageResult = {
    undocumented: [],
    unimplemented: [],
    matched: [],
  };

  // Find undocumented endpoints (in implementation but not in spec)
  for (const [path, methods] of implEndpoints) {
    // Skip special Next.js routes and internal (non-public-API) routes.
    // /api/cron/* is triggered by EventBridge with a CRON_SECRET bearer, never
    // by app clients, so it is intentionally not in the OpenAPI spec.
    if (
      path.includes('[...nextauth]') ||
      path.includes('[...path]') ||
      path.startsWith('/api/cron/')
    ) {
      continue;
    }

    const specMethods = specEndpoints.get(path);

    if (!specMethods) {
      // Entire endpoint is undocumented
      result.undocumented.push({
        path,
        methods: Array.from(methods).sort(),
      });
    } else {
      // Check for undocumented methods
      const missingMethods = Array.from(methods).filter((m) => !specMethods.has(m));
      if (missingMethods.length > 0) {
        result.undocumented.push({
          path,
          methods: missingMethods.sort(),
        });
      }

      // Track matched methods
      const matchedMethods = Array.from(methods).filter((m) => specMethods.has(m));
      if (matchedMethods.length > 0) {
        result.matched.push({
          path,
          methods: matchedMethods.sort(),
        });
      }
    }
  }

  // Find unimplemented endpoints (in spec but not in implementation)
  for (const [path, methods] of specEndpoints) {
    const implMethods = implEndpoints.get(path);

    if (!implMethods) {
      // Entire endpoint is unimplemented
      result.unimplemented.push({
        path,
        methods: Array.from(methods).sort(),
      });
    } else {
      // Check for unimplemented methods
      const missingMethods = Array.from(methods).filter((m) => !implMethods.has(m));
      if (missingMethods.length > 0) {
        result.unimplemented.push({
          path,
          methods: missingMethods.sort(),
        });
      }
    }
  }

  return result;
}

/**
 * Format endpoint info for display
 */
function formatEndpoint(endpoint: EndpointInfo): string {
  return `${endpoint.path} [${endpoint.methods.join(', ')}]`;
}

/**
 * Main execution
 */
function main() {
  const projectRoot = path.resolve(__dirname, '..');
  const specPath = path.join(projectRoot, 'docs/api/openapi.yaml');
  const apiDir = path.join(projectRoot, 'app/api');

  console.log('🔍 Checking OpenAPI endpoint coverage...\n');

  // Validate paths exist
  if (!fs.existsSync(specPath)) {
    console.error(`❌ OpenAPI spec not found: ${specPath}`);
    process.exit(1);
  }

  if (!fs.existsSync(apiDir)) {
    console.error(`❌ API directory not found: ${apiDir}`);
    process.exit(1);
  }

  // Parse spec and implementation
  const specEndpoints = parseOpenAPISpec(specPath);
  const implEndpoints = scanAPIRoutes(apiDir);

  console.log(`📋 OpenAPI spec: ${specEndpoints.size} endpoints`);
  console.log(`📁 Implementation: ${implEndpoints.size} endpoints (excluding special routes)\n`);

  // Compare endpoints
  const result = compareEndpoints(specEndpoints, implEndpoints);

  let hasErrors = false;

  // Report undocumented endpoints
  if (result.undocumented.length > 0) {
    hasErrors = true;
    console.log('❌ UNDOCUMENTED ENDPOINTS (implemented but not in OpenAPI spec):');
    for (const endpoint of result.undocumented) {
      console.log(`   ${formatEndpoint(endpoint)}`);
    }
    console.log('');
  }

  // Report unimplemented endpoints
  if (result.unimplemented.length > 0) {
    hasErrors = true;
    console.log('❌ UNIMPLEMENTED ENDPOINTS (in OpenAPI spec but not implemented):');
    for (const endpoint of result.unimplemented) {
      console.log(`   ${formatEndpoint(endpoint)}`);
    }
    console.log('');
  }

  // Report success
  if (!hasErrors) {
    console.log('✅ All endpoints match!');
    console.log(`   ${result.matched.length} endpoints properly documented and implemented\n`);
    process.exit(0);
  } else {
    console.log('💡 To fix:');
    if (result.undocumented.length > 0) {
      console.log('   - Add undocumented endpoints to docs/api/openapi.yaml');
    }
    if (result.unimplemented.length > 0) {
      console.log('   - Implement missing endpoints in app/api/');
      console.log('   - OR remove from OpenAPI spec if no longer needed');
    }
    console.log('');
    process.exit(1);
  }
}

// Run the script
main();
