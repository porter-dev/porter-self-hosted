resource "local_file" "kube_config" {
  filename = pathexpand("${path.module}/config")
  content  = <<-CONFIG
    apiVersion: v1
    kind: Config
    clusters:
    - name: clustername
      cluster:
        server: ${data.aws_eks_cluster.cluster.endpoint}
        certificate-authority-data: ${data.aws_eks_cluster.cluster.certificate_authority.0.data}
    contexts:
    - name: contextname
      context:
        cluster: clustername
        user: username
    current-context: contextname
    users:
    - name: username
      user:
        token: ${data.aws_eks_cluster_auth.cluster.token}
  CONFIG
}

resource "null_resource" "patch_storageclass" {
  depends_on = [
    module.eks,
    aws_iam_policy.worker_policy,
  ]

  // re-run when patch file changes
  triggers = {
    issuer_sha1 = "${sha1(file("${path.module}/storageclass-expansion-patch.yaml"))}"
  }

  provisioner "local-exec" {
    command = <<CREATE
kubectl patch storageclass gp2 --kubeconfig ${path.module}/config --type merge --patch "$(cat ${path.module}/storageclass-expansion-patch.yaml)"
    CREATE
  }
}
