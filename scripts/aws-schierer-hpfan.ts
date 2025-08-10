#!/usr/bin/env node
import * as cdk from "aws-cdk-lib";
import { MojoliciousStack } from "../infrastructure/lib/aws-schierer-hpfan-stack.ts";
type EnvConfig = {
  CidrRange: string;
  subdomain: string;
  desiredCount: number;
  cpu: number;
  memory: number;
  imageTag: string;
};

const app = new cdk.App();

const envConfigs: Record<string, EnvConfig> = {
  dev: {
    CidrRange: "10.233.0.0/24",
    subdomain: "dev",
    desiredCount: 1,
    cpu: 1024,
    memory: 4096,
    imageTag: "latest",
  },
  prod: {
    CidrRange: "10.239.0.0/24",
    subdomain: "www",
    desiredCount: 2,
    cpu: 2048,
    memory: 5120,
    imageTag: "stable",
  },
};

const environment: "dev" | "prod" =
  (app.node.tryGetContext("env") as string).toLowerCase() === "prod"
    ? "prod"
    : "dev";
const config = envConfigs[environment];
const hostedZoneId = "ZOB4NXMJR2BZF"; // Your Route53 hosted zone ID
const zoneName = "schierer.org";

new MojoliciousStack(app, `Hpfan-${environment}`, {
  environment: environment,
  appName: "HPFan",
  CidrRange: config.CidrRange,
  domainName: "hp-fan.schierer.org", // Your Route53 domain
  appSubdomain: config.subdomain,
  hostedZoneId: hostedZoneId, // Your Route53 hosted zone ID
  zoneName: zoneName,
  containerPort: 3000, // Port your Mojolicious app listens on
  cpu: config.cpu,
  memory: config.memory,
  desiredCount: config.desiredCount,
  ecrRepositoryName: "hpfan", // ECR repository name
  imageTag: config.imageTag,
  env: {
    account: "699040795025",
    region: "us-east-2",
  },
  crossRegionReferences: true,
  tags: {
    Environment: environment,
    Application: "HPFan",
  },
});
