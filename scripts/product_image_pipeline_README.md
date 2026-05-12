# Product Image Quality Pipeline

Conservative product-image tooling for Vinabike ecommerce images.

The pipeline has three modes:

1. `audit`
   - Measures dimensions, blur, file size, subject fill, background quality.
   - Writes `audit.csv`, `audit.jsonl`, and `audit_summary.json`.

2. `process`
   - Creates safe review copies only.
   - Crops obvious whitespace, applies a controlled upscale for tiny sources, centers product on white square canvas, exports WebP.
   - Never uploads or replaces live images.

3. `ai-test`
   - Runs the safe cleanup.
   - Optionally runs Real-ESRGAN when a binary is provided.
   - Writes side-by-side comparison sheets for manual approval.

4. `openai-test`
   - Runs the safe cleanup.
   - Uses the OpenAI Images API to generate a premium product-photo candidate.
   - Writes the prompt metadata and side-by-side comparison sheets for manual approval.

## Runtime

Use the bundled Codex Python when available:

```bash
/Users/Claudio/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 scripts/product_image_pipeline.py audit --input path/to/image.jpg
```

The script needs Pillow and NumPy. The bundled runtime already includes them.

## Examples

Audit one image:

```bash
python3 scripts/product_image_pipeline.py audit --input product.jpg
```

Safely standardize one image:

```bash
python3 scripts/product_image_pipeline.py process \
  --input product.jpg \
  --max-safe-upscale 8 \
  --output-dir reports/product_image_test
```

Audit/process a CSV:

```bash
python3 scripts/product_image_pipeline.py process \
  --manifest products.csv \
  --source-column image_url \
  --id-column id \
  --name-column name \
  --output-dir reports/product_image_batch
```

AI upscaling test with Real-ESRGAN:

```bash
python3 scripts/product_image_pipeline.py ai-test \
  --input product.jpg \
  --realesrgan-bin /path/to/realesrgan-ncnn-vulkan \
  --realesrgan-model-dir /path/to/models \
  --realesrgan-model realesrgan-x4plus \
  --realesrgan-scale 4 \
  --output-dir reports/product_image_ai_test
```

If the `models` folder is next to the Real-ESRGAN binary, the script detects it automatically.

AI enhancement test with OpenAI:

```bash
OPENAI_API_KEY=... python3 scripts/product_image_pipeline.py openai-test \
  --input product.jpg \
  --openai-model gpt-image-1.5 \
  --openai-quality high \
  --openai-size 1024x1024 \
  --output-dir reports/product_image_openai_test
```

If Real-ESRGAN is not installed yet, you can still create a non-AI upscale baseline:

```bash
python3 scripts/product_image_pipeline.py ai-test \
  --input product.jpg \
  --allow-lanczos-fallback \
  --output-dir reports/product_image_ai_test
```

That fallback is only a comparison baseline. It is not AI.

## Safety Rules

- Do not overwrite originals.
- Do not upload processed images automatically.
- Review comparison sheets before replacing product images.
- Use AI modes for tests first, especially for packaging with text/logos.
- If AI changes product labels, logos, colors, or physical details, reject that output.

## Output Folders

- `originals/` copied/downloaded input files
- `processed/` safe WebP outputs
- `ai_previews/` Real-ESRGAN, OpenAI, or baseline upscale outputs
- `comparisons/` side-by-side review images
- `audit.csv` image quality report
- `process_report.csv` generated output report
