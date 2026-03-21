const fs = require('fs');
const file = 'c:\\dev\\ProjectVinabike\\lib\\shared\\widgets\\product_autocomplete_field.dart';
let c = fs.readFileSync(file, 'utf8');

const startIdx = c.indexOf('final bottomAnchor = ');
if (startIdx === -1) throw new Error('start anchor not found');
const endAnchor = '    overlay.insert(_overlayEntry!);';
const endIdx = c.indexOf(endAnchor, startIdx);
if (endIdx === -1) throw new Error('end anchor not found');

const newStr = `    final horizontalOffset = left - relativeX;

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
    );

`;

c = c.substring(0, startIdx) + newStr + c.substring(endIdx);
fs.writeFileSync(file, c);
console.log('Update successful');
