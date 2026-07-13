# Textractor Webapp

Static site + Cloudflare Worker backend for the Textractor OCR platform.

## Quick Start

```bash
# From /Users/pounds_1/dev/Textractor
cd webapp
npm install
npm run dev
```

The dev server will start on **http://localhost:8788**.

## Endpoints

- `GET  /`           – Landing page (Tailwind, neon, responsive)
- `GET  /api/pricing – JSON pricing data
- `POST /api/ocr`    – OCR via Cloudflare Workers AI
- `GET  /health`     – Health check

## Project Structure

```
webapp/
├── frontend/        (static HTML / Tailwind / assets)
│   └── index.html
├── backend/
│   ├── src/index.js (Worker entry)
│   └── wrangler.toml
└── package.json
```

## Deploy

```bash
# Frontend → Cloudflare Pages
npm run deploy

# Backend → Cloudflare Worker (run in /webapp/backend)
wrangler publish
```

## Version

**v2.0.0** – Multi-display OCR, Continuity Camera, webapp launch.
