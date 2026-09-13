const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const root = path.resolve(__dirname, '..');
const { buildClientSchema, parse, validate } = require(path.join(root, 'build/catalog-schema-tools/node_modules/graphql'));
const source = JSON.parse(fs.readFileSync(path.join(root, 'build/hardcover-schema.json'), 'utf8'));
const schema = buildClientSchema(source.data ?? source);
const queries = JSON.parse(execFileSync(process.execPath, [path.join(root, 'Tests/run-widget-cache-checks.cjs'), '--queries'], { encoding: 'utf8' }));
for (const query of queries) {
  const errors = validate(schema, parse(query));
  if (errors.length) throw new Error(errors.map(error => error.message).join('\n'));
}
console.log('Validated ' + queries.length + ' widget GraphQL queries against the local official Hardcover schema.');
