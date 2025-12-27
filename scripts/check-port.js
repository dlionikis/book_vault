#!/usr/bin/env node

const net = require('net');

const port = process.argv[2] || 3000;

const server = net.createServer();

server.once('error', (err) => {
  if (err.code === 'EADDRINUSE') {
    console.error(`❌ Error: Port ${port} is already in use.`);
    console.error(`   Please kill the process using port ${port} before running contract tests.`);
    console.error(`   You can use: lsof -ti:${port} | xargs kill -9`);
    process.exit(1);
  } else {
    console.error(`Error checking port ${port}:`, err);
    process.exit(1);
  }
});

server.once('listening', () => {
  server.close();
  console.log(`✓ Port ${port} is available`);
  process.exit(0);
});

server.listen(port);
