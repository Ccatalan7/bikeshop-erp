import 'package:flutter/material.dart';
import 'package:vinabike_public_core/modules/website/models/website_block_definition.dart';

import 'website_block_type.dart';

export 'package:vinabike_public_core/modules/website/models/website_block_definition.dart';

/// The editor's icon for a block definition; the definitions themselves live
/// in the shared core so the HTML storefront reads the same schema.
extension WebsiteBlockDefinitionIcon on WebsiteBlockDefinition {
  IconData get icon => type.icon;
}
