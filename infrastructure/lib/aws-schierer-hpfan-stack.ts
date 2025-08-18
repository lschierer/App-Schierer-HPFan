import { Stack, type StackProps, Duration, CfnOutput, Tags } from "aws-cdk-lib";
import { type Construct } from "constructs";
import * as ec2 from "aws-cdk-lib/aws-ec2";
import * as ecs from "aws-cdk-lib/aws-ecs";
import * as ecr from "aws-cdk-lib/aws-ecr";
import * as elbv2 from "aws-cdk-lib/aws-elasticloadbalancingv2";
import * as route53 from "aws-cdk-lib/aws-route53";
import * as targets from "aws-cdk-lib/aws-route53-targets";
import * as acm from "aws-cdk-lib/aws-certificatemanager";
import * as logs from "aws-cdk-lib/aws-logs";
import * as s3 from "aws-cdk-lib/aws-s3";
import * as cdk from "aws-cdk-lib";
import * as iam from "aws-cdk-lib/aws-iam";

interface MojoliciousStackProps extends StackProps {
  environment: "dev" | "prod";
  appName: string; // e.g., 'HPFan'
  CidrRange: string;
  domainName: string; // e.g., example.com
  appSubdomain: string; // e.g., app (-> app.example.com)
  hostedZoneId: string;
  zoneName: string; // (unused in your code, but keeping)
  containerPort: number;
  cpu: number;
  memory: number;
  desiredCount: number;
  ecrRepositoryName: string;
  imageTag: string;
}

export class MojoliciousStack extends Stack {
  constructor(scope: Construct, id: string, props: MojoliciousStackProps) {
    super(scope, id, props);

    // ---------- naming helpers ----------
    const app = props.appName;
    const env = props.environment;
    const base = `${app}-${env}`; // e.g., "HPFan-dev"

    const sanitize = (s: string) =>
      s.replace(/[^A-Za-z0-9-]/g, "-").replace(/-+/g, "-");

    const name = (suffix: string, max?: number) => {
      const n = sanitize(`${base}-${suffix}`);
      return max ? n.slice(0, max) : n;
    };

    const bucketName = (() => {
      // S3 bucket rules: lowercase, 3–63 chars, start/end with letter/number, no consecutive dots
      const raw = `${app}-${env}-logs-${this.account}-${this.region}`
        .toLowerCase()
        .replace(/[^a-z0-9.-]/g, "-")
        .replace(/-+/g, "-")
        .replace(/\.+/g, ".");
      let b = raw;
      b = b.replace(/^[^a-z0-9]+/, "");
      b = b.replace(/[^a-z0-9]+$/, "");
      if (b.length < 3) b = `${b}xxx`;
      if (b.length > 63) b = b.slice(0, 63);
      return b;
    })();

    // helpful tags on everything in this stack
    Tags.of(this).add("App", app);
    Tags.of(this).add("Environment", env);

    // Full domain name for the application
    const fullDomainName = `${props.appSubdomain}.${props.domainName}`;

    // ---------- S3 Log Bucket ----------
    const logbucket = new s3.Bucket(
      this,
      `${props.appName}-${props.environment}-LogBucket`,
      {
        bucketName, // identifiable & unique per account/region
        encryption: s3.BucketEncryption.KMS_MANAGED,
        blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
        objectOwnership: s3.ObjectOwnership.BUCKET_OWNER_ENFORCED,
        removalPolicy: cdk.RemovalPolicy.DESTROY,
        autoDeleteObjects: true,
        enforceSSL: true,
        intelligentTieringConfigurations: [
          {
            name: "logs",
            prefix: "", // track all objects
            archiveAccessTierTime: Duration.days(90),
            deepArchiveAccessTierTime: Duration.days(180),
          },
        ],
      },
    );

    // ---------- IAM ----------
    const syncTaskRole = new iam.Role(
      this,
      `${props.appName}-${props.environment}-LogSyncTaskRole`,
      {
        roleName: name("ecs-taskrole"),
        assumedBy: new iam.ServicePrincipal("ecs-tasks.amazonaws.com"),
      },
    );

    logbucket.grantWrite(syncTaskRole);

    // ---------- Route53 / ACM ----------
    const hostedZone = route53.HostedZone.fromHostedZoneAttributes(
      this,
      "HostedZone",
      {
        hostedZoneId: props.hostedZoneId,
        zoneName: props.domainName,
      },
    );

    const certificate = new acm.Certificate(
      this,
      `${props.appName}-${props.environment}-UnifiedCert`,
      {
        certificateName: name("cert", 256), // visible in console
        domainName: fullDomainName,
        // If you need SANs, add full domain strings here (".net" is not valid)
        subjectAlternativeNames:
          props.environment === "prod" ? [`${props.domainName}`] : [],
        validation: acm.CertificateValidation.fromDns(hostedZone),
      },
    );

    // ---------- VPC ----------
    const vpc = new ec2.Vpc(this, `${props.appName}-${props.environment}-Vpc`, {
      ipAddresses: ec2.IpAddresses.cidr(props.CidrRange),
      maxAzs: 2,
      natGateways: 0,
      subnetConfiguration: [
        {
          name: "public",
          subnetType: ec2.SubnetType.PUBLIC,
          cidrMask: 28,
        },
      ],
    });
    // Tag 'Name' so it shows as a named VPC in console
    Tags.of(vpc).add("Name", name("vpc"));

    // ---------- ECS ----------
    const cluster = new ecs.Cluster(
      this,
      `${props.appName}-${props.environment}-Cluster`,
      {
        vpc,
        clusterName: name("cluster"),
        containerInsights: true,
      },
    );

    const repository = ecr.Repository.fromRepositoryName(
      this,
      "Repository",
      props.ecrRepositoryName,
    );

    // dedicated log groups (so names are readable)
    const appLogGroup = new logs.LogGroup(
      this,
      `${props.appName}-${props.environment}-AppLogGroup`,
      {
        logGroupName: `/aws/ecs/${sanitize(base)}`,
        retention: logs.RetentionDays.ONE_WEEK,
        removalPolicy: cdk.RemovalPolicy.DESTROY,
      },
    );
    const shipperLogGroup = new logs.LogGroup(
      this,
      `${props.appName}-${props.environment}-ShipperLogGroup`,
      {
        logGroupName: `/aws/ecs/${sanitize(base)}-shipper`,
        retention: logs.RetentionDays.ONE_WEEK,
        removalPolicy: cdk.RemovalPolicy.DESTROY,
      },
    );

    const taskDefinition = new ecs.FargateTaskDefinition(
      this,
      `${props.appName}-${props.environment}-TaskDef`,
      {
        family: name("task"),
        cpu: props.cpu,
        memoryLimitMiB: props.memory,
        runtimePlatform: {
          cpuArchitecture: ecs.CpuArchitecture.ARM64,
          operatingSystemFamily: ecs.OperatingSystemFamily.LINUX,
        },
        taskRole: syncTaskRole,
      },
    );

    // Fargate volumes: do NOT set `host` (that's for EC2 tasks)
    taskDefinition.addVolume({
      name: `${props.appName}-${props.environment}-perl-logs`,
    });

    const appContainer = taskDefinition.addContainer(
      `${props.appName}-${props.environment}-Container`,
      {
        containerName: name("app", 255),
        image: ecs.ContainerImage.fromEcrRepository(repository, props.imageTag),
        logging: ecs.LogDrivers.awsLogs({
          logGroup: appLogGroup,
          streamPrefix: "app",
        }),
        environment: {
          MOJO_MODE: "production",
          MOJO_LISTEN: `http://0.0.0.0:${props.containerPort}`,
          HOME: "/home/mojo",
          IMAGE_TAG: props.imageTag,
          IMAGE_URI: `${repository.repositoryUri}:${props.imageTag}`,
          DEPLOYMENT_TIME: new Date().toISOString(),
        },
        healthCheck: {
          command: [
            "CMD-SHELL",
            `curl -f http://localhost:${props.containerPort}/health || exit 1`,
          ],
          interval: Duration.seconds(30),
          timeout: Duration.seconds(5),
          retries: 3,
          startPeriod: Duration.seconds(10),
        },
      },
    );

    appContainer.addPortMappings({
      containerPort: props.containerPort,
      protocol: ecs.Protocol.TCP,
    });

    appContainer.addMountPoints({
      containerPath: "/home/mojo/var/log/Perl/dist/App-Schierer-HPFan",
      sourceVolume: `${props.appName}-${props.environment}-perl-logs`,
      readOnly: false,
    });

    // ---------- Security Groups ----------
    const albSG = new ec2.SecurityGroup(
      this,
      `${props.appName}-${props.environment}-AlbSG`,
      {
        vpc,
        description: "ALB SG",
        allowAllOutbound: true,
        securityGroupName: name("alb-sg"),
      },
    );
    albSG.addIngressRule(ec2.Peer.anyIpv4(), ec2.Port.tcp(443));
    albSG.addIngressRule(ec2.Peer.anyIpv4(), ec2.Port.tcp(80));

    const serviceSG = new ec2.SecurityGroup(
      this,
      `${props.appName}-${props.environment}-ServiceSG`,
      {
        vpc,
        description: "Fargate service SG",
        allowAllOutbound: true,
        securityGroupName: name("service-sg"),
      },
    );
    serviceSG.addIngressRule(albSG, ec2.Port.tcp(props.containerPort));

    // ---------- Fargate Service ----------
    const service = new ecs.FargateService(
      this,
      `${props.appName}-${props.environment}-Service`,
      {
        serviceName: name("service"),
        cluster,
        taskDefinition,
        desiredCount: props.desiredCount,
        enableExecuteCommand: true,
        assignPublicIp: true,
        securityGroups: [serviceSG], // SG for tasks (ALB uses albSG)
      },
    );

    // ---------- ALB ----------
    const lb = new elbv2.ApplicationLoadBalancer(
      this,
      `${props.appName}-${props.environment}-ALB`,
      {
        loadBalancerName: name("alb", 32), // ALB name limit 32
        vpc,
        internetFacing: true,
        securityGroup: albSG,
      },
    );

    const httpsListener = lb.addListener("HttpsListener", {
      port: 443,
      certificates: [certificate],
      protocol: elbv2.ApplicationProtocol.HTTPS,
      open: true,
    });

    httpsListener.addTargets(`${props.appName}-${props.environment}-Targets`, {
      port: props.containerPort,
      protocol: elbv2.ApplicationProtocol.HTTP,
      targets: [service],
      targetGroupName: name("tg", 32), // TG name limit 32
      healthCheck: {
        path: "/health",
        interval: Duration.seconds(30),
        timeout: Duration.seconds(5),
        healthyThresholdCount: 2,
        unhealthyThresholdCount: 3,
      },
    });

    const httpListener = lb.addListener(
      `${props.appName}-${props.environment}-HttpListener`,
      {
        port: 80,
        protocol: elbv2.ApplicationProtocol.HTTP,
        open: true,
      },
    );

    httpListener.addAction(
      `${props.appName}-${props.environment}-HttpRedirect`,
      {
        action: elbv2.ListenerAction.redirect({
          port: "443",
          protocol: elbv2.ApplicationProtocol.HTTPS,
          permanent: true,
        }),
      },
    );

    // ---------- Route53 ----------
    if (props.environment === "prod") {
      new route53.ARecord(
        this,
        `${props.appName}-${props.environment}-RootDomainRecord`,
        {
          zone: hostedZone,
          recordName: "", // root domain
          target: route53.RecordTarget.fromAlias(
            new targets.LoadBalancerTarget(lb),
          ),
          ttl: Duration.minutes(5),
        },
      );
    }

    new route53.ARecord(
      this,
      `${props.appName}-${props.environment}-DNSRecord`,
      {
        zone: hostedZone,
        recordName: props.appSubdomain, // e.g., app.example.com
        target: route53.RecordTarget.fromAlias(
          new targets.LoadBalancerTarget(lb),
        ),
        ttl: Duration.minutes(5),
      },
    );

    // ---------- Sidecar: Fluent Bit -> S3 ----------
    const logShipperContainer = taskDefinition.addContainer(
      `${props.appName}-${props.environment}-LogShipperContainer`,
      {
        containerName: name("shipper"),
        image: ecs.ContainerImage.fromRegistry(
          "amazon/aws-for-fluent-bit:stable",
        ),
        essential: false,
        cpu: 128,
        memoryReservationMiB: 128,
        logging: ecs.LogDrivers.awsLogs({
          logGroup: shipperLogGroup,
          streamPrefix: "shipper",
        }),
        environment: {
          AWS_REGION: this.region,
          S3_BUCKET: logbucket.bucketName,
          ECS_ENABLE_CONTAINER_METADATA: "true",
        },
        command: [
          "/fluent-bit/bin/fluent-bit",

          // Input: tail app files
          "-i",
          "tail",
          "-p",
          "path=/var/log/app/*.log",
          "-p",
          "tag=app",
          "-p",
          "path_key=filename",
          "-p",
          "read_from_head=true",
          "-p",
          "skip_long_lines=false",
          "-p",
          "refresh_interval=5",
          "-p",
          "rotate_wait=30",
          "-p",
          "mem_buf_limit=64MB",

          // Enable chunk persistence across restarts (optional, but helps)
          "-p",
          "storage.type=filesystem",

          // Output: S3
          "-o",
          "s3",
          "-p",
          "match=app",
          "-p",
          "bucket=${S3_BUCKET}",
          "-p",
          `region=${this.region}`,

          // Larger, fewer uploads -> fewer PUTs
          "-p",
          "total_file_size=200M", // buffer before upload (tune)
          "-p",
          "upload_timeout=30m", // or time-based flush

          // Clean, unique object keys
          "-p",
          "s3_key_format=logs/%Y/%m/%d/${filename}-${HOSTNAME}.log",

          // Cheaper storage size
          "-p",
          "compression=gzip",

          // Compatibility: direct PUT per object (works well; multipart also ok)
          "-p",
          "use_put_object=On",

          // Optional: add metadata to S3 object
          // "-p", "s3_object_tagging=environment=${ENVIRONMENT},app=${APP}",

          "-v",
        ],
      },
    );

    logShipperContainer.addMountPoints({
      containerPath: "/var/log/app",
      sourceVolume: `${props.appName}-${props.environment}-perl-logs`,
      readOnly: true,
    });

    // ---------- Outputs ----------
    new CfnOutput(this, "LoadBalancerDNS", {
      value: lb.loadBalancerDnsName,
      description: "Load Balancer DNS Name",
    });

    new CfnOutput(this, "ApplicationURL", {
      value: `https://${fullDomainName}`,
      description: "Application URL",
    });
  }
}
