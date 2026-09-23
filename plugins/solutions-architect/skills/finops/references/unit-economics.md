# Unit economics

Cost per business unit = monthly list price / business units per month.

1. Take the unit from the requirements (`manifest.assumptions.business_units`): orders,
   active users, GB processed, API calls.
2. Split costs into **fixed** (hours, provisioned sizes) and **variable** (usage-based lines).
   The estimate marks usage-based lines; only they scale with volume.
3. Report the unit cost at the expected volume, and at the low/high range from
   `assumptions.range` - a design whose unit cost falls as volume grows is usually healthier
   than one where it stays flat.
4. In ADR comparisons, compare options by unit cost at the expected volume **and** at 3x volume
   when the requirements include growth.
