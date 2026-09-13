const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { execFileSync } = require('node:child_process');

const root = path.resolve(__dirname, '..');
const read = name => fs.readFileSync(path.join(root, name), 'utf8');
const readers = read('ReadingProgressWidget/WidgetReaders.swift');
const query = readers.match(/static let quoteQuery = """([\s\S]*?)"""/)[1];
const fields = read('ReadingProgressWidget/LibraryAPI.swift').match(/static let fields = """([\s\S]*?)"""/)[1];
const selectedQuery = readers.match(/static let selectedBooksQuery = """([\s\S]*?)"""/)[1].replace('\\(LibraryAPI.fields)', fields);
if (process.argv.includes('--queries')) {
  process.stdout.write(JSON.stringify([query, selectedQuery]));
  process.exit(0);
}

const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'softcover-widget-checks-'));
try {
  const network = read('ReadingProgressWidget/HardcoverNetwork.swift');
  const library = read('ReadingProgressWidget/LibraryAPI.swift');
  const image = read('Hardcover Reading Widget/AsyncCachedImage.swift');
  const disk = image.slice(image.indexOf('private actor DiskCache {'), image.indexOf('// MARK: - Request coalescing'));
  const release = read('ReleaseCountdownWidget.swift');
  const dateHelpers = release.slice(release.indexOf('private func daysUntil('), release.indexOf('// MARK: - Small:'));
  if ((disk.match(/contentsOfDirectory/g) || []).length !== 1) throw new Error('Disk cache must reconcile its directory in one place only.');
  if (!image.includes('public enum AsyncCachedImagePixelUnit: Sendable')) throw new Error('Image pixel unit must be Sendable.');
  const source = [
    read('Tests/WidgetCacheSupport.swift'),
    network.slice(0, network.indexOf('actor HardcoverRequestScheduler {')),
    read('ReadingProgressWidget/BookProgress.swift'),
    library.slice(library.indexOf('enum LibrarySnapshot {')),
    read('ReadingProgressWidget/WidgetSync.swift').replace('import WidgetKit', ''),
    readers,
    disk,
    dateHelpers,
    read('Tests/WidgetCacheChecks.swift')
  ].join('\n');
  const swift = path.join(temp, 'WidgetChecks.swift');
  const binary = path.join(temp, 'widget-checks');
  fs.writeFileSync(swift, source);
  execFileSync('xcrun', ['swiftc', '-parse-as-library', '-swift-version', '5', '-strict-concurrency=complete', '-warnings-as-errors', '-O', swift, '-o', binary], { stdio: 'inherit', cwd: root });
  execFileSync(binary, { stdio: 'inherit', cwd: root });
} finally {
  fs.rmSync(temp, { recursive: true, force: true });
}
