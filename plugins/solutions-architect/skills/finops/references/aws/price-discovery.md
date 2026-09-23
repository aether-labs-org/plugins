# Adding a resource to the price map

`providers/aws/price-map.json` maps a Terraform resource type to Price List queries. Add an
entry only after confirming it resolves to exactly one product.

1. Find the service code and attributes with the `aws-pricing` MCP:
   `get_pricing_service_codes`, `get_pricing_service_attributes`, `get_pricing_attribute_values`.
2. Query candidates with `get_pricing` (or `aws pricing get-products`) filtered by `regionCode`
   and the attributes the resource sets, and list the `usagetype` values returned.
3. Choose the usagetype **without** its region prefix (`NatGateway-Hours`, not
   `SAE1-NatGateway-Hours`): the map prepends `^(?:[A-Z]{2,4}[0-9]-)?`, which matches `SAE1-`,
   `USE1-` or no prefix (us-east-1 uses both) and never `IA-` (Infrequent Access).
4. Write the entry: `service_code`, `filters` (attribute templates like `{instance_type}`, or
   `{"from": "<attr>", "map": {...}}`), optional `when`, and `lines[]` with `name`, `usagetype`
   and `quantity` (`hours`, `attr` + `scale`, `usage`, `times_usage`, `times_attr`,
   `times_hours`).
5. Run the lookup with `--mode record` for two regions (the workspace region and us-east-1) and
   check the line is `estimated` with the expected usagetype. If it says "several products with
   different prices", add a filter; never pick one by hand.
6. Propose the entry to the user as a change to the plugin's price map; until it is merged the
   estimate lists the line as "estimated via discovery" with the filter used.

Usage metrics already understood by the map: `storage_gb`, `lcu`, `processed_gb`, `requests`,
`gb_seconds`, `write_request_units`, `read_request_units`, `data_out_gb`, `tasks`, `ingest_gb`,
`stored_gb`.
