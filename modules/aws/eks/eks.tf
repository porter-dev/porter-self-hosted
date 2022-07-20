resource "random_string" "suffix" {
  length  = 8
  special = false
}

resource "aws_security_group" "worker_group_mgmt_one" {
  name_prefix = "worker_group_mgmt_one"
  vpc_id      = var.vpc_id

  ingress {
    from_port = 22
    to_port   = 22
    protocol  = "tcp"

    cidr_blocks = [
      "10.99.0.0/16",
    ]
  }
}

resource "aws_security_group" "worker_group_mgmt_two" {
  name_prefix = "worker_group_mgmt_two"
  vpc_id      = var.vpc_id

  ingress {
    from_port = 22
    to_port   = 22
    protocol  = "tcp"

    cidr_blocks = [
      "192.168.0.0/16",
    ]
  }
}

resource "aws_security_group" "all_worker_mgmt" {
  name_prefix = "all_worker_management"
  vpc_id      = var.vpc_id

  # TODO: support additional node groups
  ingress {
    from_port = 22
    to_port   = 22
    protocol  = "tcp"

    cidr_blocks = [
      "10.99.0.0/16",
      "172.16.0.0/12",
      "192.168.0.0/16",
    ]
  }
}

module "eks" {
  depends_on = [
    aws_security_group.worker_group_mgmt_one,
    aws_security_group.worker_group_mgmt_two,
    aws_security_group.all_worker_mgmt,
  ]

  source          = "terraform-aws-modules/eks/aws"
  version         = "17.22.0"
  cluster_name    = var.env_name
  cluster_version = var.cluster_version
  subnets         = var.private_subnets

  manage_aws_auth = var.manage_aws_auth_configmap

  map_roles = [
    for arn, group in var.aws_auth_roles : {
      rolearn  = arn
      username = split("/", arn)[1]
      groups   = [group]
    }
  ]

  map_users = [
    for arn, group in var.aws_auth_users : {
      userarn  = arn
      username = split("/", arn)[1]
      groups   = [group]
    }
  ]

  enable_irsa = true

  vpc_id = var.vpc_id

  worker_groups_launch_template = concat([{
    name                                    = "worker-group-1"
    instance_type                           = var.system_machine_type
    additional_userdata                     = "echo foo bar"
    asg_desired_capacity                    = 2
    instance_refresh_enabled                = true
    update_default_version                  = true
    instance_refresh_min_healthy_percentage = 90
    instance_refresh_instance_warmup        = 300
    additional_security_group_ids           = [aws_security_group.worker_group_mgmt_one.id]

    kubelet_extra_args = join(" ", [
      "--node-labels porter.run/workload-kind=system",
      "--register-with-taints porter.run/workload-kind=system:NoSchedule",
      "--cluster-dns 169.254.20.10",
      "--cluster-dns 172.20.0.10"
    ])
    },
    {
      name          = "worker-group-2"
      instance_type = var.machine_type

      override_instance_types = var.spot_instances_enabled ? [var.machine_type] : []
      spot_instance_pools     = var.spot_instances_enabled ? 1 : 0
      spot_price              = var.spot_instances_enabled ? var.spot_price : ""

      additional_userdata                     = "echo foo bar"
      additional_security_group_ids           = [aws_security_group.worker_group_mgmt_two.id]
      asg_desired_capacity                    = var.min_instances
      asg_max_size                            = var.max_instances
      asg_min_size                            = var.min_instances
      instance_refresh_enabled                = true
      update_default_version                  = true
      instance_refresh_min_healthy_percentage = 90
      instance_refresh_instance_warmup        = 300

      tags = [
        {
          "key"                 = "k8s.io/cluster-autoscaler/enabled"
          "propagate_at_launch" = "false"
          "value"               = "true"
        },
        {
          "key"                 = "k8s.io/cluster-autoscaler/${var.env_name}"
          "propagate_at_launch" = "false"
          "value"               = "true"
        }
      ]

      kubelet_extra_args = join(" ", var.spot_instances_enabled ? [
        "--node-labels porter.run/workload-kind=application,node.kubernetes.io/lifecycle=spot",
        "--cluster-dns 169.254.20.10",
        "--cluster-dns 172.20.0.10",
        ] : [
        "--node-labels porter.run/workload-kind=application",
        "--cluster-dns 169.254.20.10",
        "--cluster-dns 172.20.0.10",
      ])
    },
    ], var.additional_nodegroup_enabled ? [{
      name          = "worker-group-3"
      instance_type = var.additional_nodegroup_machine_type

      additional_userdata                     = "echo foo bar"
      additional_security_group_ids           = [aws_security_group.worker_group_mgmt_two.id]
      subnets                                 = var.additional_stateful_nodegroup_enabled ? [var.private_subnets[0]] : var.private_subnets
      asg_desired_capacity                    = var.additional_nodegroup_min_instances
      asg_max_size                            = var.additional_nodegroup_max_instances
      asg_min_size                            = var.additional_nodegroup_min_instances
      instance_refresh_enabled                = true
      update_default_version                  = true
      instance_refresh_min_healthy_percentage = 90
      instance_refresh_instance_warmup        = 300

      tags = [
        {
          "key"                 = "k8s.io/cluster-autoscaler/enabled"
          "propagate_at_launch" = "false"
          "value"               = "true"
        },
        {
          "key"                 = "k8s.io/cluster-autoscaler/${var.env_name}"
          "propagate_at_launch" = "false"
          "value"               = "true"
        }
      ]

      kubelet_extra_args = join(" ", [
        "--node-labels ${var.additional_nodegroup_label}",
        "--register-with-taints ${var.additional_nodegroup_taint}",
        "--cluster-dns 169.254.20.10",
        "--cluster-dns 172.20.0.10",
      ])
  }] : [])

  workers_group_defaults = {
    root_volume_type = "gp2"
  }

  workers_additional_policies = [
    aws_iam_policy.worker_policy.arn,
    aws_iam_policy.worker_autoscaling.arn
  ]
}

data "aws_eks_cluster" "cluster" {
  name = module.eks.cluster_id
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_id
}

resource "aws_iam_policy" "worker_policy" {
  name        = "${var.env_name}-${random_string.suffix.result}"
  description = "Worker policy for the ALB Ingress"

  policy = file("${path.module}/iam-policy.json")
}

resource "aws_iam_policy" "worker_autoscaling" {
  name_prefix = "eks-worker-autoscaling-${module.eks.cluster_id}"
  description = "EKS worker node autoscaling policy for cluster ${module.eks.cluster_id}"

  policy = data.aws_iam_policy_document.worker_autoscaling.json
}

data "aws_iam_policy_document" "worker_autoscaling" {
  statement {
    sid    = "eksWorkerAutoscalingAll"
    effect = "Allow"

    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeAutoScalingInstances",
      "autoscaling:DescribeLaunchConfigurations",
      "autoscaling:DescribeTags",
      "ec2:DescribeLaunchTemplateVersions",
    ]

    resources = ["*"]
  }

  statement {
    sid    = "eksWorkerAutoscalingOwn"
    effect = "Allow"

    actions = [
      "autoscaling:SetDesiredCapacity",
      "autoscaling:TerminateInstanceInAutoScalingGroup",
      "autoscaling:UpdateAutoScalingGroup",
    ]

    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "autoscaling:ResourceTag/kubernetes.io/cluster/${module.eks.cluster_id}"
      values   = ["owned"]
    }

    condition {
      test     = "StringEquals"
      variable = "autoscaling:ResourceTag/k8s.io/cluster-autoscaler/enabled"
      values   = ["true"]
    }
  }
}

resource "helm_release" "ingress" {
  # EKS and IAM policy are pre-requisites
  depends_on = [module.eks, aws_iam_policy.worker_policy]
  name       = "ingress-controller"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  repository = "https://aws.github.io/eks-charts"
  version    = "v1.4.1"

  set {
    name  = "region"
    value = var.aws_region
  }

  set {
    name  = "vpcId"
    value = var.vpc_id
  }

  set {
    name  = "clusterName"
    value = var.env_name
  }

  values = [
    <<VALUES
nodeSelector:
  porter.run/workload-kind: "system"
tolerations:
- key: "porter.run/workload-kind"
  operator: "Equal"
  value: "system"
  effect: "NoSchedule"
image:
  repository: 602401143452.dkr.ecr.${var.aws_region}.amazonaws.com/amazon/aws-load-balancer-controller
VALUES
  ]
}
