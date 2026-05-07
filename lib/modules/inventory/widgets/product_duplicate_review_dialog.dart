import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../shared/services/image_service.dart';
import '../models/inventory_models.dart';
import '../models/product_duplicate_candidate.dart';

class ProductDuplicateSummaryButton extends StatelessWidget {
  const ProductDuplicateSummaryButton({
    super.key,
    required this.candidates,
    required this.onPressed,
    this.isEnabled = true,
  });

  final List<ProductDuplicateCandidate> candidates;
  final VoidCallback onPressed;
  final bool isEnabled;

  @override
  Widget build(BuildContext context) {
    if (candidates.isEmpty) {
      return OutlinedButton.icon(
        onPressed: isEnabled ? onPressed : null,
        icon: const Icon(Icons.search, size: 14),
        label: const Text('Revisar'),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          textStyle: const TextStyle(fontSize: 12),
        ),
      );
    }

    final top = candidates.first;
    return InkWell(
      onTap: isEnabled ? onPressed : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.amber.shade50,
          border: Border.all(color: Colors.amber.shade200),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded,
                size: 16, color: Colors.amber.shade800),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '${candidates.length} parecido${candidates.length == 1 ? '' : 's'} • ${(top.overallScore * 100).round()}%',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.amber.shade900,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, size: 16),
          ],
        ),
      ),
    );
  }
}

class ProductDuplicateReviewDialog extends StatelessWidget {
  const ProductDuplicateReviewDialog({
    super.key,
    required this.rows,
    this.title = 'Revisión de parecidos',
    this.subtitle,
    this.footerText,
    this.closeLabel = 'Volver a la tabla',
    this.emptyActionLabel,
  });

  final List<ProductDuplicateReviewRow> rows;
  final String title;
  final String? subtitle;
  final String? footerText;
  final String closeLabel;
  final String? emptyActionLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenSize = MediaQuery.of(context).size;

    return Dialog(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: math.min(screenSize.width * 0.82, 1100),
        height: math.min(screenSize.height * 0.82, 760),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(
                  bottom: BorderSide(
                    color:
                        theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.find_in_page_outlined,
                      color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: rows.length,
                separatorBuilder: (_, __) => const SizedBox(height: 14),
                itemBuilder: (context, index) => ProductDuplicateReviewCard(
                  row: rows[index],
                  rowLabel: 'Fila ${index + 1}',
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(
                  top: BorderSide(
                    color:
                        theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                  ),
                ),
              ),
              child: Row(
                children: [
                  if (footerText != null)
                    Expanded(
                      child: Text(
                        footerText!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  else
                    const Spacer(),
                  const SizedBox(width: 12),
                  if (emptyActionLabel != null)
                    OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.add_box_outlined),
                      label: Text(emptyActionLabel!),
                    )
                  else
                    FilledButton.tonal(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(closeLabel),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ProductDuplicateReviewCard extends StatelessWidget {
  const ProductDuplicateReviewCard({
    super.key,
    required this.row,
    required this.rowLabel,
  });

  final ProductDuplicateReviewRow row;
  final String rowLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 58,
                  height: 58,
                  child: row.imageUrl != null
                      ? ImageService.buildProductImage(
                          imageUrl: row.imageUrl,
                          size: 58,
                        )
                      : Container(
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: Icon(
                            Icons.inventory_2_outlined,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rowLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      row.title.trim().isEmpty
                          ? 'Producto sin nombre'
                          : row.title,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    if (row.subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        row.subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (row.badges.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: row.badges
                            .map((badge) => ProductDuplicateMetricChip(
                                  label: badge,
                                  tone: ProductDuplicateChipTone.neutral,
                                ))
                            .toList(growable: false),
                      ),
                    ],
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${row.candidates.length} candidato${row.candidates.length == 1 ? '' : 's'}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.orange.shade700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...row.candidates.map(
            (candidate) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ProductDuplicateCandidateTile(
                candidate: candidate,
                onSelected: row.onCandidateSelected == null
                    ? null
                    : () => row.onCandidateSelected!(candidate.product),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ProductDuplicateCandidateTile extends StatelessWidget {
  const ProductDuplicateCandidateTile({
    super.key,
    required this.candidate,
    this.onSelected,
  });

  final ProductDuplicateCandidate candidate;
  final VoidCallback? onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final product = candidate.product;
    final scorePercent = (candidate.overallScore * 100).round();

    final content = Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 52,
              height: 52,
              child: ImageService.buildProductImage(
                imageUrl: _productPreviewUrl(product),
                size: 52,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            product.name,
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${product.sku} · ${product.brand ?? 'Sin marca'} · ${product.categoryName ?? 'Sin categoría'}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '$scorePercent%',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: candidate.overallScore >= 0.8
                                ? Colors.orange.shade700
                                : theme.colorScheme.primary,
                          ),
                        ),
                        Text(
                          'score total',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: candidate.overallScore,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(999),
                  backgroundColor: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.4),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (candidate.keywordScore > 0)
                      ProductDuplicateMetricChip(
                        label:
                            'Texto ${(candidate.keywordScore * 100).round()}%',
                      ),
                    if (candidate.semanticScore > 0)
                      ProductDuplicateMetricChip(
                        label: 'IA ${(candidate.semanticScore * 100).round()}%',
                        tone: ProductDuplicateChipTone.primary,
                      ),
                    if (candidate.aiTypeScore > 0)
                      ProductDuplicateMetricChip(
                        label:
                            'Vision ${(candidate.aiTypeScore * 100).round()}%',
                        tone: candidate.aiTypeScore >= 0.75
                            ? ProductDuplicateChipTone.warning
                            : ProductDuplicateChipTone.primary,
                      ),
                    if (candidate.identityScore > 0)
                      ProductDuplicateMetricChip(
                        label: 'ID ${(candidate.identityScore * 100).round()}%',
                        tone: candidate.identityScore >= 0.60
                            ? ProductDuplicateChipTone.warning
                            : ProductDuplicateChipTone.primary,
                      ),
                    if (candidate.imageScore > 0)
                      ProductDuplicateMetricChip(
                        label:
                            'Imagen ${(candidate.imageScore * 100).round()}%',
                        tone: candidate.imageScore >= 0.9
                            ? ProductDuplicateChipTone.warning
                            : ProductDuplicateChipTone.primary,
                      ),
                    if (!candidate.hasProductImage)
                      const ProductDuplicateMetricChip(
                        label: 'Sin imagen',
                        tone: ProductDuplicateChipTone.neutral,
                      ),
                    if (candidate.metadataScore > 0)
                      ProductDuplicateMetricChip(
                        label:
                            'Meta ${(candidate.metadataScore * 100).round()}%',
                      ),
                    if (product.price > 0)
                      ProductDuplicateMetricChip(
                        label: '\$${product.price.toStringAsFixed(0)}',
                        tone: ProductDuplicateChipTone.neutral,
                      ),
                  ],
                ),
                if (candidate.imageDebugSignals.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: candidate.imageDebugSignals
                        .map((signal) => ProductDuplicateMetricChip(
                              label: signal,
                              tone: ProductDuplicateChipTone.neutral,
                            ))
                        .toList(growable: false),
                  ),
                ],
                if (candidate.signals.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: candidate.signals
                        .map((signal) => ProductDuplicateMetricChip(
                              label: signal,
                              tone: ProductDuplicateChipTone.soft,
                            ))
                        .toList(growable: false),
                  ),
                ],
              ],
            ),
          ),
          if (onSelected != null) ...[
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: onSelected,
              icon: const Icon(Icons.check, size: 16),
              label: const Text('Usar'),
            ),
          ],
        ],
      ),
    );

    if (onSelected == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onSelected,
        borderRadius: BorderRadius.circular(12),
        child: content,
      ),
    );
  }

  static String? _productPreviewUrl(Product product) {
    final optimized = product.imageUrlOptimized?.trim();
    if (optimized != null && optimized.isNotEmpty) return optimized;
    final main = product.imageUrl?.trim();
    if (main != null && main.isNotEmpty) return main;
    if (product.additionalImages.isNotEmpty) {
      return product.additionalImages.first;
    }
    return null;
  }
}

enum ProductDuplicateChipTone { standard, primary, warning, soft, neutral }

class ProductDuplicateMetricChip extends StatelessWidget {
  const ProductDuplicateMetricChip({
    super.key,
    required this.label,
    this.tone = ProductDuplicateChipTone.standard,
  });

  final String label;
  final ProductDuplicateChipTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Color background;
    Color foreground;

    switch (tone) {
      case ProductDuplicateChipTone.primary:
        background = theme.colorScheme.primaryContainer.withValues(alpha: 0.45);
        foreground = theme.colorScheme.primary;
        break;
      case ProductDuplicateChipTone.warning:
        background = Colors.orange.shade50;
        foreground = Colors.orange.shade700;
        break;
      case ProductDuplicateChipTone.soft:
        background =
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5);
        foreground = theme.colorScheme.onSurfaceVariant;
        break;
      case ProductDuplicateChipTone.neutral:
        background =
            theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.4);
        foreground = theme.colorScheme.onSurfaceVariant;
        break;
      case ProductDuplicateChipTone.standard:
        background = theme.colorScheme.surfaceContainerHighest;
        foreground = theme.colorScheme.onSurfaceVariant;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
      ),
    );
  }
}
