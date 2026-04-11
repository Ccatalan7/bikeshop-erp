import os
import re

lib_dir = "lib"

# Loop through all dart files in lib
for root, dirs, files in os.walk(lib_dir):
    for file in files:
        if file.endswith(".dart"):
            file_path = os.path.join(root, file)
            with open(file_path, "r", encoding="utf-8") as f:
                content = f.read()
            
            # Use regex to find .withOpacity(x) and replace with .withValues(alpha: x)
            # x could be a number, a variable, or an expression
            new_content = re.sub(r'\.withOpacity\(([^)]+)\)', r'.withValues(alpha: \1)', content)
            
            if new_content != content:
                with open(file_path, "w", encoding="utf-8") as f:
                    f.write(new_content)
                print(f"Fixed {file_path}")

print("Done fixing withOpacity globally in lib")
