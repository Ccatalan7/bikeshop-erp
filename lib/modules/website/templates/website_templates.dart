/// 🎨 Professional Website Templates for GrapesJS
/// 
/// These templates are actual HTML/CSS that will be:
/// 1. Shown in wizard for selection
/// 2. Loaded in GrapesJS editor
/// 3. Deployed to Firebase as static HTML
/// 
/// What you see in editor === What deploys to web (100% match)

class WebsiteTemplate {
  final String id;
  final String name;
  final String description;
  final List<String> features;
  final String htmlContent;
  final String cssContent;
  final String previewImageUrl;

  const WebsiteTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.features,
    required this.htmlContent,
    required this.cssContent,
    this.previewImageUrl = '',
  });
}

class WebsiteTemplates {
  /// Modern Store Template - Blue theme, full-featured e-commerce
  static const modernStore = WebsiteTemplate(
    id: 'modern-store',
    name: 'Tienda Moderna',
    description: 'Diseño moderno y profesional para e-commerce',
    features: ['Hero dinámico', 'Grid de productos', 'Servicios', 'Sobre nosotros'],
    htmlContent: _modernStoreHTML,
    cssContent: _modernStoreCSS,
  );

  /// Bike Shop Template - Green theme, focused on services
  static const bikeShop = WebsiteTemplate(
    id: 'bike-shop',
    name: 'Bike Shop Pro',
    description: 'Diseño especializado para tiendas de bicicletas',
    features: ['Hero para talleres', 'Servicios destacados', 'Productos', 'Contacto'],
    htmlContent: _bikeShopHTML,
    cssContent: _bikeShopCSS,
  );

  /// Minimalist Template - Clean, elegant design
  static const minimalist = WebsiteTemplate(
    id: 'minimalist',
    name: 'Minimalista',
    description: 'Diseño limpio y elegante con enfoque en el producto',
    features: ['Hero simple', 'Productos destacados', 'Diseño limpio'],
    htmlContent: _minimalistHTML,
    cssContent: _minimalistCSS,
  );

  /// All available templates
  static const List<WebsiteTemplate> all = [
    modernStore,
    bikeShop,
    minimalist,
  ];

  static WebsiteTemplate? getById(String id) {
    try {
      return all.firstWhere((template) => template.id == id);
    } catch (e) {
      return null;
    }
  }
}

/// ============================================================================
/// MODERN STORE TEMPLATE
/// ============================================================================

const String _modernStoreHTML = r'''
<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Tienda Online</title>
  <link href="https://fonts.googleapis.com/css2?family=Roboto:wght@300;400;500;700&display=swap" rel="stylesheet">
</head>
<body>
  <!-- Hero Section -->
  <section class="hero" id="hero">
    <div class="container">
      <h1 class="hero-title">¡Bienvenido a Nuestra Tienda!</h1>
      <p class="hero-subtitle">Los mejores productos al mejor precio</p>
      <a href="#productos" class="btn btn-primary">Ver Catálogo</a>
    </div>
  </section>

  <!-- Products Section -->
  <section class="products" id="productos">
    <div class="container">
      <h2 class="section-title">Productos Destacados</h2>
      <p class="section-subtitle">Descubre nuestras mejores ofertas</p>
      <div class="product-grid" id="product-grid" data-columns="3" data-show-prices="true">
        <!-- Products loaded dynamically -->
        <div class="product-card">
          <img src="https://via.placeholder.com/300x300/1976D2/ffffff?text=Producto+1" alt="Producto">
          <h3>Producto Demo</h3>
          <p class="price">$29.990</p>
          <button class="btn btn-secondary">Agregar al Carro</button>
        </div>
        <div class="product-card">
          <img src="https://via.placeholder.com/300x300/1976D2/ffffff?text=Producto+2" alt="Producto">
          <h3>Producto Demo</h3>
          <p class="price">$39.990</p>
          <button class="btn btn-secondary">Agregar al Carro</button>
        </div>
        <div class="product-card">
          <img src="https://via.placeholder.com/300x300/1976D2/ffffff?text=Producto+3" alt="Producto">
          <h3>Producto Demo</h3>
          <p class="price">$49.990</p>
          <button class="btn btn-secondary">Agregar al Carro</button>
        </div>
      </div>
    </div>
  </section>

  <!-- Services Section -->
  <section class="services">
    <div class="container">
      <h2 class="section-title">Nuestros Servicios</h2>
      <div class="services-grid">
        <div class="service-card">
          <div class="service-icon">🚚</div>
          <h3>Envío Gratis</h3>
          <p>En compras sobre $50.000</p>
        </div>
        <div class="service-card">
          <div class="service-icon">🔒</div>
          <h3>Compra Segura</h3>
          <p>Pago protegido 100%</p>
        </div>
        <div class="service-card">
          <div class="service-icon">💬</div>
          <h3>Soporte 24/7</h3>
          <p>Estamos para ayudarte</p>
        </div>
      </div>
    </div>
  </section>

  <!-- About Section -->
  <section class="about">
    <div class="container">
      <h2 class="section-title">Sobre Nosotros</h2>
      <p class="about-text">
        Somos una tienda comprometida con la calidad y la satisfacción de nuestros clientes.
        Ofrecemos los mejores productos al mejor precio, con envío rápido y atención personalizada.
      </p>
    </div>
  </section>

  <script>
    // Load products from API (Supabase)
    async function loadProducts() {
      const grid = document.getElementById('product-grid');
      const showPrices = grid.dataset.showPrices === 'true';
      const columns = grid.dataset.columns || 3;
      
      try {
        // Fetch from your API endpoint
        const response = await fetch('/api/featured-products');
        const products = await response.json();
        
        grid.innerHTML = products.map(product => `
          <div class="product-card">
            <img src="${product.image_url || 'https://via.placeholder.com/300'}" alt="${product.name}">
            <h3>${product.name}</h3>
            ${showPrices ? `<p class="price">$${product.price.toLocaleString('es-CL')}</p>` : ''}
            <button class="btn btn-secondary" onclick="addToCart('${product.id}')">Agregar al Carro</button>
          </div>
        `).join('');
      } catch (error) {
        console.error('Error loading products:', error);
      }
    }

    // Initialize on page load
    if (document.getElementById('product-grid')) {
      loadProducts();
    }
  </script>
</body>
</html>
''';

const String _modernStoreCSS = r'''
:root {
  --primary-color: #1976D2;
  --secondary-color: #FF6F00;
  --text-color: #333333;
  --background-color: #FFFFFF;
  --gray-light: #F5F5F5;
  --gray-medium: #E0E0E0;
}

* {
  margin: 0;
  padding: 0;
  box-sizing: border-box;
}

body {
  font-family: 'Roboto', sans-serif;
  color: var(--text-color);
  line-height: 1.6;
}

.container {
  max-width: 1200px;
  margin: 0 auto;
  padding: 0 20px;
}

/* Hero Section */
.hero {
  background: linear-gradient(135deg, var(--primary-color) 0%, #1565C0 100%);
  color: white;
  padding: 120px 0;
  text-align: center;
}

.hero-title {
  font-size: 48px;
  font-weight: 700;
  margin-bottom: 20px;
}

.hero-subtitle {
  font-size: 24px;
  font-weight: 300;
  margin-bottom: 40px;
}

.btn {
  display: inline-block;
  padding: 14px 32px;
  font-size: 16px;
  font-weight: 500;
  text-decoration: none;
  border-radius: 4px;
  transition: all 0.3s ease;
  border: none;
  cursor: pointer;
}

.btn-primary {
  background: white;
  color: var(--primary-color);
}

.btn-primary:hover {
  background: var(--gray-light);
  transform: translateY(-2px);
  box-shadow: 0 4px 12px rgba(0,0,0,0.15);
}

.btn-secondary {
  background: var(--secondary-color);
  color: white;
}

.btn-secondary:hover {
  background: #F57C00;
}

/* Sections */
section {
  padding: 80px 0;
}

.section-title {
  font-size: 36px;
  font-weight: 700;
  text-align: center;
  margin-bottom: 12px;
}

.section-subtitle {
  font-size: 18px;
  font-weight: 300;
  text-align: center;
  color: #666;
  margin-bottom: 48px;
}

/* Product Grid */
.product-grid {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 32px;
  margin-top: 48px;
}

.product-card {
  background: white;
  border-radius: 8px;
  overflow: hidden;
  box-shadow: 0 2px 8px rgba(0,0,0,0.1);
  transition: transform 0.3s ease, box-shadow 0.3s ease;
}

.product-card:hover {
  transform: translateY(-4px);
  box-shadow: 0 8px 24px rgba(0,0,0,0.15);
}

.product-card img {
  width: 100%;
  height: 300px;
  object-fit: cover;
}

.product-card h3 {
  font-size: 20px;
  font-weight: 500;
  padding: 16px 16px 8px;
}

.product-card .price {
  font-size: 24px;
  font-weight: 700;
  color: var(--primary-color);
  padding: 0 16px 16px;
}

.product-card button {
  width: calc(100% - 32px);
  margin: 0 16px 16px;
}

/* Services Grid */
.services {
  background: var(--gray-light);
}

.services-grid {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 32px;
  margin-top: 48px;
}

.service-card {
  background: white;
  padding: 40px 24px;
  border-radius: 8px;
  text-align: center;
  box-shadow: 0 2px 8px rgba(0,0,0,0.08);
}

.service-icon {
  font-size: 48px;
  margin-bottom: 16px;
}

.service-card h3 {
  font-size: 22px;
  font-weight: 500;
  margin-bottom: 8px;
}

.service-card p {
  color: #666;
}

/* About Section */
.about-text {
  max-width: 800px;
  margin: 0 auto;
  font-size: 18px;
  line-height: 1.8;
  text-align: center;
}

/* Responsive */
@media (max-width: 968px) {
  .product-grid,
  .services-grid {
    grid-template-columns: repeat(2, 1fr);
  }
  
  .hero-title {
    font-size: 36px;
  }
}

@media (max-width: 640px) {
  .product-grid,
  .services-grid {
    grid-template-columns: 1fr;
  }
  
  .hero {
    padding: 80px 0;
  }
  
  .hero-title {
    font-size: 28px;
  }
  
  .hero-subtitle {
    font-size: 18px;
  }
}
''';

/// ============================================================================
/// BIKE SHOP TEMPLATE
/// ============================================================================

const String _bikeShopHTML = r'''
<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Bike Shop</title>
  <link href="https://fonts.googleapis.com/css2?family=Roboto:wght@300;400;500;700&display=swap" rel="stylesheet">
</head>
<body>
  <!-- Hero Section -->
  <section class="hero-bike">
    <div class="container">
      <h1 class="hero-title">Tu Tienda de Bicicletas</h1>
      <p class="hero-subtitle">Reparación • Ventas • Accesorios</p>
      <a href="#productos" class="btn btn-primary">Ver Bicicletas</a>
    </div>
  </section>

  <!-- Services Section -->
  <section class="services-bike">
    <div class="container">
      <h2 class="section-title">Nuestros Servicios</h2>
      <div class="services-grid-bike">
        <div class="service-card-bike">
          <div class="service-icon-bike">🔧</div>
          <h3>Reparación</h3>
          <p>Servicio técnico profesional para tu bicicleta</p>
        </div>
        <div class="service-card-bike">
          <div class="service-icon-bike">🚴</div>
          <h3>Ventas</h3>
          <p>Bicicletas nuevas y usadas de todas las marcas</p>
        </div>
        <div class="service-card-bike">
          <div class="service-icon-bike">⚙️</div>
          <h3>Mantención</h3>
          <p>Planes de mantención preventiva</p>
        </div>
      </div>
    </div>
  </section>

  <!-- Products Section -->
  <section class="products-bike" id="productos">
    <div class="container">
      <h2 class="section-title">Productos Destacados</h2>
      <div class="product-grid-bike" id="product-grid-bike" data-columns="3">
        <div class="product-card-bike">
          <img src="https://via.placeholder.com/300x300/2E7D32/ffffff?text=Bicicleta" alt="Bicicleta">
          <h3>Bicicleta Demo</h3>
          <p class="price-bike">$299.990</p>
          <button class="btn btn-secondary">Ver Detalles</button>
        </div>
        <div class="product-card-bike">
          <img src="https://via.placeholder.com/300x300/2E7D32/ffffff?text=Bicicleta" alt="Bicicleta">
          <h3>Bicicleta Demo</h3>
          <p class="price-bike">$399.990</p>
          <button class="btn btn-secondary">Ver Detalles</button>
        </div>
        <div class="product-card-bike">
          <img src="https://via.placeholder.com/300x300/2E7D32/ffffff?text=Bicicleta" alt="Bicicleta">
          <h3>Bicicleta Demo</h3>
          <p class="price-bike">$499.990</p>
          <button class="btn btn-secondary">Ver Detalles</button>
        </div>
      </div>
    </div>
  </section>
</body>
</html>
''';

const String _bikeShopCSS = r'''
:root {
  --primary-color: #2E7D32;
  --secondary-color: #FF6F00;
  --text-color: #333333;
  --gray-light: #F5F5F5;
}

* {
  margin: 0;
  padding: 0;
  box-sizing: border-box;
}

body {
  font-family: 'Roboto', sans-serif;
  color: var(--text-color);
  line-height: 1.6;
}

.container {
  max-width: 1200px;
  margin: 0 auto;
  padding: 0 20px;
}

.hero-bike {
  background: linear-gradient(135deg, var(--primary-color) 0%, #1B5E20 100%);
  color: white;
  padding: 120px 0;
  text-align: center;
}

.hero-title {
  font-size: 48px;
  font-weight: 700;
  margin-bottom: 16px;
}

.hero-subtitle {
  font-size: 24px;
  font-weight: 300;
  margin-bottom: 40px;
  opacity: 0.9;
}

.btn {
  display: inline-block;
  padding: 14px 32px;
  font-size: 16px;
  font-weight: 500;
  text-decoration: none;
  border-radius: 4px;
  transition: all 0.3s ease;
  border: none;
  cursor: pointer;
}

.btn-primary {
  background: white;
  color: var(--primary-color);
}

.btn-primary:hover {
  transform: translateY(-2px);
  box-shadow: 0 4px 12px rgba(0,0,0,0.2);
}

.btn-secondary {
  background: var(--secondary-color);
  color: white;
  width: 100%;
}

.btn-secondary:hover {
  background: #F57C00;
}

section {
  padding: 80px 0;
}

.section-title {
  font-size: 36px;
  font-weight: 700;
  text-align: center;
  margin-bottom: 48px;
}

.services-bike {
  background: var(--gray-light);
}

.services-grid-bike {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 32px;
}

.service-card-bike {
  background: white;
  padding: 40px 24px;
  border-radius: 8px;
  text-align: center;
  box-shadow: 0 2px 8px rgba(0,0,0,0.08);
  transition: transform 0.3s ease;
}

.service-card-bike:hover {
  transform: translateY(-4px);
  box-shadow: 0 8px 24px rgba(0,0,0,0.12);
}

.service-icon-bike {
  font-size: 48px;
  margin-bottom: 16px;
}

.service-card-bike h3 {
  font-size: 22px;
  font-weight: 500;
  margin-bottom: 8px;
  color: var(--primary-color);
}

.product-grid-bike {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 32px;
}

.product-card-bike {
  background: white;
  border-radius: 8px;
  overflow: hidden;
  box-shadow: 0 2px 8px rgba(0,0,0,0.1);
  transition: transform 0.3s ease;
}

.product-card-bike:hover {
  transform: translateY(-4px);
  box-shadow: 0 8px 24px rgba(0,0,0,0.15);
}

.product-card-bike img {
  width: 100%;
  height: 300px;
  object-fit: cover;
}

.product-card-bike h3 {
  font-size: 20px;
  font-weight: 500;
  padding: 16px 16px 8px;
}

.price-bike {
  font-size: 24px;
  font-weight: 700;
  color: var(--primary-color);
  padding: 0 16px 16px;
}

.product-card-bike button {
  margin: 0 16px 16px;
}

@media (max-width: 968px) {
  .services-grid-bike,
  .product-grid-bike {
    grid-template-columns: repeat(2, 1fr);
  }
}

@media (max-width: 640px) {
  .services-grid-bike,
  .product-grid-bike {
    grid-template-columns: 1fr;
  }
  
  .hero-bike {
    padding: 80px 0;
  }
  
  .hero-title {
    font-size: 32px;
  }
}
''';

/// ============================================================================
/// MINIMALIST TEMPLATE
/// ============================================================================

const String _minimalistHTML = r'''
<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Tienda</title>
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600&display=swap" rel="stylesheet">
</head>
<body>
  <section class="hero-minimal">
    <div class="container-minimal">
      <h1>Simplicidad y Calidad</h1>
      <a href="#productos" class="btn-minimal">Explorar Productos</a>
    </div>
  </section>

  <section class="products-minimal" id="productos">
    <div class="container-minimal">
      <div class="product-grid-minimal">
        <div class="product-minimal">
          <img src="https://via.placeholder.com/250x250/000000/ffffff?text=Producto" alt="Producto">
          <h3>Producto</h3>
          <p class="price-minimal">$29.990</p>
        </div>
        <div class="product-minimal">
          <img src="https://via.placeholder.com/250x250/000000/ffffff?text=Producto" alt="Producto">
          <h3>Producto</h3>
          <p class="price-minimal">$39.990</p>
        </div>
        <div class="product-minimal">
          <img src="https://via.placeholder.com/250x250/000000/ffffff?text=Producto" alt="Producto">
          <h3>Producto</h3>
          <p class="price-minimal">$49.990</p>
        </div>
        <div class="product-minimal">
          <img src="https://via.placeholder.com/250x250/000000/ffffff?text=Producto" alt="Producto">
          <h3>Producto</h3>
          <p class="price-minimal">$59.990</p>
        </div>
      </div>
    </div>
  </section>
</body>
</html>
''';

const String _minimalistCSS = r'''
* {
  margin: 0;
  padding: 0;
  box-sizing: border-box;
}

body {
  font-family: 'Inter', sans-serif;
  color: #000;
  background: #fff;
}

.container-minimal {
  max-width: 1200px;
  margin: 0 auto;
  padding: 0 24px;
}

.hero-minimal {
  padding: 160px 0 120px;
  text-align: center;
  border-bottom: 1px solid #e0e0e0;
}

.hero-minimal h1 {
  font-size: 56px;
  font-weight: 300;
  letter-spacing: -0.02em;
  margin-bottom: 48px;
}

.btn-minimal {
  display: inline-block;
  padding: 12px 48px;
  font-size: 14px;
  font-weight: 500;
  color: #fff;
  background: #000;
  text-decoration: none;
  text-transform: uppercase;
  letter-spacing: 0.1em;
  transition: opacity 0.3s ease;
}

.btn-minimal:hover {
  opacity: 0.8;
}

.products-minimal {
  padding: 80px 0;
}

.product-grid-minimal {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 40px;
}

.product-minimal {
  text-align: center;
}

.product-minimal img {
  width: 100%;
  height: auto;
  margin-bottom: 16px;
  transition: opacity 0.3s ease;
}

.product-minimal:hover img {
  opacity: 0.8;
}

.product-minimal h3 {
  font-size: 16px;
  font-weight: 400;
  margin-bottom: 8px;
}

.price-minimal {
  font-size: 18px;
  font-weight: 500;
}

@media (max-width: 968px) {
  .product-grid-minimal {
    grid-template-columns: repeat(2, 1fr);
  }
  
  .hero-minimal h1 {
    font-size: 40px;
  }
}

@media (max-width: 640px) {
  .product-grid-minimal {
    grid-template-columns: 1fr;
  }
  
  .hero-minimal {
    padding: 100px 0 80px;
  }
  
  .hero-minimal h1 {
    font-size: 32px;
  }
}
''';
