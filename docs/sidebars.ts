import type { SidebarsConfig } from "@docusaurus/plugin-content-docs";

const sidebars: SidebarsConfig = {
  tutorialSidebar: [
    "intro",
    {
      type: "category",
      label: "환경 설정",
      items: ["setup/prerequisites", "setup/cluster-setup"],
    },
    {
      type: "category",
      label: "Kubernetes 기초",
      items: [
        "kubernetes-basics/intro",
        "kubernetes-basics/basic-deployments",
        "kubernetes-basics/services",
        "kubernetes-basics/configmaps",
        "kubernetes-basics/secrets",
        "kubernetes-basics/blue-green-deployments",
        "kubernetes-basics/canary-deployments",
      ],
    },
    {
      type: "category",
      label: "고급 Kubernetes",
      items: [
        "advanced-kubernetes/intro",
        "advanced-kubernetes/volumes",
        "advanced-kubernetes/advanced-volumes",
        "advanced-kubernetes/ingress",
        "advanced-kubernetes/probes",
        "advanced-kubernetes/init-containers",
        "advanced-kubernetes/multi-container-pods",
        "advanced-kubernetes/jobs",
      ],
    },
    {
      type: "category",
      label: "Pod 스케줄링",
      items: [
        "scheduling/intro",
        "scheduling/affinity-volume",
        "scheduling/anti-affinity-stateful-set",
        "scheduling/taint-tolerations",
        "scheduling/topology-spread",
      ],
    },
    {
      type: "category",
      label: "오토스케일링",
      items: [
        "autoscaling/intro",
        "autoscaling/resources",
        "autoscaling/hpa",
        "autoscaling/keda-rabbitmq",
        "autoscaling/keda-cron",
      ],
    },
    {
      type: "category",
      label: "모니터링",
      items: ["monitoring/overview"],
    },
    {
      type: "category",
      label: "Istio",
      items: [
        "istio/intro",
        "setup/bookinfo",
        "istio/request-routing",
        "istio/traffic-shifting",
        "istio/fault-injection",
        "istio/circuit-breaking",
        "istio/authorization",
        "advanced/tips",
      ],
    },
    "cleanup",
  ],
};

export default sidebars;
