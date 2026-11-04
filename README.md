# Naija Votes: election simulator for learning DevOps

A fake election. Simulated voters post votes, results update live in the browser.
**Simulation only. Never use it for a real vote.**

## Architecture
```
Browser ─▶ web (nginx + React) ─▶ api x2 (Express) ─▶ db (Postgres: votes, tallies)
                                      ▲   │
simulator (fake voters) ──POST /vote──┘   └─▶ redis pub/sub ─▶ every api replica ─▶ SSE push to browsers
```
## Run it
```
docker compose up --build         # open http://localhost:8080
docker compose up -d --scale api=4   # horizontal scaling
docker compose logs -f api
docker compose exec db psql -U naija votes -c "select party,sum(count) from tallies group by 1"
```
Local dev of the UI: `cd frontend && npm i && npm run dev`.

## DevOps exercises (in order)
1. **Containers**: read each Dockerfile. Why is `package.json` copied before the source? (layer caching)
2. **Compose**: kill `db` and watch `api` retry. Remove the volume and watch data vanish.
3. **Scaling**: scale `api` to 4; check `/health` returns different `instance` values.
4. **CI**: push to GitHub; the Actions workflow builds and smoke-tests. Add a failing test and watch it block.
5. **Observability**: add `prom-client` to the API (`/metrics`), then Prometheus + Grafana to compose.
6. **Kubernetes**: write manifests (Deployment, Service, Ingress, StatefulSet for Postgres) or a Helm chart; use `kind` locally.
7. **IaC and CD**: Terraform a VM or managed cluster; push images to GHCR and auto-deploy on `main`.
8. **Reliability**: rate-limit votes, add Postgres backups, chaos test (`docker kill`), define an SLO for result latency.
9. **Security**: move secrets from compose to env files or a vault, run `trivy` on the images.

## Deploy to AWS (ECS Fargate), see `terraform/`
Network (3 tiers, 2 AZs) + security groups + RDS Postgres + ElastiCache Redis + ECS Fargate behind an ALB.
```
cd terraform && terraform init
terraform apply -target=module.compute.aws_ecr_repository.repo     # 1. create image registries first
# 2. build and push (replace ACCOUNT/REGION; add --platform linux/amd64 on Apple Silicon)
aws ecr get-login-password | docker login --username AWS --password-stdin ACCOUNT.dkr.ecr.REGION.amazonaws.com
docker build -t ACCOUNT.dkr.ecr.REGION.amazonaws.com/naija-vote/api:latest ../backend
docker build -t ACCOUNT.dkr.ecr.REGION.amazonaws.com/naija-vote/web:latest --build-arg NGINX_CONF=nginx.ecs.conf ../frontend
docker build -t ACCOUNT.dkr.ecr.REGION.amazonaws.com/naija-vote/simulator:latest ../simulator
docker push ... (each image)
terraform apply                                                     # 3. everything else, then open app_url
terraform destroy                                                   # 4. ALWAYS destroy after practice (NAT, RDS, ALB cost money)
```

## Continuous deployment (GitHub Actions + OIDC)
No AWS keys are stored in GitHub. Terraform creates a role that only your repo's `main` branch can assume.
1. `terraform apply -var github_repo=YOUR_USER/naija-vote`
2. In GitHub: Settings > Secrets and variables > Actions > **Variables**, add
   `AWS_DEPLOY_ROLE_ARN` (output `deploy_role_arn`) and `APP_URL` (output `app_url`).
3. Push to `main`. The workflow runs CI, builds images (tagged with the commit SHA only), registers a new task-definition
   revision per service, redeploys, waits until stable, then smoke-tests the live site.
4. Safety nets: ECS circuit breaker auto-rolls back a failing deploy; add branch protection so CI must pass before merging.
**Rollback:** re-run the workflow on an older commit (images are immutable, so that exact build is redeployed), or point a service at an earlier task-definition revision with `aws ecs update-service --task-definition`.
**First deploy:** Terraform creates services pointing at a placeholder `bootstrap` image, so tasks fail until the first pipeline run pushes real images. That is expected.

## Observability and autoscaling
`terraform apply -var github_repo=... -var alert_email=you@example.com` (click the confirmation link AWS emails you).
- **Dashboard** (output `dashboard_url`): traffic and errors, API p95 latency, CPU/memory, running tasks, Postgres, Redis.
- **8 alarms to email**: 5xx errors, unhealthy API task, slow p95, no API tasks, Postgres CPU and free storage, Redis CPU and memory.
- **Autoscaling**: API tasks scale between `api_count` (min) and `api_max` on 60% average CPU.
- Try it: run the simulator at `VOTES_PER_SEC=200` and watch the dashboard and the task count.
