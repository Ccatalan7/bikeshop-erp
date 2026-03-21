const fs = require('fs');
const file = 'c:\\dev\\ProjectVinabike\\lib\\shared\\widgets\\product_autocomplete_field.dart';
let c = fs.readFileSync(file, 'utf8');

const oldStr = `
    final bottomAnchor = overlaySize.height - relativeY + 4;

    _overlayEntry = OverlayEntry(
      builder: (context) => showAbove
          ? Positioned(
              left: left,
              bottom: bottomAnchor,
              width: dropdownWidth,
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(8),
                child:
                    _buildDropdownContent(Theme.of(context), dropdownMaxHeight),
              ),
            )
          : Positioned(
              left: left,
              top: fieldBottomInOverlay + 4,
              width: dropdownWidth,
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(8),
                child:
                    _buildDropdownContent(Theme.of(context), dropdownMaxHeight),
              ),
            ),
    );`;

const newStr = `
    final horizontalOffset = left - relativeX;

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        width: dropdownWidth,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          targetAnchor: showAbove ? Alignment.topLeft : Alignment.bottomLeft,
          followerAnchor: showAbove ? Alignment.bottomLeft : Alignment.topLeft,
          offset: Offset(horizontalOffset, showAbove ? -4 : 4),
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(8),
            child: _buildDropdownContent(Theme.of(context), dropdownMaxHeight),
          ),
        ),
      ),
    );`;

c = c.replace(oldStr.trim(), newStr.trim());
fs.writeFileSync(file, c);
console.log('Done replacement');

