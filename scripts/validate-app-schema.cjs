// Offline validation of query strings emitted from the compiled production code.
const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const root = path.resolve(__dirname, '..');
const { buildClientSchema, parse, validate } = require(path.join(root, 'build/catalog-schema-tools/node_modules/graphql'));
const source = JSON.parse(fs.readFileSync(path.join(root, 'build/hardcover-schema.json'), 'utf8'));
const schema = buildClientSchema(source.data ?? source);
const queries = JSON.parse(execFileSync(path.join(root, 'build/app-core-checks'), ['--queries'], { encoding: 'utf8' }));
let failures = 0;
for (const query of queries) {
  try {
    const document = parse(query);
    const errors = validate(schema, document);
    for (const operation of document.definitions.filter(d => d.kind === 'OperationDefinition')) {
      if (operation.selectionSet.selections.length > 5) errors.push(new Error('Hardcover permits at most five top-level fields.'));
      if (!operation.name) errors.push(new Error('Exported regression queries should be named.'));
    }
    for (const error of errors) {
      process.stderr.write(`${error.message}\n${query}\n`);
      failures++;
    }
  } catch (error) {
    process.stderr.write(`${error.message}\n${query}\n`);
    failures++;
  }
}
if (failures) process.exit(1);
console.log(`Validated ${queries.length} production GraphQL queries against the local official Hardcover schema.`);
