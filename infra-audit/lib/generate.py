#!/usr/bin/env python3
"""
Generate documentation (Markdown) and infrastructure diagram (Graphviz) from summary.json.
"""

import argparse
import json
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional


class DocumentationGenerator:
    """Generate Markdown documentation from the normalized AWS inventory."""

    def __init__(self, summary: Dict):
        self.summary = summary
        self.meta = summary.get("meta", {})
        self.networking = summary.get("networking", {})
        self.compute = summary.get("compute", {})
        self.data = summary.get("data", {})
        self.edge = summary.get("edge", {})
        self.security = summary.get("security", {})
        self.observability = summary.get("observability", {})
        self.relationships = summary.get("relationships", {})
        self.gaps = summary.get("gaps", {})

    def generate(self) -> str:
        """Generate the full Markdown documentation."""
        sections = [
            self._header(),
            self._overview(),
            self._entry_points(),
            self._networking_section(),
            self._compute_section(),
            self._data_section(),
            self._security_section(),
            self._observability_section(),
            self._gaps_section(),
            self._how_to_section()
        ]
        return "\n\n".join(filter(None, sections))

    def _header(self) -> str:
        return f"""# Book Vault - AWS Production Infrastructure

> Auto-generated infrastructure documentation from AWS API queries.
>
> **Generated**: {self.meta.get('generated_at', 'Unknown')}
> **Account ID**: {self.meta.get('account_id', 'Unknown')}
> **Region**: {self.meta.get('region', 'Unknown')}
> **Audit Version**: {self.meta.get('audit_version', 'Unknown')}

---"""

    def _overview(self) -> str:
        # Count resources
        vpc_count = len(self.networking.get("vpcs", []))
        subnet_count = len(self.networking.get("subnets", []))
        ecs_clusters = len(self.compute.get("ecs_clusters", []))
        ecs_services = len(self.compute.get("ecs_services", []))
        rds_count = len(self.data.get("rds_instances", []))
        s3_count = len(self.data.get("s3_buckets", []))
        lb_count = len(self.networking.get("load_balancers", []))

        return f"""## Overview

| Resource Type | Count |
|--------------|-------|
| VPCs | {vpc_count} |
| Subnets | {subnet_count} |
| Load Balancers | {lb_count} |
| ECS Clusters | {ecs_clusters} |
| ECS Services | {ecs_services} |
| RDS Instances | {rds_count} |
| S3 Buckets | {s3_count} |

### Architecture Summary

```
┌─────────────────────────────────────────────────────────────────────┐
│                         AWS Account: {self.meta.get('account_id', '?'):<12}              │
│                         Region: {self.meta.get('region', '?'):<16}                     │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│   [Route53] → [ALB] → [ECS Fargate] → [RDS PostgreSQL]             │
│                           ↓                                         │
│                        [S3 Media]                                   │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```"""

    def _entry_points(self) -> str:
        lines = ["## Entry Points", ""]

        # Public Load Balancers
        public_lbs = [lb for lb in self.networking.get("load_balancers", [])
                      if lb.get("is_internet_facing")]

        if public_lbs:
            lines.append("### Load Balancers (Public)")
            lines.append("")
            for lb in public_lbs:
                lines.append(f"- **{lb.get('name')}**")
                lines.append(f"  - DNS: `{lb.get('dns_name')}`")
                lines.append(f"  - Type: {lb.get('type')}")
                listeners = lb.get("listeners", [])
                if listeners:
                    ports = ", ".join(f"{l.get('protocol')}:{l.get('port')}" for l in listeners)
                    lines.append(f"  - Listeners: {ports}")
                lines.append("")

        # Route53 records pointing to AWS resources
        zones = self.edge.get("route53_zones", [])
        if zones:
            lines.append("### DNS Records")
            lines.append("")
            for zone in zones:
                for record in zone.get("relevant_records", []):
                    if record.get("alias_target"):
                        lines.append(f"- `{record.get('name')}` → `{record.get('alias_target')}`")
                    elif record.get("values"):
                        lines.append(f"- `{record.get('name')}` → {', '.join(record.get('values', []))}")
            lines.append("")

        # CloudFront
        dists = self.edge.get("cloudfront_distributions", [])
        if dists:
            lines.append("### CloudFront Distributions")
            lines.append("")
            for dist in dists:
                lines.append(f"- **{dist.get('id')}**: `{dist.get('domain_name')}`")
                if dist.get("aliases"):
                    lines.append(f"  - Aliases: {', '.join(dist.get('aliases'))}")
            lines.append("")

        return "\n".join(lines)

    def _networking_section(self) -> str:
        lines = ["## Networking", ""]

        # VPCs
        vpcs = self.networking.get("vpcs", [])
        if vpcs:
            lines.append("### VPCs")
            lines.append("")
            for vpc in vpcs:
                name = vpc.get("name") or vpc.get("id")
                lines.append(f"#### {name}")
                lines.append(f"- **ID**: `{vpc.get('id')}`")
                lines.append(f"- **CIDR**: `{vpc.get('cidr_block')}`")
                lines.append(f"- **Default**: {vpc.get('is_default')}")
                lines.append("")

        # Subnets
        subnets = self.networking.get("subnets", [])
        if subnets:
            lines.append("### Subnets")
            lines.append("")
            lines.append("| Name | ID | CIDR | AZ | Public? |")
            lines.append("|------|-----|------|-----|---------|")
            for subnet in sorted(subnets, key=lambda s: (s.get("vpc_id", ""), s.get("availability_zone", ""))):
                name = subnet.get("name") or "-"
                lines.append(f"| {name} | `{subnet.get('id')}` | {subnet.get('cidr_block')} | {subnet.get('availability_zone')} | {'Yes' if subnet.get('is_public') else 'No'} |")
            lines.append("")

        # Security Groups
        sgs = self.networking.get("security_groups", [])
        if sgs:
            lines.append("### Security Groups")
            lines.append("")
            for sg in sgs:
                lines.append(f"#### {sg.get('name')} (`{sg.get('id')}`)")
                lines.append(f"> {sg.get('description')}")
                lines.append("")

                if sg.get("has_wide_open_ingress"):
                    lines.append("⚠️ **Warning**: Has 0.0.0.0/0 ingress rules")
                    lines.append("")

                # Key ingress rules
                ingress = sg.get("ingress_rules", [])
                if ingress:
                    lines.append("**Ingress Rules:**")
                    for rule in ingress[:10]:  # Limit to first 10
                        source = rule.get("source") or rule.get("source_sg", "")
                        port = f"{rule.get('from_port')}"
                        if rule.get("to_port") != rule.get("from_port"):
                            port += f"-{rule.get('to_port')}"
                        lines.append(f"- {rule.get('protocol')} port {port} from `{source}`")
                    if len(ingress) > 10:
                        lines.append(f"- ... and {len(ingress) - 10} more rules")
                    lines.append("")

        # Load Balancers (detailed)
        lbs = self.networking.get("load_balancers", [])
        if lbs:
            lines.append("### Load Balancers")
            lines.append("")
            for lb in lbs:
                lines.append(f"#### {lb.get('name')}")
                lines.append(f"- **ARN**: `{lb.get('arn')}`")
                lines.append(f"- **Type**: {lb.get('type')}")
                lines.append(f"- **Scheme**: {lb.get('scheme')}")
                lines.append(f"- **State**: {lb.get('state')}")
                lines.append(f"- **VPC**: `{lb.get('vpc_id')}`")
                lines.append(f"- **AZs**: {', '.join(lb.get('availability_zones', []))}")
                lines.append("")

        return "\n".join(lines)

    def _compute_section(self) -> str:
        lines = ["## Compute", ""]

        # ECS Clusters
        clusters = self.compute.get("ecs_clusters", [])
        if clusters:
            lines.append("### ECS Clusters")
            lines.append("")
            for cluster in clusters:
                lines.append(f"#### {cluster.get('name')}")
                lines.append(f"- **ARN**: `{cluster.get('arn')}`")
                lines.append(f"- **Status**: {cluster.get('status')}")
                lines.append(f"- **Running Tasks**: {cluster.get('running_tasks')}")
                lines.append(f"- **Active Services**: {cluster.get('active_services')}")
                if cluster.get("capacity_providers"):
                    lines.append(f"- **Capacity Providers**: {', '.join(cluster.get('capacity_providers'))}")
                lines.append("")

        # ECS Services
        services = self.compute.get("ecs_services", [])
        if services:
            lines.append("### ECS Services")
            lines.append("")
            for svc in services:
                lines.append(f"#### {svc.get('name')}")
                lines.append(f"- **Status**: {svc.get('status')}")
                lines.append(f"- **Desired/Running/Pending**: {svc.get('desired_count')}/{svc.get('running_count')}/{svc.get('pending_count')}")
                lines.append(f"- **Launch Type**: {svc.get('launch_type') or 'Capacity Provider'}")
                if svc.get("capacity_provider_strategy"):
                    for cp in svc.get("capacity_provider_strategy"):
                        lines.append(f"  - {cp.get('capacityProvider')}: weight={cp.get('weight')}, base={cp.get('base', 0)}")
                lines.append(f"- **Task Definition**: `{svc.get('task_definition')}`")
                if svc.get("load_balancers"):
                    lines.append("- **Load Balancers**:")
                    for lb in svc.get("load_balancers"):
                        lines.append(f"  - Container `{lb.get('container_name')}:{lb.get('container_port')}`")
                lines.append("")

        # ECR Repositories
        repos = self.compute.get("ecr_repositories", [])
        if repos:
            lines.append("### ECR Repositories")
            lines.append("")
            for repo in repos:
                lines.append(f"- **{repo.get('name')}**: `{repo.get('uri')}`")
            lines.append("")

        # EC2 Instances
        instances = self.compute.get("ec2_instances", [])
        if instances:
            lines.append("### EC2 Instances")
            lines.append("")
            lines.append("| Name | ID | Type | State | AZ |")
            lines.append("|------|-----|------|-------|-----|")
            for inst in instances:
                name = inst.get("name") or "-"
                lines.append(f"| {name} | `{inst.get('id')}` | {inst.get('type')} | {inst.get('state')} | {inst.get('availability_zone')} |")
            lines.append("")

        # Lambda Functions
        lambdas = self.compute.get("lambda_functions", [])
        if lambdas:
            lines.append("### Lambda Functions")
            lines.append("")
            for fn in lambdas:
                lines.append(f"- **{fn.get('name')}** ({fn.get('runtime')}, {fn.get('memory')}MB)")
            lines.append("")

        return "\n".join(lines)

    def _data_section(self) -> str:
        lines = ["## Data Stores", ""]

        # RDS
        rds = self.data.get("rds_instances", [])
        if rds:
            lines.append("### RDS Instances")
            lines.append("")
            for db in rds:
                lines.append(f"#### {db.get('id')}")
                lines.append(f"- **Engine**: {db.get('engine')} {db.get('engine_version')}")
                lines.append(f"- **Class**: {db.get('instance_class')}")
                lines.append(f"- **Status**: {db.get('status')}")
                lines.append(f"- **Multi-AZ**: {db.get('multi_az')}")
                lines.append(f"- **Storage**: {db.get('allocated_storage')}GB {db.get('storage_type')}")
                lines.append(f"- **Endpoint**: `{db.get('endpoint')}:{db.get('port')}`")
                lines.append(f"- **Encrypted**: {db.get('encrypted')}")
                lines.append(f"- **Public**: {db.get('publicly_accessible')}")
                lines.append(f"- **Backup Retention**: {db.get('backup_retention')} days")
                lines.append("")

        # S3 Buckets
        buckets = self.data.get("s3_buckets", [])
        if buckets:
            lines.append("### S3 Buckets")
            lines.append("")
            # Filter to likely app-related buckets
            app_buckets = [b for b in buckets if "book" in b.get("name", "").lower() or "vault" in b.get("name", "").lower()]
            other_buckets = [b for b in buckets if b not in app_buckets]

            if app_buckets:
                lines.append("**Application Buckets:**")
                for bucket in app_buckets:
                    lines.append(f"- `{bucket.get('name')}` (Region: {bucket.get('region')})")
                lines.append("")

            if other_buckets:
                lines.append(f"**Other Buckets:** {len(other_buckets)} buckets in account")
                lines.append("")

        # ElastiCache
        cache = self.data.get("elasticache_clusters", [])
        if cache:
            lines.append("### ElastiCache Clusters")
            lines.append("")
            for c in cache:
                lines.append(f"- **{c.get('id')}**: {c.get('engine')} {c.get('node_type')} ({c.get('num_nodes')} nodes)")
            lines.append("")

        return "\n".join(lines)

    def _security_section(self) -> str:
        lines = ["## Security & IAM", ""]

        # IAM Roles
        roles = self.security.get("iam_roles", [])
        if roles:
            lines.append("### IAM Roles (Compute-related)")
            lines.append("")
            for role in roles:
                lines.append(f"- **{role.get('name')}**")
                if role.get("description"):
                    lines.append(f"  - {role.get('description')}")
            lines.append("")

        # Secrets
        secrets = self.security.get("secrets", [])
        if secrets:
            lines.append("### Secrets Manager")
            lines.append("")
            lines.append("| Secret Name | Description |")
            lines.append("|-------------|-------------|")
            for secret in secrets:
                desc = secret.get("description") or "-"
                lines.append(f"| `{secret.get('name')}` | {desc} |")
            lines.append("")

        # SSM Parameters
        params = self.security.get("ssm_parameters", [])
        if params:
            lines.append("### SSM Parameters")
            lines.append("")
            for param in params[:20]:  # Limit
                lines.append(f"- `{param.get('name')}` ({param.get('type')})")
            if len(params) > 20:
                lines.append(f"- ... and {len(params) - 20} more")
            lines.append("")

        # ACM Certificates
        certs = self.edge.get("acm_certificates", [])
        if certs:
            lines.append("### SSL/TLS Certificates")
            lines.append("")
            for cert in certs:
                lines.append(f"- **{cert.get('domain')}**")
                lines.append(f"  - Status: {cert.get('status')}")
                lines.append(f"  - Type: {cert.get('type')}")
                if cert.get("in_use_by"):
                    lines.append(f"  - In use by: {len(cert.get('in_use_by'))} resources")
            lines.append("")

        # Security Findings
        findings = self.relationships.get("security_findings", [])
        if findings:
            lines.append("### Security Findings")
            lines.append("")
            for finding in findings:
                severity_icon = "🔴" if finding.get("severity") == "high" else "🟡"
                lines.append(f"- {severity_icon} **{finding.get('type')}** on `{finding.get('name')}`")
                lines.append(f"  - {finding.get('detail')}")
            lines.append("")

        return "\n".join(lines)

    def _observability_section(self) -> str:
        lines = ["## Observability", ""]

        # Log Groups
        logs = self.observability.get("log_groups", [])
        if logs:
            lines.append("### CloudWatch Log Groups")
            lines.append("")
            for lg in logs:
                retention = f"{lg.get('retention_days')} days" if lg.get("retention_days") else "Never expire"
                lines.append(f"- `{lg.get('name')}` (Retention: {retention})")
            lines.append("")

        # Alarms
        alarms = self.observability.get("alarms", [])
        if alarms:
            lines.append("### CloudWatch Alarms")
            lines.append("")
            for alarm in alarms:
                state_icon = "🟢" if alarm.get("state") == "OK" else "🔴" if alarm.get("state") == "ALARM" else "⚪"
                lines.append(f"- {state_icon} **{alarm.get('name')}** ({alarm.get('state')})")
                if alarm.get("description"):
                    lines.append(f"  - {alarm.get('description')}")
            lines.append("")

        return "\n".join(lines)

    def _gaps_section(self) -> str:
        lines = ["## Known Gaps / Permissions Issues", ""]

        errors = self.gaps.get("permission_errors", [])
        if errors:
            lines.append("The following resources could not be queried due to permissions:")
            lines.append("")
            for error in errors:
                lines.append(f"- `{error.get('command')}`")
            lines.append("")
        else:
            lines.append("No permission issues encountered.")
            lines.append("")

        return "\n".join(lines)

    def _how_to_section(self) -> str:
        return """## Maintenance

### How to Re-run the Audit

```bash
cd infra-audit
./audit.sh
```

### How to Update the Diagram

If you have Graphviz installed:

```bash
dot -Tsvg ../docs/infra/production.dot -o ../docs/infra/production.svg
```

Install Graphviz:

```bash
# macOS
brew install graphviz

# Ubuntu/Debian
apt install graphviz
```

### Viewing the Diagram

Open `docs/infra/production.svg` in a browser or SVG viewer.

---

*This document was auto-generated. Do not edit manually.*
*Re-run the audit to update: `cd infra-audit && ./audit.sh`*"""


class DiagramGenerator:
    """Generate Graphviz DOT diagram from the normalized AWS inventory."""

    def __init__(self, summary: Dict):
        self.summary = summary
        self.meta = summary.get("meta", {})
        self.networking = summary.get("networking", {})
        self.compute = summary.get("compute", {})
        self.data = summary.get("data", {})
        self.edge = summary.get("edge", {})
        self.security = summary.get("security", {})

    def generate(self) -> str:
        """Generate the Graphviz DOT diagram."""
        lines = [
            'digraph BookVaultInfra {',
            '    // Graph settings',
            '    rankdir=TB;',
            '    compound=true;',
            '    fontname="Helvetica";',
            '    node [fontname="Helvetica", shape=box, style="filled,rounded"];',
            '    edge [fontname="Helvetica", fontsize=10];',
            '    bgcolor="white";',
            '    label=<<B>Book Vault AWS Infrastructure</B><BR/>'
            f'    <FONT POINT-SIZE="10">Account: {self.meta.get("account_id")} | '
            f'Region: {self.meta.get("region")} | '
            f'Generated: {self.meta.get("generated_at")}</FONT>>;',
            '    labelloc=t;',
            '    fontsize=16;',
            ''
        ]

        lines.extend(self._internet_node())
        lines.extend(self._dns_nodes())
        lines.extend(self._vpc_clusters())
        lines.extend(self._data_nodes())
        lines.extend(self._s3_nodes())
        lines.extend(self._edges())

        lines.append('}')
        return '\n'.join(lines)

    def _internet_node(self) -> List[str]:
        return [
            '    // Internet',
            '    internet [label="Internet\\n☁️", shape=ellipse, fillcolor="#E0E0E0"];',
            ''
        ]

    def _dns_nodes(self) -> List[str]:
        lines = ['    // DNS & Edge']

        zones = self.edge.get("route53_zones", [])
        if zones:
            for zone in zones:
                zone_id = zone.get("id", "").replace("-", "_")
                lines.append(f'    route53_{zone_id} [label="Route53\\n{zone.get("name")}", '
                           f'fillcolor="#F5B041", shape=box];')

        certs = self.edge.get("acm_certificates", [])
        if certs:
            # Just show one ACM node
            lines.append('    acm [label="ACM\\nSSL Certs", fillcolor="#AF7AC5", shape=box];')

        cloudfront = self.edge.get("cloudfront_distributions", [])
        if cloudfront:
            for dist in cloudfront:
                dist_id = dist.get("id", "").replace("-", "_")
                lines.append(f'    cf_{dist_id} [label="CloudFront\\n{dist.get("domain_name")}", '
                           f'fillcolor="#3498DB", shape=box];')

        lines.append('')
        return lines

    def _vpc_clusters(self) -> List[str]:
        lines = []

        vpcs = self.networking.get("vpcs", [])
        subnets = self.networking.get("subnets", [])
        lbs = self.networking.get("load_balancers", [])
        ecs_services = self.compute.get("ecs_services", [])
        ec2_instances = self.compute.get("ec2_instances", [])

        # Group subnets by VPC
        subnets_by_vpc = {}
        for subnet in subnets:
            vpc_id = subnet.get("vpc_id")
            if vpc_id not in subnets_by_vpc:
                subnets_by_vpc[vpc_id] = []
            subnets_by_vpc[vpc_id].append(subnet)

        for vpc in vpcs:
            vpc_id = vpc.get("id")
            vpc_name = vpc.get("name") or vpc_id
            vpc_id_safe = vpc_id.replace("-", "_")

            lines.append(f'    // VPC: {vpc_name}')
            lines.append(f'    subgraph cluster_{vpc_id_safe} {{')
            lines.append(f'        label=<<B>VPC: {vpc_name}</B><BR/><FONT POINT-SIZE="10">{vpc.get("cidr_block")}</FONT>>;')
            lines.append('        style="filled,rounded";')
            lines.append('        fillcolor="#EBF5FB";')
            lines.append('        color="#2980B9";')
            lines.append('')

            # Public subnets cluster
            public_subnets = [s for s in subnets_by_vpc.get(vpc_id, []) if s.get("is_public")]

            # Check for internet-facing ALBs in this VPC
            vpc_lbs = [lb for lb in lbs if lb.get("vpc_id") == vpc_id and lb.get("is_internet_facing")]

            if public_subnets or vpc_lbs:
                lines.append(f'        subgraph cluster_{vpc_id_safe}_public {{')
                lines.append('            label="Public Subnets";')
                lines.append('            style="filled,rounded";')
                lines.append('            fillcolor="#D5F5E3";')
                lines.append('            color="#27AE60";')
                lines.append('')

                # Add ALBs in public subnets
                for lb in vpc_lbs:
                    lb_id = lb.get("name", "").replace("-", "_")
                    lb_type = "ALB" if lb.get("type") == "application" else "NLB"
                    lines.append(f'            lb_{lb_id} [label="{lb_type}\\n{lb.get("name")}", '
                               f'fillcolor="#F39C12", shape=box];')

                # Only show a few representative subnets to avoid clutter
                shown_subnets = public_subnets[:3] if len(public_subnets) > 3 else public_subnets
                for subnet in shown_subnets:
                    subnet_id_safe = subnet.get("id", "").replace("-", "_")
                    az = subnet.get("availability_zone", "")[-2:] if subnet.get("availability_zone") else ""
                    label = subnet.get("name") or f"Public-{az}"
                    lines.append(f'            subnet_{subnet_id_safe} [label="{label}\\n{subnet.get("cidr_block")}", '
                               f'fillcolor="#ABEBC6", shape=box, style="filled"];')

                if len(public_subnets) > 3:
                    lines.append(f'            more_public [label="... +{len(public_subnets) - 3} more", shape=plaintext];')

                lines.append('        }')
                lines.append('')

            # Private subnets cluster
            private_subnets = [s for s in subnets_by_vpc.get(vpc_id, []) if not s.get("is_public")]

            # Find ECS services for this VPC (check if any subnet is in this VPC)
            vpc_subnet_ids = [s.get("id") for s in subnets_by_vpc.get(vpc_id, [])]
            vpc_ecs_services = [
                svc for svc in ecs_services
                if any(subnet_id in vpc_subnet_ids for subnet_id in svc.get("subnets", []))
            ]

            # Also check EC2 instances for this VPC
            vpc_ec2 = [inst for inst in ec2_instances if inst.get("vpc_id") == vpc_id]

            if private_subnets or vpc_ecs_services or vpc_ec2:
                cluster_type = "Private" if private_subnets else "Compute"
                cluster_color = "#FADBD8" if private_subnets else "#FCF3CF"
                border_color = "#E74C3C" if private_subnets else "#F39C12"

                lines.append(f'        subgraph cluster_{vpc_id_safe}_private {{')
                lines.append(f'            label="{cluster_type} Subnets / Compute";')
                lines.append('            style="filled,rounded";')
                lines.append(f'            fillcolor="{cluster_color}";')
                lines.append(f'            color="{border_color}";')
                lines.append('')

                # Add ECS services
                for svc in vpc_ecs_services:
                    svc_id = svc.get("name", "").replace("-", "_")
                    count = svc.get("running_count", 0)
                    lines.append(f'            ecs_{svc_id} [label="ECS Service\\n{svc.get("name")}\\n({count} tasks)", '
                               f'fillcolor="#FF9900", shape=box];')

                # Add EC2 instances (limit to 5)
                shown_ec2 = vpc_ec2[:5]
                for inst in shown_ec2:
                    inst_id = inst.get("id", "").replace("-", "_")
                    name = inst.get("name") or inst.get("id")
                    lines.append(f'            ec2_{inst_id} [label="EC2\\n{name}", '
                               f'fillcolor="#FF9900", shape=box];')

                if len(vpc_ec2) > 5:
                    lines.append(f'            more_ec2 [label="... +{len(vpc_ec2) - 5} EC2", shape=plaintext];')

                # Show private subnets (limit to 3)
                shown_private = private_subnets[:3] if len(private_subnets) > 3 else private_subnets
                for subnet in shown_private:
                    subnet_id_safe = subnet.get("id", "").replace("-", "_")
                    az = subnet.get("availability_zone", "")[-2:] if subnet.get("availability_zone") else ""
                    label = subnet.get("name") or f"Private-{az}"
                    lines.append(f'            subnet_{subnet_id_safe} [label="{label}\\n{subnet.get("cidr_block")}", '
                               f'fillcolor="#F5B7B1", shape=box, style="filled"];')

                if len(private_subnets) > 3:
                    lines.append(f'            more_private [label="... +{len(private_subnets) - 3} more", shape=plaintext];')

                lines.append('        }')
                lines.append('')

            lines.append('    }')
            lines.append('')

        return lines

    def _data_nodes(self) -> List[str]:
        lines = ['    // Data Stores']

        rds = self.data.get("rds_instances", [])
        for db in rds:
            db_id = db.get("id", "").replace("-", "_")
            engine = db.get("engine", "").upper()
            lines.append(f'    rds_{db_id} [label="RDS {engine}\\n{db.get("id")}", '
                       f'fillcolor="#3498DB", shape=cylinder];')

        cache = self.data.get("elasticache_clusters", [])
        for c in cache:
            cache_id = c.get("id", "").replace("-", "_")
            lines.append(f'    cache_{cache_id} [label="ElastiCache\\n{c.get("id")}", '
                       f'fillcolor="#E74C3C", shape=cylinder];')

        lines.append('')
        return lines

    def _s3_nodes(self) -> List[str]:
        lines = ['    // S3 Buckets']

        buckets = self.data.get("s3_buckets", [])
        # Only show app-related buckets
        app_buckets = [b for b in buckets
                       if "book" in b.get("name", "").lower()
                       or "vault" in b.get("name", "").lower()]

        for bucket in app_buckets:
            bucket_id = bucket.get("name", "").replace("-", "_").replace(".", "_")
            lines.append(f'    s3_{bucket_id} [label="S3\\n{bucket.get("name")}", '
                       f'fillcolor="#27AE60", shape=folder];')

        lines.append('')
        return lines

    def _edges(self) -> List[str]:
        lines = ['    // Connections']

        # Internet -> Route53
        zones = self.edge.get("route53_zones", [])
        for zone in zones:
            zone_id = zone.get("id", "").replace("-", "_")
            lines.append(f'    internet -> route53_{zone_id} [label="DNS"];')

        # Route53 -> ALB (via alias records)
        lbs = self.networking.get("load_balancers", [])
        for lb in lbs:
            if lb.get("is_internet_facing"):
                lb_id = lb.get("name", "").replace("-", "_")
                if zones:
                    zone_id = zones[0].get("id", "").replace("-", "_")
                    lines.append(f'    route53_{zone_id} -> lb_{lb_id} [label="HTTPS"];')
                else:
                    lines.append(f'    internet -> lb_{lb_id} [label="HTTPS"];')

        # ALB -> ECS Services
        ecs_services = self.compute.get("ecs_services", [])
        for svc in ecs_services:
            svc_id = svc.get("name", "").replace("-", "_")
            for svc_lb in svc.get("load_balancers", []):
                # Find matching ALB
                for lb in lbs:
                    lb_id = lb.get("name", "").replace("-", "_")
                    port = svc_lb.get("container_port", "")
                    lines.append(f'    lb_{lb_id} -> ecs_{svc_id} [label=":{port}"];')
                    break

        # ECS -> RDS
        rds = self.data.get("rds_instances", [])
        for svc in ecs_services:
            svc_id = svc.get("name", "").replace("-", "_")
            for db in rds:
                db_id = db.get("id", "").replace("-", "_")
                lines.append(f'    ecs_{svc_id} -> rds_{db_id} [label=":5432", style=dashed];')

        # ECS -> S3
        buckets = self.data.get("s3_buckets", [])
        app_buckets = [b for b in buckets
                       if "book" in b.get("name", "").lower()
                       or "vault" in b.get("name", "").lower()]
        for svc in ecs_services:
            svc_id = svc.get("name", "").replace("-", "_")
            for bucket in app_buckets:
                bucket_id = bucket.get("name", "").replace("-", "_").replace(".", "_")
                lines.append(f'    ecs_{svc_id} -> s3_{bucket_id} [label="S3 API", style=dashed];')

        lines.append('')
        return lines


def render_svg(dot_path: Path, svg_path: Path) -> bool:
    """Render DOT to SVG using Graphviz."""
    try:
        result = subprocess.run(
            ["dot", "-Tsvg", str(dot_path), "-o", str(svg_path)],
            capture_output=True,
            text=True
        )
        if result.returncode != 0:
            print(f"Graphviz error: {result.stderr}", file=sys.stderr)
            return False
        return True
    except FileNotFoundError:
        print("Graphviz not found. Install with: brew install graphviz", file=sys.stderr)
        return False


def main():
    parser = argparse.ArgumentParser(description="Generate infrastructure documentation")
    parser.add_argument("--summary", required=True, help="Path to summary.json")
    parser.add_argument("--docs-dir", required=True, help="Output directory for docs")
    parser.add_argument("--skip-diagram", default="false", help="Skip SVG rendering")

    args = parser.parse_args()
    skip_diagram = args.skip_diagram.lower() == "true"

    # Load summary
    summary_path = Path(args.summary)
    if not summary_path.exists():
        print(f"Error: {summary_path} not found", file=sys.stderr)
        sys.exit(1)

    with open(summary_path) as f:
        summary = json.load(f)

    docs_dir = Path(args.docs_dir)
    docs_dir.mkdir(parents=True, exist_ok=True)

    # Generate Markdown
    doc_gen = DocumentationGenerator(summary)
    markdown = doc_gen.generate()

    md_path = docs_dir / "production.md"
    with open(md_path, "w") as f:
        f.write(markdown)
    print(f"Wrote documentation to {md_path}")

    # Generate DOT diagram
    diagram_gen = DiagramGenerator(summary)
    dot = diagram_gen.generate()

    dot_path = docs_dir / "production.dot"
    with open(dot_path, "w") as f:
        f.write(dot)
    print(f"Wrote diagram source to {dot_path}")

    # Render SVG
    if not skip_diagram:
        svg_path = docs_dir / "production.svg"
        if render_svg(dot_path, svg_path):
            print(f"Wrote diagram to {svg_path}")
        else:
            print("SVG rendering skipped (Graphviz not available)")


if __name__ == "__main__":
    main()
