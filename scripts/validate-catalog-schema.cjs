// Run after test-catalog-editing.sh, with the official schema and graphql package installed under build/.
const fs = require('node:fs');
const { execFileSync } = require('node:child_process');
const { buildClientSchema, parse, validate } = require('../build/catalog-schema-tools/node_modules/graphql');
const schema = buildClientSchema(JSON.parse(fs.readFileSync('build/hardcover-schema.json', 'utf8')).data);
const queries = JSON.parse(execFileSync('build/catalog-editing-checks', ['--queries'], { encoding: 'utf8' }));
let failures = 0;
for (const query of queries) {
  const document = parse(query);
  const errors = validate(schema, document);
  for (const operation of document.definitions.filter(d => d.kind === 'OperationDefinition')) {
    if (operation.selectionSet.selections.length > 5) {
      errors.push(new Error('Hardcover allows at most 5 top-level operations.'));
    }
    if (operation.name?.value === 'CatalogOverview' && operation.selectionSet.selections.length !== 2) {
      errors.push(new Error('Editor overview must cost only 2 top-level queries.'));
    }
  }
  for (const error of errors) {
    process.stderr.write(`${error.message}\n${query}\n`);
    failures++;
  }
}
if (failures) process.exit(1);
console.log(`Validated ${queries.length} GraphQL operations against the official Hardcover schema.`);
