// Learn more: https://github.com/testing-library/jest-dom
import '@testing-library/jest-dom';

// Polyfill TextEncoder/TextDecoder for undici (required by @fastify/busboy)
const { TextEncoder, TextDecoder } = require('util');
global.TextEncoder = TextEncoder;
global.TextDecoder = TextDecoder;

// Polyfill Web Fetch API for API route tests using undici (Node.js 18+ compatible)
if (typeof global.Request === 'undefined') {
  const { Request, Response, Headers, FormData } = require('undici');
  global.Request = Request;
  global.Response = Response;
  global.Headers = Headers;
  global.FormData = FormData;
}
