# Third-party icons - Kafka, Datadog, Prometheus and others

Technologies without a draw.io library are drawn with a logo **embedded** in the file, so the
view opens and exports offline. Never write base64 yourself and never link an image URL (the
validator rejects `image=http...`): put the slug in `sa_icon` and let the script embed it.

```xml
<object id="kafka" label="Apache Kafka (Amazon MSK)" component_id="orders-events" sa_icon="apachekafka">
  <mxCell style="shape=image;aspect=fixed;html=1;verticalLabelPosition=bottom;verticalAlign=top;imageAspect=0;" vertex="1" parent="region">
    <mxGeometry x="480" y="120" width="48" height="48" as="geometry"/>
  </mxCell>
</object>
```

Then, before validating:

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/embed_icons.py architecture/diagrams/<view>.drawio \
  --catalog ${CLAUDE_PLUGIN_ROOT}/providers/icons/catalog.json
```

It is idempotent - run it again after every edit of the view.

## Catalog (`providers/icons/catalog.json`)

| Group | Product → `sa_icon` |
|---|---|
| Observability | Datadog `datadog`, Prometheus `prometheus`, Grafana `grafana`, OpenTelemetry `opentelemetry`, Elasticsearch `elasticsearch`, OpenSearch `opensearch`, Jaeger `jaeger` |
| Streaming and data | Apache Kafka `apachekafka`, RabbitMQ `rabbitmq`, Redis `redis`, PostgreSQL `postgresql`, MongoDB `mongodb` |
| Platform and CI/CD | Kubernetes `kubernetes`, Helm `helm`, Argo CD `argo`, Istio `istio`, Envoy `envoyproxy`, Terraform `terraform`, Vault `vault`, GitHub Actions `githubactions`, Keycloak `keycloak`, NGINX `nginx`, Cloudflare `cloudflare`, Kong `kong` |

No icon: **Confluent** → `apachekafka` with the label "Confluent Cloud"; **Valkey** →
`redis` with the label "Valkey". Anything else not in the catalog: a plain rounded rectangle
with the product name as label - do not invent a slug.

## Which icon, AWS or third-party?

- A managed AWS service keeps its AWS4 icon (`aws4-shapes.md`): MSK, ElastiCache, RDS, Amazon
  Managed Prometheus/Grafana. Add the engine to the label ("Amazon MSK (Kafka)").
- A self-managed product (Kafka on EKS via Strimzi, Redis on EC2) or a SaaS (Datadog,
  Confluent Cloud, Cloudflare) uses the third-party icon.
- A SaaS sits **outside** the AWS `account` container. In the `dataflow-security` view, its
  flows cross a `trust-boundary` and their labels say what leaves the account ("5 HTTPS - metrics
  and logs, no personal data").
- A SaaS is still a manifest component (`service` "Datadog (SaaS)", `terraform` empty). The
  AWS price lookup never sees it: its cost belongs in the ADR's cost comparison, from the
  vendor's price page, and the estimate lists it as outside the AWS total.
