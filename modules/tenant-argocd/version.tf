# ─── Versionamento do Estado da Infraestrutura ───────────────
# Adiciona metadata de versão nos recursos do ArgoCD
# Permite rastrear qual tag do repositório criou cada recurso

locals {
  # A versão é passada via variável de ambiente no CI/CD
  # Ex: TF_VAR_infra_version=v1.2.3
  # Se não existir, usa "dev" (desenvolvimento local)
  infra_version = try(var.infra_version, "dev")
}
