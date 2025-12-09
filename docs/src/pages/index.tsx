import type { ReactNode } from "react";
import clsx from "clsx";
import Link from "@docusaurus/Link";
import useDocusaurusContext from "@docusaurus/useDocusaurusContext";
import Layout from "@theme/Layout";
import Heading from "@theme/Heading";

import styles from "./index.module.css";

function HomepageHeader() {
  const { siteConfig } = useDocusaurusContext();
  return (
    <header className={clsx("hero hero--primary", styles.heroBanner)}>
      <div className="container">
        <Heading as="h1" className="hero__title">
          {siteConfig.title}
        </Heading>
        <p className="hero__subtitle">{siteConfig.tagline}</p>
        <div className={styles.buttons}>
          <Link
            className="button button--secondary button--lg"
            to="/docs/intro"
          >
            시작하기 →
          </Link>
        </div>
      </div>
    </header>
  );
}

function HomepageFeatures() {
  return (
    <section className={styles.features}>
      <div className="container">
        <div className="row">
          <div className="col col--4">
            <div className="text--center padding-horiz--md">
              <h3>🎯 Kubernetes 기초</h3>
              <p>
                Deployment, Service, ConfigMap, Secret 등 Kubernetes의 핵심
                개념과 Blue-Green, Canary 배포 전략을 실습합니다.
              </p>
            </div>
          </div>
          <div className="col col--4">
            <div className="text--center padding-horiz--md">
              <h3>🚀 고급 기능</h3>
              <p>
                스토리지, 네트워킹, Ingress, Probes, Jobs 등 프로덕션 환경에
                필요한 고급 기능을 다룹니다.
              </p>
            </div>
          </div>
          <div className="col col--4">
            <div className="text--center padding-horiz--md">
              <h3>🔧 Service Mesh</h3>
              <p>
                Istio를 활용한 트래픽 관리, 복원력 패턴, 보안, 관찰성을 실제
                예제로 학습합니다.
              </p>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}

export default function Home(): ReactNode {
  const { siteConfig } = useDocusaurusContext();
  return (
    <Layout
      title={`환영합니다`}
      description="Azure Kubernetes Service 워크샵 - Kubernetes 기초부터 Istio Service Mesh까지"
    >
      <HomepageHeader />
      <main>
        <HomepageFeatures />
      </main>
    </Layout>
  );
}
