#!/usr/bin/env python3
"""
Normalize raw AWS CLI JSON outputs into a unified summary.json schema.

This script reads the raw JSON files from the audit and produces a normalized
inventory with inferred relationships.
"""

import argparse
import json
import os
import re
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional


def load_json_file(path: Path) -> Optional[Dict]:
    """Load a JSON file, returning None if it doesn't exist or has errors."""
    if not path.exists():
        return None
    try:
        with open(path) as f:
            data = json.load(f)
            # Check if it's an error response
            if isinstance(data, dict) and "error" in data:
                return None
            return data
    except (json.JSONDecodeError, Exception):
        return None


def get_name_tag(tags: List[Dict]) -> Optional[str]:
    """Extract the Name tag from a list of AWS tags."""
    if not tags:
        return None
    for tag in tags:
        if tag.get("Key") == "Name":
            return tag.get("Value")
    return None


def extract_resource_id_from_arn(arn: str) -> str:
    """Extract the resource ID from an ARN."""
    if not arn:
        return ""
    parts = arn.split("/")
    return parts[-1] if parts else arn.split(":")[-1]


class AWSNormalizer:
    def __init__(self, raw_dir: Path, account_id: str, region: str,
                 generated_at: str, version: str):
        self.raw_dir = raw_dir
        self.account_id = account_id
        self.region = region
        self.generated_at = generated_at
        self.version = version

        # Storage for cross-referencing
        self.vpc_map: Dict[str, Dict] = {}
        self.subnet_map: Dict[str, Dict] = {}
        self.sg_map: Dict[str, Dict] = {}
        self.role_map: Dict[str, Dict] = {}

    def normalize(self) -> Dict:
        """Main normalization entry point."""
        return {
            "meta": self._build_meta(),
            "networking": self._normalize_networking(),
            "compute": self._normalize_compute(),
            "data": self._normalize_data(),
            "edge": self._normalize_edge(),
            "security": self._normalize_security(),
            "observability": self._normalize_observability(),
            "relationships": self._infer_relationships(),
            "gaps": self._collect_gaps()
        }

    def _build_meta(self) -> Dict:
        """Build metadata section."""
        # Try to get account alias
        account_alias = None
        caller_identity = load_json_file(self.raw_dir / "caller-identity.json")

        return {
            "account_id": self.account_id,
            "account_alias": account_alias,
            "region": self.region,
            "generated_at": self.generated_at,
            "audit_version": self.version
        }

    def _normalize_networking(self) -> Dict:
        """Normalize networking resources."""
        return {
            "vpcs": self._normalize_vpcs(),
            "subnets": self._normalize_subnets(),
            "route_tables": self._normalize_route_tables(),
            "internet_gateways": self._normalize_igws(),
            "nat_gateways": self._normalize_nat_gws(),
            "vpc_endpoints": self._normalize_vpc_endpoints(),
            "security_groups": self._normalize_security_groups(),
            "load_balancers": self._normalize_load_balancers()
        }

    def _normalize_vpcs(self) -> List[Dict]:
        """Normalize VPC data."""
        data = load_json_file(self.raw_dir / "vpcs.json")
        if not data:
            return []

        vpcs = []
        for vpc in data.get("Vpcs", []):
            vpc_id = vpc.get("VpcId")
            normalized = {
                "id": vpc_id,
                "name": get_name_tag(vpc.get("Tags", [])),
                "cidr_block": vpc.get("CidrBlock"),
                "state": vpc.get("State"),
                "is_default": vpc.get("IsDefault", False),
                "dhcp_options_id": vpc.get("DhcpOptionsId")
            }
            vpcs.append(normalized)
            self.vpc_map[vpc_id] = normalized

        return vpcs

    def _normalize_subnets(self) -> List[Dict]:
        """Normalize subnet data."""
        data = load_json_file(self.raw_dir / "subnets.json")
        if not data:
            return []

        subnets = []
        for subnet in data.get("Subnets", []):
            subnet_id = subnet.get("SubnetId")
            normalized = {
                "id": subnet_id,
                "name": get_name_tag(subnet.get("Tags", [])),
                "vpc_id": subnet.get("VpcId"),
                "cidr_block": subnet.get("CidrBlock"),
                "availability_zone": subnet.get("AvailabilityZone"),
                "map_public_ip": subnet.get("MapPublicIpOnLaunch", False),
                "available_ips": subnet.get("AvailableIpAddressCount"),
                "is_public": False  # Will be determined from route tables
            }
            subnets.append(normalized)
            self.subnet_map[subnet_id] = normalized

        return subnets

    def _normalize_route_tables(self) -> List[Dict]:
        """Normalize route table data and determine public subnets."""
        data = load_json_file(self.raw_dir / "route-tables.json")
        if not data:
            return []

        route_tables = []
        main_rt_by_vpc = {}  # Track main route tables by VPC

        for rt in data.get("RouteTables", []):
            # Check if any route points to an IGW (making associated subnets public)
            has_igw_route = any(
                r.get("GatewayId", "").startswith("igw-")
                for r in rt.get("Routes", [])
            )

            associations = []
            is_main = False
            for assoc in rt.get("Associations", []):
                if assoc.get("Main"):
                    is_main = True
                    vpc_id = rt.get("VpcId")
                    if has_igw_route:
                        main_rt_by_vpc[vpc_id] = True  # VPC's main RT has IGW
                subnet_id = assoc.get("SubnetId")
                if subnet_id:
                    associations.append(subnet_id)
                    # Mark subnet as public if it has IGW route
                    if has_igw_route and subnet_id in self.subnet_map:
                        self.subnet_map[subnet_id]["is_public"] = True

            normalized = {
                "id": rt.get("RouteTableId"),
                "name": get_name_tag(rt.get("Tags", [])),
                "vpc_id": rt.get("VpcId"),
                "is_main": is_main,
                "associated_subnets": associations,
                "has_igw_route": has_igw_route,
                "routes": [
                    {
                        "destination": r.get("DestinationCidrBlock") or r.get("DestinationPrefixListId"),
                        "target": r.get("GatewayId") or r.get("NatGatewayId") or
                                  r.get("NetworkInterfaceId") or r.get("VpcPeeringConnectionId") or "local"
                    }
                    for r in rt.get("Routes", [])
                ]
            }
            route_tables.append(normalized)

        # Mark subnets as public if they use a main route table with IGW
        # (subnets without explicit RT association use the main RT)
        explicitly_associated = set()
        for rt in route_tables:
            explicitly_associated.update(rt.get("associated_subnets", []))

        for subnet_id, subnet in self.subnet_map.items():
            if subnet_id not in explicitly_associated:
                vpc_id = subnet.get("vpc_id")
                if main_rt_by_vpc.get(vpc_id):
                    subnet["is_public"] = True

        return route_tables

    def _normalize_igws(self) -> List[Dict]:
        """Normalize Internet Gateway data."""
        data = load_json_file(self.raw_dir / "internet-gateways.json")
        if not data:
            return []

        return [
            {
                "id": igw.get("InternetGatewayId"),
                "name": get_name_tag(igw.get("Tags", [])),
                "vpc_id": igw.get("Attachments", [{}])[0].get("VpcId") if igw.get("Attachments") else None,
                "state": igw.get("Attachments", [{}])[0].get("State") if igw.get("Attachments") else None
            }
            for igw in data.get("InternetGateways", [])
        ]

    def _normalize_nat_gws(self) -> List[Dict]:
        """Normalize NAT Gateway data."""
        data = load_json_file(self.raw_dir / "nat-gateways.json")
        if not data:
            return []

        return [
            {
                "id": nat.get("NatGatewayId"),
                "name": get_name_tag(nat.get("Tags", [])),
                "vpc_id": nat.get("VpcId"),
                "subnet_id": nat.get("SubnetId"),
                "state": nat.get("State"),
                "public_ip": nat.get("NatGatewayAddresses", [{}])[0].get("PublicIp") if nat.get("NatGatewayAddresses") else None
            }
            for nat in data.get("NatGateways", [])
        ]

    def _normalize_vpc_endpoints(self) -> List[Dict]:
        """Normalize VPC Endpoint data."""
        data = load_json_file(self.raw_dir / "vpc-endpoints.json")
        if not data:
            return []

        return [
            {
                "id": ep.get("VpcEndpointId"),
                "name": get_name_tag(ep.get("Tags", [])),
                "vpc_id": ep.get("VpcId"),
                "service_name": ep.get("ServiceName"),
                "type": ep.get("VpcEndpointType"),
                "state": ep.get("State"),
                "subnet_ids": ep.get("SubnetIds", [])
            }
            for ep in data.get("VpcEndpoints", [])
        ]

    def _normalize_security_groups(self) -> List[Dict]:
        """Normalize Security Group data."""
        data = load_json_file(self.raw_dir / "security-groups.json")
        if not data:
            return []

        sgs = []
        for sg in data.get("SecurityGroups", []):
            sg_id = sg.get("GroupId")

            # Process ingress rules
            ingress_rules = []
            for rule in sg.get("IpPermissions", []):
                for ip_range in rule.get("IpRanges", []):
                    ingress_rules.append({
                        "protocol": rule.get("IpProtocol"),
                        "from_port": rule.get("FromPort"),
                        "to_port": rule.get("ToPort"),
                        "source": ip_range.get("CidrIp"),
                        "description": ip_range.get("Description", "")
                    })
                for sg_ref in rule.get("UserIdGroupPairs", []):
                    ingress_rules.append({
                        "protocol": rule.get("IpProtocol"),
                        "from_port": rule.get("FromPort"),
                        "to_port": rule.get("ToPort"),
                        "source_sg": sg_ref.get("GroupId"),
                        "description": sg_ref.get("Description", "")
                    })

            # Process egress rules
            egress_rules = []
            for rule in sg.get("IpPermissionsEgress", []):
                for ip_range in rule.get("IpRanges", []):
                    egress_rules.append({
                        "protocol": rule.get("IpProtocol"),
                        "from_port": rule.get("FromPort"),
                        "to_port": rule.get("ToPort"),
                        "destination": ip_range.get("CidrIp"),
                        "description": ip_range.get("Description", "")
                    })

            normalized = {
                "id": sg_id,
                "name": sg.get("GroupName"),
                "description": sg.get("Description"),
                "vpc_id": sg.get("VpcId"),
                "ingress_rules": ingress_rules,
                "egress_rules": egress_rules,
                "has_wide_open_ingress": any(
                    r.get("source") == "0.0.0.0/0" for r in ingress_rules
                )
            }
            sgs.append(normalized)
            self.sg_map[sg_id] = normalized

        return sgs

    def _normalize_load_balancers(self) -> List[Dict]:
        """Normalize Load Balancer data."""
        data = load_json_file(self.raw_dir / "load-balancers.json")
        if not data:
            return []

        # Load listener and target group data
        listeners_data = load_json_file(self.raw_dir / "all-listeners.json")
        tg_data = load_json_file(self.raw_dir / "target-groups.json")
        target_health_data = load_json_file(self.raw_dir / "all-target-health.json")

        listeners_by_lb = {}
        if listeners_data:
            for listener in listeners_data.get("Listeners", []):
                lb_arn = listener.get("LoadBalancerArn")
                if lb_arn not in listeners_by_lb:
                    listeners_by_lb[lb_arn] = []
                listeners_by_lb[lb_arn].append({
                    "arn": listener.get("ListenerArn"),
                    "port": listener.get("Port"),
                    "protocol": listener.get("Protocol"),
                    "ssl_policy": listener.get("SslPolicy"),
                    "certificates": [c.get("CertificateArn") for c in listener.get("Certificates", [])]
                })

        tg_map = {}
        if tg_data:
            for tg in tg_data.get("TargetGroups", []):
                tg_map[tg.get("TargetGroupArn")] = {
                    "arn": tg.get("TargetGroupArn"),
                    "name": tg.get("TargetGroupName"),
                    "port": tg.get("Port"),
                    "protocol": tg.get("Protocol"),
                    "target_type": tg.get("TargetType"),
                    "health_check_path": tg.get("HealthCheckPath"),
                    "vpc_id": tg.get("VpcId"),
                    "targets": []
                }

        # Add target health info
        if target_health_data:
            for health in target_health_data.get("TargetHealth", []):
                tg_arn = health.get("TargetGroupArn")
                if tg_arn in tg_map:
                    tg_map[tg_arn]["targets"] = [
                        {
                            "id": t.get("Target", {}).get("Id"),
                            "port": t.get("Target", {}).get("Port"),
                            "health": t.get("TargetHealth", {}).get("State"),
                            "reason": t.get("TargetHealth", {}).get("Reason")
                        }
                        for t in health.get("Targets", [])
                    ]

        lbs = []
        for lb in data.get("LoadBalancers", []):
            lb_arn = lb.get("LoadBalancerArn")

            # Find target groups associated with this LB's listeners
            lb_target_groups = []
            for listener in listeners_by_lb.get(lb_arn, []):
                # We'd need to look at listener rules to get exact TGs
                pass

            normalized = {
                "arn": lb_arn,
                "name": lb.get("LoadBalancerName"),
                "type": lb.get("Type"),
                "scheme": lb.get("Scheme"),
                "state": lb.get("State", {}).get("Code"),
                "dns_name": lb.get("DNSName"),
                "vpc_id": lb.get("VpcId"),
                "availability_zones": [az.get("ZoneName") for az in lb.get("AvailabilityZones", [])],
                "subnets": [az.get("SubnetId") for az in lb.get("AvailabilityZones", [])],
                "security_groups": lb.get("SecurityGroups", []),
                "listeners": listeners_by_lb.get(lb_arn, []),
                "is_internet_facing": lb.get("Scheme") == "internet-facing"
            }
            lbs.append(normalized)

        # Add target groups as separate list
        self.target_groups = list(tg_map.values())

        return lbs

    def _normalize_compute(self) -> Dict:
        """Normalize compute resources."""
        return {
            "ec2_instances": self._normalize_ec2(),
            "auto_scaling_groups": self._normalize_asgs(),
            "ecs_clusters": self._normalize_ecs(),
            "ecs_services": self._normalize_ecs_services(),
            "ecr_repositories": self._normalize_ecr(),
            "lambda_functions": self._normalize_lambda()
        }

    def _normalize_ec2(self) -> List[Dict]:
        """Normalize EC2 instance data."""
        data = load_json_file(self.raw_dir / "ec2-instances.json")
        if not data:
            return []

        instances = []
        for reservation in data.get("Reservations", []):
            for instance in reservation.get("Instances", []):
                instances.append({
                    "id": instance.get("InstanceId"),
                    "name": get_name_tag(instance.get("Tags", [])),
                    "type": instance.get("InstanceType"),
                    "state": instance.get("State", {}).get("Name"),
                    "ami": instance.get("ImageId"),
                    "vpc_id": instance.get("VpcId"),
                    "subnet_id": instance.get("SubnetId"),
                    "availability_zone": instance.get("Placement", {}).get("AvailabilityZone"),
                    "private_ip": instance.get("PrivateIpAddress"),
                    "public_ip": instance.get("PublicIpAddress"),
                    "security_groups": [sg.get("GroupId") for sg in instance.get("SecurityGroups", [])],
                    "iam_instance_profile": instance.get("IamInstanceProfile", {}).get("Arn")
                })

        return instances

    def _normalize_asgs(self) -> List[Dict]:
        """Normalize Auto Scaling Group data."""
        data = load_json_file(self.raw_dir / "auto-scaling-groups.json")
        if not data:
            return []

        return [
            {
                "name": asg.get("AutoScalingGroupName"),
                "arn": asg.get("AutoScalingGroupARN"),
                "min_size": asg.get("MinSize"),
                "max_size": asg.get("MaxSize"),
                "desired_capacity": asg.get("DesiredCapacity"),
                "launch_template": asg.get("LaunchTemplate", {}).get("LaunchTemplateId"),
                "vpc_zones": asg.get("AvailabilityZones", []),
                "subnets": asg.get("VPCZoneIdentifier", "").split(",") if asg.get("VPCZoneIdentifier") else [],
                "target_groups": [tg.split("/")[1] if "/" in tg else tg for tg in asg.get("TargetGroupARNs", [])],
                "instances": [i.get("InstanceId") for i in asg.get("Instances", [])]
            }
            for asg in data.get("AutoScalingGroups", [])
        ]

    def _normalize_ecs(self) -> List[Dict]:
        """Normalize ECS cluster data."""
        data = load_json_file(self.raw_dir / "ecs-cluster-details.json")
        if not data:
            return []

        return [
            {
                "arn": cluster.get("clusterArn"),
                "name": cluster.get("clusterName"),
                "status": cluster.get("status"),
                "running_tasks": cluster.get("runningTasksCount", 0),
                "pending_tasks": cluster.get("pendingTasksCount", 0),
                "active_services": cluster.get("activeServicesCount", 0),
                "registered_instances": cluster.get("registeredContainerInstancesCount", 0),
                "capacity_providers": cluster.get("capacityProviders", [])
            }
            for cluster in data.get("clusters", [])
        ]

    def _normalize_ecs_services(self) -> List[Dict]:
        """Normalize ECS service data."""
        services = []

        # Find all service detail files
        for f in self.raw_dir.glob("ecs-service-details-*.json"):
            data = load_json_file(f)
            if not data:
                continue

            for svc in data.get("services", []):
                # Extract task definition details
                task_def = svc.get("taskDefinition", "")

                services.append({
                    "arn": svc.get("serviceArn"),
                    "name": svc.get("serviceName"),
                    "cluster_arn": svc.get("clusterArn"),
                    "status": svc.get("status"),
                    "desired_count": svc.get("desiredCount"),
                    "running_count": svc.get("runningCount"),
                    "pending_count": svc.get("pendingCount"),
                    "task_definition": task_def,
                    "launch_type": svc.get("launchType"),
                    "capacity_provider_strategy": svc.get("capacityProviderStrategy", []),
                    "load_balancers": [
                        {
                            "target_group_arn": lb.get("targetGroupArn"),
                            "container_name": lb.get("containerName"),
                            "container_port": lb.get("containerPort")
                        }
                        for lb in svc.get("loadBalancers", [])
                    ],
                    "subnets": svc.get("networkConfiguration", {}).get("awsvpcConfiguration", {}).get("subnets", []),
                    "security_groups": svc.get("networkConfiguration", {}).get("awsvpcConfiguration", {}).get("securityGroups", []),
                    "created_at": svc.get("createdAt"),
                    "role_arn": svc.get("roleArn")
                })

        return services

    def _normalize_ecr(self) -> List[Dict]:
        """Normalize ECR repository data."""
        data = load_json_file(self.raw_dir / "ecr-repositories.json")
        if not data:
            return []

        return [
            {
                "arn": repo.get("repositoryArn"),
                "name": repo.get("repositoryName"),
                "uri": repo.get("repositoryUri"),
                "created_at": repo.get("createdAt"),
                "image_tag_mutability": repo.get("imageTagMutability"),
                "scan_on_push": repo.get("imageScanningConfiguration", {}).get("scanOnPush", False)
            }
            for repo in data.get("repositories", [])
        ]

    def _normalize_lambda(self) -> List[Dict]:
        """Normalize Lambda function data with triggers."""
        data = load_json_file(self.raw_dir / "lambda-functions.json")
        if not data:
            return []

        functions = []
        for fn in data.get("Functions", []):
            func_name = fn.get("FunctionName", "")

            # Parse resource-based policy to find triggers
            triggers = []
            policy_data = load_json_file(self.raw_dir / f"lambda-policy-{func_name}.json")
            if policy_data and policy_data.get("Policy"):
                try:
                    import json as json_mod
                    pol = json_mod.loads(policy_data["Policy"])
                    for stmt in pol.get("Statement", []):
                        source_arn = stmt.get("Condition", {}).get(
                            "ArnLike", {}
                        ).get("AWS:SourceArn", "")
                        if source_arn:
                            triggers.append({
                                "source": stmt.get("Principal", {}).get("Service", ""),
                                "source_arn": source_arn,
                                "statement_id": stmt.get("Sid", ""),
                            })
                except Exception:
                    pass

            functions.append({
                "arn": fn.get("FunctionArn"),
                "name": func_name,
                "runtime": fn.get("Runtime"),
                "memory": fn.get("MemorySize"),
                "timeout": fn.get("Timeout"),
                "handler": fn.get("Handler"),
                "architecture": fn.get("Architectures", ["x86_64"])[0],
                "role": fn.get("Role", "").split("/")[-1] if fn.get("Role") else None,
                "description": fn.get("Description"),
                "vpc_config": {
                    "vpc_id": fn.get("VpcConfig", {}).get("VpcId"),
                    "subnets": fn.get("VpcConfig", {}).get("SubnetIds", []),
                    "security_groups": fn.get("VpcConfig", {}).get("SecurityGroupIds", [])
                } if fn.get("VpcConfig") else None,
                "last_modified": fn.get("LastModified"),
                "triggers": triggers,
            })

        return functions

    def _normalize_data(self) -> Dict:
        """Normalize data store resources."""
        return {
            "rds_instances": self._normalize_rds_instances(),
            "rds_clusters": self._normalize_rds_clusters(),
            "elasticache_clusters": self._normalize_elasticache(),
            "s3_buckets": self._normalize_s3()
        }

    def _normalize_rds_instances(self) -> List[Dict]:
        """Normalize RDS instance data."""
        data = load_json_file(self.raw_dir / "rds-instances.json")
        if not data:
            return []

        return [
            {
                "id": db.get("DBInstanceIdentifier"),
                "arn": db.get("DBInstanceArn"),
                "engine": db.get("Engine"),
                "engine_version": db.get("EngineVersion"),
                "instance_class": db.get("DBInstanceClass"),
                "status": db.get("DBInstanceStatus"),
                "multi_az": db.get("MultiAZ", False),
                "storage_type": db.get("StorageType"),
                "allocated_storage": db.get("AllocatedStorage"),
                "endpoint": db.get("Endpoint", {}).get("Address"),
                "port": db.get("Endpoint", {}).get("Port"),
                "vpc_id": db.get("DBSubnetGroup", {}).get("VpcId"),
                "subnet_group": db.get("DBSubnetGroup", {}).get("DBSubnetGroupName"),
                "security_groups": [sg.get("VpcSecurityGroupId") for sg in db.get("VpcSecurityGroups", [])],
                "publicly_accessible": db.get("PubliclyAccessible", False),
                "encrypted": db.get("StorageEncrypted", False),
                "backup_retention": db.get("BackupRetentionPeriod")
            }
            for db in data.get("DBInstances", [])
        ]

    def _normalize_rds_clusters(self) -> List[Dict]:
        """Normalize RDS cluster data."""
        data = load_json_file(self.raw_dir / "rds-clusters.json")
        if not data:
            return []

        return [
            {
                "id": cluster.get("DBClusterIdentifier"),
                "arn": cluster.get("DBClusterArn"),
                "engine": cluster.get("Engine"),
                "engine_version": cluster.get("EngineVersion"),
                "status": cluster.get("Status"),
                "multi_az": cluster.get("MultiAZ", False),
                "endpoint": cluster.get("Endpoint"),
                "reader_endpoint": cluster.get("ReaderEndpoint"),
                "port": cluster.get("Port"),
                "members": [m.get("DBInstanceIdentifier") for m in cluster.get("DBClusterMembers", [])]
            }
            for cluster in data.get("DBClusters", [])
        ]

    def _normalize_elasticache(self) -> List[Dict]:
        """Normalize ElastiCache cluster data."""
        data = load_json_file(self.raw_dir / "elasticache-clusters.json")
        if not data:
            return []

        return [
            {
                "id": cache.get("CacheClusterId"),
                "arn": cache.get("ARN"),
                "engine": cache.get("Engine"),
                "engine_version": cache.get("EngineVersion"),
                "node_type": cache.get("CacheNodeType"),
                "status": cache.get("CacheClusterStatus"),
                "num_nodes": cache.get("NumCacheNodes"),
                "endpoint": cache.get("ConfigurationEndpoint", {}).get("Address") if cache.get("ConfigurationEndpoint") else None
            }
            for cache in data.get("CacheClusters", [])
        ]

    def _normalize_s3(self) -> List[Dict]:
        """Normalize S3 bucket data."""
        data = load_json_file(self.raw_dir / "s3-buckets.json")
        details = load_json_file(self.raw_dir / "s3-bucket-details.json")

        if not data:
            return []

        details_map = {}
        if details:
            for bucket in details.get("BucketDetails", []):
                details_map[bucket.get("Name")] = bucket

        return [
            {
                "name": bucket.get("Name"),
                "created": bucket.get("CreationDate"),
                "region": details_map.get(bucket.get("Name"), {}).get("Location", "us-east-1"),
                "tags": details_map.get(bucket.get("Name"), {}).get("Tags", [])
            }
            for bucket in data.get("Buckets", [])
        ]

    def _normalize_edge(self) -> Dict:
        """Normalize edge/DNS resources."""
        return {
            "route53_zones": self._normalize_route53(),
            "acm_certificates": self._normalize_acm(),
            "cloudfront_distributions": self._normalize_cloudfront()
        }

    def _normalize_route53(self) -> List[Dict]:
        """Normalize Route53 zone data."""
        data = load_json_file(self.raw_dir / "route53-zones.json")
        if not data:
            return []

        zones = []
        for zone in data.get("HostedZones", []):
            zone_id = zone.get("Id", "").replace("/hostedzone/", "")

            # Load records for this zone
            records_data = load_json_file(self.raw_dir / f"route53-records-{zone_id}.json")

            # Filter to relevant records (A, AAAA, CNAME pointing to AWS resources)
            relevant_records = []
            if records_data:
                for record in records_data.get("ResourceRecordSets", []):
                    record_type = record.get("Type")
                    if record_type in ["A", "AAAA", "CNAME"]:
                        # Check if it's an alias to AWS resource
                        alias = record.get("AliasTarget", {})
                        relevant_records.append({
                            "name": record.get("Name"),
                            "type": record_type,
                            "ttl": record.get("TTL"),
                            "alias_target": alias.get("DNSName") if alias else None,
                            "alias_zone_id": alias.get("HostedZoneId") if alias else None,
                            "values": [rr.get("Value") for rr in record.get("ResourceRecords", [])]
                        })

            zones.append({
                "id": zone_id,
                "name": zone.get("Name"),
                "private": zone.get("Config", {}).get("PrivateZone", False),
                "record_count": zone.get("ResourceRecordSetCount"),
                "relevant_records": relevant_records
            })

        return zones

    def _normalize_acm(self) -> List[Dict]:
        """Normalize ACM certificate data."""
        data = load_json_file(self.raw_dir / "acm-certificate-details.json")
        if not data:
            return []

        return [
            {
                "arn": cert.get("CertificateArn"),
                "domain": cert.get("DomainName"),
                "status": cert.get("Status"),
                "type": cert.get("Type"),
                "issuer": cert.get("Issuer"),
                "not_before": cert.get("NotBefore"),
                "not_after": cert.get("NotAfter"),
                "in_use_by": cert.get("InUseBy", []),
                "subject_alternative_names": cert.get("SubjectAlternativeNames", [])
            }
            for cert in data.get("Certificates", [])
        ]

    def _normalize_cloudfront(self) -> List[Dict]:
        """Normalize CloudFront distribution data."""
        data = load_json_file(self.raw_dir / "cloudfront-distributions.json")
        if not data or not data.get("DistributionList"):
            return []

        return [
            {
                "id": dist.get("Id"),
                "arn": dist.get("ARN"),
                "domain_name": dist.get("DomainName"),
                "status": dist.get("Status"),
                "enabled": dist.get("Enabled"),
                "aliases": dist.get("Aliases", {}).get("Items", []),
                "origins": [
                    {
                        "id": o.get("Id"),
                        "domain": o.get("DomainName"),
                        "path": o.get("OriginPath")
                    }
                    for o in dist.get("Origins", {}).get("Items", [])
                ]
            }
            for dist in data.get("DistributionList", {}).get("Items", [])
        ]

    def _normalize_security(self) -> Dict:
        """Normalize security resources."""
        return {
            "iam_roles": self._normalize_iam_roles(),
            "secrets": self._normalize_secrets(),
            "ssm_parameters": self._normalize_ssm_params()
        }

    def _normalize_iam_roles(self) -> List[Dict]:
        """Normalize IAM role data (only roles used by compute)."""
        data = load_json_file(self.raw_dir / "iam-roles.json")
        if not data:
            return []

        # Filter to roles that look like they're used by ECS/EC2
        compute_role_patterns = [
            "ecs", "ec2", "task", "execution", "instance", "lambda",
            "book-vault", "bookvault"
        ]

        roles = []
        for role in data.get("Roles", []):
            role_name = role.get("RoleName", "").lower()
            if any(pattern in role_name for pattern in compute_role_patterns):
                roles.append({
                    "arn": role.get("Arn"),
                    "name": role.get("RoleName"),
                    "path": role.get("Path"),
                    "created": role.get("CreateDate"),
                    "description": role.get("Description"),
                    "max_session_duration": role.get("MaxSessionDuration")
                })
                self.role_map[role.get("Arn")] = role.get("RoleName")

        return roles

    def _normalize_secrets(self) -> List[Dict]:
        """Normalize Secrets Manager data (names only, no values)."""
        data = load_json_file(self.raw_dir / "secrets.json")
        if not data:
            return []

        return [
            {
                "arn": secret.get("ARN"),
                "name": secret.get("Name"),
                "description": secret.get("Description"),
                "last_rotated": secret.get("LastRotatedDate"),
                "last_accessed": secret.get("LastAccessedDate"),
                "tags": secret.get("Tags", [])
            }
            for secret in data.get("SecretList", [])
        ]

    def _normalize_ssm_params(self) -> List[Dict]:
        """Normalize SSM Parameter Store data (names only, no values)."""
        data = load_json_file(self.raw_dir / "ssm-parameters.json")
        if not data:
            return []

        return [
            {
                "name": param.get("Name"),
                "type": param.get("Type"),
                "tier": param.get("Tier"),
                "last_modified": param.get("LastModifiedDate"),
                "version": param.get("Version")
            }
            for param in data.get("Parameters", [])
        ]

    def _normalize_observability(self) -> Dict:
        """Normalize observability resources."""
        return {
            "log_groups": self._normalize_log_groups(),
            "alarms": self._normalize_alarms(),
            "event_rules": self._normalize_event_rules(),
            "sqs_queues": self._normalize_sqs(),
            "sns_topics": self._normalize_sns()
        }

    def _normalize_log_groups(self) -> List[Dict]:
        """Normalize CloudWatch Log Group data."""
        data = load_json_file(self.raw_dir / "log-groups.json")
        if not data:
            return []

        # Filter to likely app-related log groups
        app_patterns = ["book-vault", "ecs", "lambda", "api-gateway"]

        return [
            {
                "arn": lg.get("arn"),
                "name": lg.get("logGroupName"),
                "retention_days": lg.get("retentionInDays"),
                "stored_bytes": lg.get("storedBytes"),
                "created": lg.get("creationTime")
            }
            for lg in data.get("logGroups", [])
            if any(p in lg.get("logGroupName", "").lower() for p in app_patterns)
               or lg.get("logGroupName", "").startswith("/aws/")
        ]

    def _normalize_alarms(self) -> List[Dict]:
        """Normalize CloudWatch Alarm data."""
        data = load_json_file(self.raw_dir / "alarms.json")
        if not data:
            return []

        return [
            {
                "arn": alarm.get("AlarmArn"),
                "name": alarm.get("AlarmName"),
                "description": alarm.get("AlarmDescription"),
                "state": alarm.get("StateValue"),
                "metric_name": alarm.get("MetricName"),
                "namespace": alarm.get("Namespace"),
                "threshold": alarm.get("Threshold"),
                "comparison": alarm.get("ComparisonOperator")
            }
            for alarm in data.get("MetricAlarms", [])
        ]

    def _normalize_event_rules(self) -> List[Dict]:
        """Normalize EventBridge rule data with targets."""
        data = load_json_file(self.raw_dir / "event-rules.json")
        if not data:
            return []

        rules = []
        for rule in data.get("Rules", []):
            rule_name = rule.get("Name", "")

            # Load targets for this rule
            targets_data = load_json_file(
                self.raw_dir / f"event-targets-{rule_name}.json"
            ) or {}
            targets = [
                {
                    "id": t.get("Id"),
                    "arn": t.get("Arn"),
                    "type": self._infer_target_type(t.get("Arn", "")),
                    "name": t.get("Arn", "").split(":")[-1] if t.get("Arn") else None,
                }
                for t in targets_data.get("Targets", [])
            ]

            rules.append({
                "arn": rule.get("Arn"),
                "name": rule_name,
                "description": rule.get("Description"),
                "state": rule.get("State"),
                "schedule": rule.get("ScheduleExpression"),
                "event_pattern": rule.get("EventPattern"),
                "targets": targets,
            })

        return rules

    def _infer_target_type(self, arn: str) -> str:
        """Infer the target type from its ARN."""
        if ":function:" in arn:
            return "lambda"
        elif ":topic" in arn:
            return "sns"
        elif ":queue" in arn:
            return "sqs"
        elif ":stateMachine:" in arn:
            return "step_functions"
        return "unknown"

    def _normalize_sqs(self) -> List[Dict]:
        """Normalize SQS queue data."""
        data = load_json_file(self.raw_dir / "sqs-queues.json")
        if not data:
            return []

        return [
            {"url": url, "name": url.split("/")[-1]}
            for url in data.get("QueueUrls", [])
        ]

    def _normalize_sns(self) -> List[Dict]:
        """Normalize SNS topic data with subscriptions."""
        data = load_json_file(self.raw_dir / "sns-topics.json")
        if not data:
            return []

        topics = []
        for topic in data.get("Topics", []):
            topic_arn = topic.get("TopicArn", "")
            topic_name = topic_arn.split(":")[-1]

            # Load subscriptions
            subs_data = load_json_file(
                self.raw_dir / f"sns-subscriptions-{topic_name}.json"
            ) or {}
            subscriptions = [
                {
                    "protocol": s.get("Protocol"),
                    "endpoint": s.get("Endpoint", "").split(":")[-1]
                        if s.get("Protocol") == "lambda"
                        else "(redacted)" if s.get("Protocol") == "email"
                        else s.get("Endpoint"),
                }
                for s in subs_data.get("Subscriptions", [])
            ]

            topics.append({
                "arn": topic_arn,
                "name": topic_name,
                "subscriptions": subscriptions,
            })

        return topics

    def _infer_relationships(self) -> Dict:
        """Infer relationships between resources."""
        traffic_flows = []
        security_findings = []

        # ALB -> Target Group -> Compute
        networking = self._normalize_networking()
        for lb in networking.get("load_balancers", []):
            if lb.get("is_internet_facing"):
                traffic_flows.append({
                    "from": "internet",
                    "to": f"alb:{lb.get('name')}",
                    "type": "public_ingress",
                    "ports": [l.get("port") for l in lb.get("listeners", [])]
                })

        # Security findings
        for sg in networking.get("security_groups", []):
            if sg.get("has_wide_open_ingress"):
                for rule in sg.get("ingress_rules", []):
                    if rule.get("source") == "0.0.0.0/0":
                        security_findings.append({
                            "type": "wide_open_sg",
                            "severity": "medium" if rule.get("from_port") in [80, 443] else "high",
                            "resource": f"sg:{sg.get('id')}",
                            "name": sg.get("name"),
                            "detail": f"Allows {rule.get('protocol')} port {rule.get('from_port')} from 0.0.0.0/0"
                        })

        # Public subnets
        for subnet in networking.get("subnets", []):
            if subnet.get("is_public"):
                traffic_flows.append({
                    "type": "public_subnet",
                    "resource": f"subnet:{subnet.get('id')}",
                    "name": subnet.get("name"),
                    "vpc_id": subnet.get("vpc_id")
                })

        return {
            "traffic_flows": traffic_flows,
            "security_findings": security_findings
        }

    def _collect_gaps(self) -> Dict:
        """Collect any permission errors or missing resources."""
        gaps_file = self.raw_dir.parent / "gaps.json"
        if gaps_file.exists():
            with open(gaps_file) as f:
                return {"permission_errors": json.load(f), "missing_resources": []}
        return {"permission_errors": [], "missing_resources": []}


def main():
    parser = argparse.ArgumentParser(description="Normalize AWS audit data")
    parser.add_argument("--raw-dir", required=True, help="Directory with raw AWS JSON files")
    parser.add_argument("--output", required=True, help="Output path for summary.json")
    parser.add_argument("--account-id", required=True, help="AWS Account ID")
    parser.add_argument("--region", required=True, help="AWS Region")
    parser.add_argument("--generated-at", required=True, help="Timestamp")
    parser.add_argument("--version", required=True, help="Audit version")

    args = parser.parse_args()

    normalizer = AWSNormalizer(
        raw_dir=Path(args.raw_dir),
        account_id=args.account_id,
        region=args.region,
        generated_at=args.generated_at,
        version=args.version
    )

    summary = normalizer.normalize()

    # Write output
    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    with open(output_path, "w") as f:
        json.dump(summary, f, indent=2, default=str)

    print(f"Wrote normalized data to {output_path}")


if __name__ == "__main__":
    main()
