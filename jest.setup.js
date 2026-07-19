// Learn more: https://github.com/testing-library/jest-dom
import '@testing-library/jest-dom';

// Deterministic secret for real JWT signing/verification in tests
// (lib/jwt.ts throws without NEXTAUTH_SECRET; don't depend on developer .env files)
process.env.NEXTAUTH_SECRET = process.env.NEXTAUTH_SECRET || 'jest-test-secret-do-not-use-in-prod';

// Polyfill TextEncoder/TextDecoder for undici (required by @fastify/busboy)
const { TextEncoder, TextDecoder } = require('util');
global.TextEncoder = TextEncoder;
global.TextDecoder = TextDecoder;

// Polyfill Web Fetch API for API route tests using undici.
// undici 8's fetch implementation reads the Web Streams globals off `global`,
// which the jsdom test environment doesn't define (undici 5 didn't need them).
// Provide them from Node's built-in `stream/web` before requiring undici.
if (typeof global.ReadableStream === 'undefined') {
  const { ReadableStream, WritableStream, TransformStream } = require('node:stream/web');
  global.ReadableStream = ReadableStream;
  global.WritableStream = WritableStream;
  global.TransformStream = TransformStream;
}
if (typeof global.MessagePort === 'undefined') {
  global.MessagePort = require('node:worker_threads').MessagePort;
}
if (typeof global.Request === 'undefined') {
  const { Request, Response, Headers, FormData } = require('undici');
  global.Request = Request;
  global.Response = Response;
  global.Headers = Headers;
  global.FormData = FormData;
}
