enum ProductCompatibilityLevel {
  compatible,
  caution,
  incompatible,
}

class ProductCompatibilityAssessment {
  final ProductCompatibilityLevel level;
  final String label;
  final String? detail;
  final int sortPriority;

  const ProductCompatibilityAssessment.compatible({
    this.label = 'Compatible',
    this.detail,
    this.sortPriority = 10,
  }) : level = ProductCompatibilityLevel.compatible;

  const ProductCompatibilityAssessment.caution({
    this.label = 'Revisar',
    this.detail,
    this.sortPriority = 40,
  }) : level = ProductCompatibilityLevel.caution;

  const ProductCompatibilityAssessment.incompatible({
    this.label = 'No compatible',
    this.detail,
    this.sortPriority = 90,
  }) : level = ProductCompatibilityLevel.incompatible;
}
