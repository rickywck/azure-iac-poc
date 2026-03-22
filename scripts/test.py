import math

cabin_weight = 9.4
cabin_allowance = 7
cabin_overweight_kg = max(0, math.ceil(cabin_weight - cabin_allowance))
cabin_overweight_fee = cabin_overweight_kg * 12
print(f"Cabin weight: {cabin_weight} kg")
print(f"Cabin allowance: {cabin_allowance} kg")
print(f"Cabin overweight (rounded up): {cabin_overweight_kg} kg")
print(f"Cabin overweight fee: {cabin_overweight_fee}")

def checked_base_fee(weight, prepaid):
    if weight <= 10:
        return 20 if prepaid else 35
    if weight <= 20:
        return 35 if prepaid else 55
    if weight <= 30:
        return 55 if prepaid else 85
    return 0

checked_bags = [
    {"name": "Bag A", "weight": 18.7, "prepaid": True, "oversize": False, "handling": 0},
    {"name": "Bag B", "weight": 26.2, "prepaid": False, "oversize": True, "handling": 0},
    {"name": "Bag C", "weight": 12.3, "prepaid": True, "oversize": False, "handling": 75},
    {"name": "Bag D", "weight": 8.5, "prepaid": False, "oversize": False, "handling": 50},
]

for bag in checked_bags:
    bag["base_fee"] = checked_base_fee(bag["weight"], bag["prepaid"])
    print(
        f"{bag['name']} base fee (weight={bag['weight']} kg, prepaid={bag['prepaid']}): {bag['base_fee']}"
    )

passenger_type = "Flex"
free_bags_allowed = 1 if passenger_type == "Flex" else 0
print(f"Passenger type: {passenger_type}")
print(f"Free bags allowed: {free_bags_allowed}")

for bag in checked_bags:
    if free_bags_allowed > 0 and bag["weight"] <= 20:
        print(
            f"Applying free bag allowance to {bag['name']} (previous base fee: {bag['base_fee']})"
        )
        bag["base_fee"] = 0
        free_bags_allowed -= 1
    print(f"{bag['name']} final base fee after allowance: {bag['base_fee']}")

base_total = sum(bag["base_fee"] for bag in checked_bags)
special_handling_total = sum(bag["handling"] for bag in checked_bags)
oversize_total = sum(60 for bag in checked_bags if bag["oversize"])
print(f"Base total: {base_total}")
print(f"Special handling total: {special_handling_total}")
print(f"Oversize total: {oversize_total}")

def overweight_penalty(weight):
    if weight > 30:
        return math.ceil(weight - 30) * 15
    return 0

overweight_total = sum(overweight_penalty(bag["weight"]) for bag in checked_bags)
penalties_total = cabin_overweight_fee + oversize_total + overweight_total
print(f"Overweight total: {overweight_total}")
print(f"Penalties total (cabin + oversize + overweight): {penalties_total}")

surcharge_base = base_total + special_handling_total
surcharge_total = surcharge_base * 0.2
print(f"Surcharge base: {surcharge_base}")
print(f"Surcharge total (20%): {surcharge_total}")

subtotal_before_multiplier = surcharge_base + surcharge_total + penalties_total
peak_multiplier = 1.15
pre_tax_total = subtotal_before_multiplier * peak_multiplier
print(f"Subtotal before multiplier: {subtotal_before_multiplier}")
print(f"Peak multiplier: {peak_multiplier}")
print(f"Pre-tax total: {pre_tax_total}")

total_with_tax = round(pre_tax_total * 1.13, 2)
print(f"Total with tax (13%, rounded): {total_with_tax}")