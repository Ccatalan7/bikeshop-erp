import sys

try:
    with open('/Users/Claudio/Dev/bikeshop-erp/lib/modules/pos/pages/pos_dashboard_page.dart', 'r', encoding='utf-8') as f:
        lines = f.readlines()
        
    start_delete_index = -1
    end_delete_index = -1
    for i in range(len(lines)):
        if lines[i].startswith("  Widget _buildInvoicePaymentForm(ThemeData theme, POSService posService) {"):
            start_delete_index = i
            break
            
    # The SECOND occurrence of _buildInvoicePaymentForm is the new one, at line 2059 (index 2058)
    for i in range(start_delete_index + 1, len(lines)):
        if lines[i].startswith("  Widget _buildInvoicePaymentForm(ThemeData theme, POSService posService) {"):
            # The line BEFORE the second occurrence is where we stop deleting
            end_delete_index = i - 1
            break
            
    if start_delete_index == -1 or end_delete_index == -1:
        print("Could not find boundaries")
        sys.exit(1)
        
    # Delete the lines
    new_lines = lines[:start_delete_index] + lines[end_delete_index+1:]
    
    with open('/Users/Claudio/Dev/bikeshop-erp/lib/modules/pos/pages/pos_dashboard_page.dart', 'w', encoding='utf-8') as f:
        f.writelines(new_lines)
        
    print(f"Successfully deleted duplicate methods from index {start_delete_index} to {end_delete_index}")

except Exception as e:
    print(f"Error: {e}")
    sys.exit(1)
