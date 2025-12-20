
import os

file_path = 'lib/modules/website/widgets/website_block_renderer.dart'
start_line = 249
end_line = 382

new_content = r"""  static Widget _buildHero({
    required BuildContext context,
    required Map<String, dynamic> data,
    required Color primaryColor,
    required Color accentColor,
    bool previewMode = false,
    String? headingFont,
    String? bodyFont,
    double? headingSize,
    double? bodySize,
    void Function(String route)? onNavigate,
  }) {
    final theme = Theme.of(context);

    final title = (data['title'] ?? 'Bienvenido').toString().trim();
    final subtitle = (data['subtitle'] ?? '').toString().trim();
    final ctaText =
        (data['ctaText'] ?? data['buttonText'] ?? 'Ver más').toString().trim();
    final ctaLink =
        (data['ctaLink'] ?? data['buttonLink'] ?? '/tienda/productos')
            .toString()
            .trim();
    final imageUrl = data['imageUrl'];
    final showOverlay = (data['showOverlay'] ?? true) == true;
    final overlayOpacity =
        ((data['overlayOpacity'] ?? 0.5) as num).clamp(0.0, 1.0).toDouble();
    final hasImage = imageUrl != null && imageUrl.toString().isNotEmpty;

    // Use style background if no image
    final bgColor = _parseColor(data['style']?['backgroundColor']) ?? const Color(0xFF1a1a1a);
    
    // New Props for Alignment and Full Screen
    final isFullScreen = data['isFullScreen'] == true;
    final alignment = data['alignment']?.toString() ?? 'center'; // center, left, right

    final resolvedHeading =
        (theme.textTheme.displayLarge ?? const TextStyle()).copyWith(
      fontFamily: headingFont?.isNotEmpty == true ? headingFont : null,
      fontSize: headingSize,
      color: Colors.white,
    );

    final resolvedSubtitle =
        (theme.textTheme.headlineSmall ?? const TextStyle()).copyWith(
      fontFamily: bodyFont?.isNotEmpty == true ? bodyFont : null,
      fontSize: bodySize != null ? bodySize * 1.2 : null,
      color: Colors.white70,
    );
    
    // Resolve alignment logic
    CrossAxisAlignment crossAlign;
    TextAlign textAlign;
    Alignment geometryAlign;
    
    switch (alignment) {
      case 'left':
        crossAlign = CrossAxisAlignment.start;
        textAlign = TextAlign.left;
        geometryAlign = Alignment.centerLeft;
        break;
      case 'right':
        crossAlign = CrossAxisAlignment.end;
        textAlign = TextAlign.right;
        geometryAlign = Alignment.centerRight;
        break;
      default:
        crossAlign = CrossAxisAlignment.center;
        textAlign = TextAlign.center;
        geometryAlign = Alignment.center;
    }

    return Container(
      height: isFullScreen ? MediaQuery.of(context).size.height : 520,
      width: double.infinity,
      decoration: BoxDecoration(
        color: bgColor,
        image: hasImage
            ? DecorationImage(
                image: NetworkImage(imageUrl.toString()),
                fit: BoxFit.cover,
              )
            : null,
        gradient: !hasImage
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  bgColor,
                  Color.lerp(bgColor, Colors.black, 0.2)!,
                ],
              )
            : null,
      ),
      child: Container(
        decoration: showOverlay
            ? BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(overlayOpacity * 0.5),
                    Colors.black.withOpacity(overlayOpacity * 0.8),
                  ],
                ),
              )
            : null,
        child: Align(
          alignment: geometryAlign,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: crossAlign,
              children: [
                Text(
                  (title.isEmpty ? 'Título' : title).toUpperCase(),
                  style: resolvedHeading.copyWith(
                    letterSpacing: 3,
                    fontWeight: FontWeight.w900,
                  ),
                  textAlign: textAlign,
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(subtitle,
                      style: resolvedSubtitle, textAlign: textAlign),
                ],
                const SizedBox(height: 40),
                OutlinedButton(
                  onPressed: previewMode
                      ? () {}
                      : () {
                          final route =
                              ctaLink.isNotEmpty ? ctaLink : '/tienda/productos';
                          if (onNavigate != null) {
                            onNavigate(route);
                          }
                        },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white, width: 1),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(0),
                    ),
                  ),
                  child: Text(
                    (ctaText.isEmpty ? 'CHECK IT OUT' : ctaText).toUpperCase(),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }"""

with open(file_path, 'r') as f:
    lines = f.readlines()

# Replace lines 249-382 (0-indexed: 248-382)
# Check if line 248 starts with "  static Widget _buildHero" to be sure
if "static Widget _buildHero" not in lines[start_line - 1]:
    print(f"Error: Line {start_line} does not match expected content: {lines[start_line - 1]}")
    exit(1)

# Check if line 382 is "  }"
if "  }" not in lines[end_line - 1]:
    print(f"Error: Line {end_line} does not match expected content: {lines[end_line - 1]}")
    # allow fuzzy match?
    pass

# Perform replacement
# Keep lines before start_line
new_lines = lines[:start_line - 1]
# Insert new content
new_lines.append(new_content + "\n")
# Keep lines after end_line
new_lines.extend(lines[end_line:])

with open(file_path, 'w') as f:
    f.writelines(new_lines)

print("Successfully updated _buildHero")
