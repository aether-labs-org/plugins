# AWS4 shapes - XML patterns

Copy these patterns; change ids, labels, geometry and attributes. Every shape name used must be
in `providers/aws/aws4-allowlist.txt` (generated from the draw.io AWS4 library).

## Containers (groups)

```xml
<object id="region" label="sa-east-1" sa_kind="region">
  <mxCell style="points=[];outlineConnect=0;html=1;whiteSpace=wrap;fontSize=12;container=1;collapsible=0;recursiveResize=0;shape=mxgraph.aws4.group;grIcon=mxgraph.aws4.group_region;strokeColor=#00A4A6;fillColor=none;verticalAlign=top;align=left;spacingLeft=30;fontColor=#147EBA;dashed=1;" vertex="1" parent="1">
    <mxGeometry x="0" y="0" width="800" height="500" as="geometry"/>
  </mxCell>
</object>
<object id="vpc" label="VPC app 10.0.0.0/16" sa_kind="vpc" cidr="10.0.0.0/16">
  <mxCell style="points=[];outlineConnect=0;html=1;whiteSpace=wrap;fontSize=12;container=1;collapsible=0;recursiveResize=0;shape=mxgraph.aws4.group;grIcon=mxgraph.aws4.group_vpc;strokeColor=#8C4FFF;fillColor=none;verticalAlign=top;align=left;spacingLeft=30;fontColor=#AAB7B8;" vertex="1" parent="region">
    <mxGeometry x="20" y="40" width="760" height="440" as="geometry"/>
  </mxCell>
</object>
<object id="az-a" label="sa-east-1a" sa_kind="az">
  <mxCell style="fillColor=none;strokeColor=#147EBA;dashed=1;verticalAlign=top;fontStyle=0;fontColor=#147EBA;container=1;collapsible=0;" vertex="1" parent="vpc">
    <mxGeometry x="20" y="40" width="340" height="380" as="geometry"/>
  </mxCell>
</object>
<object id="pub-a" label="Public subnet 10.0.101.0/24" sa_kind="subnet-public" cidr="10.0.101.0/24">
  <mxCell style="points=[];outlineConnect=0;html=1;whiteSpace=wrap;fontSize=12;container=1;collapsible=0;shape=mxgraph.aws4.group;grIcon=mxgraph.aws4.group_security_group;grStroke=0;strokeColor=#7AA116;fillColor=#F2F6E8;verticalAlign=top;align=left;spacingLeft=30;fontColor=#248814;" vertex="1" parent="az-a">
    <mxGeometry x="20" y="40" width="300" height="140" as="geometry"/>
  </mxCell>
</object>
```

Private subnets use the same pattern with `sa_kind="subnet-private"`, `strokeColor=#00A4A6`,
`fillColor=#E6F6F7`, `fontColor=#147EBA`. Accounts use `grIcon=mxgraph.aws4.group_aws_cloud_alt`
and `sa_kind="account"`. Trust boundaries are a dashed red rectangle
(`dashed=1;strokeColor=#DD344C;container=1;fillColor=none`) with `sa_kind="trust-boundary"`.

## Service icons

Resource icons (`shape=mxgraph.aws4.resourceIcon;resIcon=` + a shape name) or product
shapes (`shape=` + a shape name):

| Service | Style fragment |
|---|---|
| Application Load Balancer | `shape=mxgraph.aws4.application_load_balancer` |
| NAT Gateway | `shape=mxgraph.aws4.nat_gateway` |
| Internet Gateway | `shape=mxgraph.aws4.internet_gateway` |
| CloudFront | `shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.cloudfront` |
| API Gateway | `shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.api_gateway` |
| Lambda | `shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.lambda` |
| ECS / Fargate | `shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.fargate` |
| EKS | `shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.eks` |
| EC2 | `shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.ec2` |
| RDS | `shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.rds` |
| Aurora | `shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.aurora` |
| DynamoDB | `shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.dynamodb` |
| ElastiCache | `shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.elasticache` |
| S3 | `shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.s3` |
| SQS | `shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.sqs` |
| SNS | `shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.sns` |
| EventBridge | `shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.eventbridge` |
| Step Functions | `shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.step_functions` |
| CloudWatch | `shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.cloudwatch` |
| KMS | `shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.key_management_service` |
| Secrets Manager | `shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.secrets_manager` |
| WAF | `shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.waf` |
| Route 53 | `shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.route_53` |
| Bedrock (no dedicated icon in the draw.io 31 AWS4 library) | `shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.machine_learning`, label "Amazon Bedrock" |
| Users | `shape=mxgraph.aws4.users` |

A component icon:

```xml
<object id="alb" label="ALB" component_id="web-alb">
  <mxCell style="sketch=0;outlineConnect=0;fontColor=#232F3E;fillColor=#8C4FFF;strokeColor=none;verticalLabelPosition=bottom;verticalAlign=top;align=center;html=1;fontSize=12;aspect=fixed;shape=mxgraph.aws4.application_load_balancer;" vertex="1" parent="pub-a">
    <mxGeometry x="40" y="40" width="60" height="60" as="geometry"/>
  </mxCell>
</object>
```

A flow (data-flow view labels start with the step number):

```xml
<mxCell id="f1" value="1 HTTPS (TLS 1.2+)" style="edgeStyle=orthogonalEdgeStyle;html=1;endArrow=block;" edge="1" source="users" target="alb" parent="1">
  <mxGeometry relative="1" as="geometry"/>
</mxCell>
```
