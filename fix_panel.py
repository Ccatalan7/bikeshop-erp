import re

file_path = "lib/modules/bikeshop/widgets/bike_record_panel.dart"
with open(file_path, "r") as f:
    text = f.read()

# Replace withOpacity with withValues(alpha: ) globally in this file
text = re.sub(r'\.withOpacity\(([^)]+)\)', r'.withValues(alpha: \1)', text)

# _hoveredDiagnosisSystemKey
text = re.sub(r'String\?\s+_hoveredDiagnosisSystemKey;', '', text)

# Just comment out the problem line 793 calling _buildBikeSchemaNavigator
text = re.sub(r'_buildBikeSchemaNavigator\(theme,\s*history,\s*activeSystemKey\);', r'// _buildBikeSchemaNavigator(theme, history, activeSystemKey);', text)

with open(file_path, "w") as f:
    f.write(text)

print("Done fixing panel")
