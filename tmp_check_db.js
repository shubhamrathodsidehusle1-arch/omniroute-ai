const sqlite3 = require('better-sqlite3');
const db = new sqlite3('/app/data/storage.sqlite', {readonly: true});

const tables = db.prepare("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name").all();
console.log('=== TABLES ===');
tables.forEach(t => console.log('  ' + t.name));

// Check provider_connections columns
const cols = db.prepare('PRAGMA table_info(provider_connections)').all();
console.log('\n=== provider_connections cols ===');
cols.forEach(c => console.log('  ' + c.name + ' (' + c.type + ')'));

// All provider types in use
const providers = db.prepare('SELECT DISTINCT provider FROM provider_connections ORDER BY provider').all();
console.log('\n=== provider types in DB ===');
providers.forEach(p => console.log('  ' + p.provider));

db.close();
