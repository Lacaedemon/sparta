import re

with open('scripts/Order.gd', 'r') as f:
    content = f.read()

content = content.replace(
    'var apart: bool = is_instance_valid(partner) \\\n\t\t# OPTIMIZATION: Use distance_squared_to instead of distance_to to avoid expensive sqrt\n\t\tand u.position.distance_squared_to(partner.position) \\\n\t\t\t> u.separation_radius + partner.separation_radius \\\n\t\t\t\t+ u.soldier_block_extent() + partner.soldier_block_extent()',
    '# OPTIMIZATION: Use distance_squared_to instead of distance_to to avoid expensive sqrt\n\tvar contact_distance: float = u.separation_radius + partner.separation_radius + u.soldier_block_extent() + partner.soldier_block_extent()\n\tvar apart: bool = is_instance_valid(partner) \\\n\t\tand u.position.distance_squared_to(partner.position) > contact_distance * contact_distance'
)

with open('scripts/Order.gd', 'w') as f:
    f.write(content)

with open('scripts/SelectionManager.gd', 'r') as f:
    content = f.read()

content = content.replace(
    'var click_combo: bool = (now_ms - _last_right_click_ms <= _click_combo_window_ms) and \\\n\t\t\t# OPTIMIZATION: Use distance_squared_to instead of distance_to to avoid expensive sqrt\n\t\t\tend_pos.distance_squared_to(_last_right_click_pos) < 100.0',
    '# OPTIMIZATION: Use distance_squared_to instead of distance_to to avoid expensive sqrt\n\t\tvar click_combo: bool = (now_ms - _last_right_click_ms <= _click_combo_window_ms) and \\\n\t\t\tend_pos.distance_squared_to(_last_right_click_pos) < 100.0'
)

with open('scripts/SelectionManager.gd', 'w') as f:
    f.write(content)
