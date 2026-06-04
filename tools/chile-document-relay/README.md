# Vinabike Chile Document Relay

This small service fixes supplier PDF links that only answer from Chilean
networks. Run it on a Chilean machine or Chile-hosted VPS, then configure the
ERP browser fallback with:

```text
http://CHILE_HOST:8787/fetch-document
```

## Run

```bash
cd tools/chile-document-relay
cp relay.env.example .env
# edit .env and choose a strong DOCUMENT_RELAY_SHARED_TOKEN
set -a && . ./.env && set +a
npm start
```

Health check:

```bash
curl http://localhost:8787/health
```

Fetch test:

```bash
curl -X POST http://localhost:8787/fetch-document \
  -H "Content-Type: application/json" \
  -H "X-Vinabike-Relay-Token: change-this-token" \
  -d '{"url":"http://186.67.65.199:8000/utiles/getPdf.php?doc=..."}' \
  --output documento.pdf
```

## Security

The relay is intentionally allowlisted. By default it only fetches
`186.67.65.199`, so it cannot become a generic open proxy. If another supplier
needs the same treatment, add its host to `DOCUMENT_RELAY_ALLOWED_HOSTS`.

For a public endpoint, put it behind HTTPS and keep
`DOCUMENT_RELAY_SHARED_TOKEN` enabled.
