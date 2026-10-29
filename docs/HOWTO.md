# HOWTO: build and ship snake-game end to end (about 2 hours)

A small Snake game website with a leaderboard. The game is simple on purpose. The marks come from the
DevOps tooling around it. Written for **Ubuntu 22.04 LTS** (native, or WSL2 Ubuntu 22.04 on Windows; on
WSL keep the project in `~`, not under `/mnt/c`). Every command runs in the Ubuntu terminal.

## 0. Rubric map

| Rubric criterion | Where it is covered | Proof to capture |
|---|---|---|
| DevOps ecosystem, version control, collaboration | `main`/`dev`/`feature/*` branches, PR template, deliberate merge conflict | PR page, conflict + resolution, branch graph |
| CI/CD pipeline automation | `.github/workflows/ci-cd.yml`: flake8, pytest, CodeQL, Terraform validate, Trivy (image + config), artifact, GHCR push, multi-stage deploy | Green run with job graph, artifacts list |
| Containerization and orchestration | Multi-stage non-root `Dockerfile`, GHCR registry, K8s Deployment/Service/HPA, scaling, rolling update, rollback | `docker images`, `kubectl get all`, `rollout status` |
| IaC, cloud deployment, monitoring | Terraform on AWS (EC2, security group, generated secrets), Prometheus + Grafana + alert rules, security scanning | `terraform apply`, Grafana, firing alert |
| Documentation and presentation | `README.md`, this guide, report and slides made from your screenshots | Report PDF, slides |

Outside the build: **Online certification (10 marks)** needs 100% of Coursera "Introduction to DevOps"
with certificate. Start it in parallel.

## 1. Install the tools (Ubuntu 22.04, about 10 minutes, before the clock starts)

```bash
sudo apt update
sudo apt install -y git python3-venv python3-pip curl unzip wget gnupg ca-certificates lsb-release

# Docker Engine + Compose
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" | sudo tee /etc/apt/sources.list.d/docker.list
sudo apt update && sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo usermod -aG docker $USER && newgrp docker

# GitHub CLI (22.04's default package is too old, so use the official repo)
sudo mkdir -p -m 755 /etc/apt/keyrings
wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null
sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
sudo apt update && sudo apt install -y gh

# Terraform
wget -qO- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install -y terraform

# kubectl + kind
curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -m 0755 kubectl /usr/local/bin/kubectl
curl -Lo kind https://kind.sigs.k8s.io/dl/v0.24.0/kind-linux-amd64
sudo install -m 0755 kind /usr/local/bin/kind

# AWS CLI
curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
unzip -q awscliv2.zip && sudo ./aws/install

# SSH key (skip if you already have one)
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""
```

Log in and verify:

```bash
gh auth login                  # GitHub.com > HTTPS > login with browser
aws configure                  # IAM user with AmazonEC2FullAccess, region ap-south-1, output json
git --version && docker --version && docker compose version
gh --version | head -1 && terraform --version | head -1
kubectl version --client && kind --version && aws --version
aws sts get-caller-identity    # prints your AWS account
```

Notes for 22.04:
- Local Python is 3.10, which is fine for `make install` and `make test`. CI and the Docker image use 3.12 by themselves.
- If apt says "Waiting for cache lock", let the other apt finish; do not press Ctrl+C or delete lock files.
- On WSL, Docker comes from Docker Desktop for Windows with WSL integration turned on for Ubuntu-22.04. In that case skip the "Docker Engine + Compose" block above.

## 2. Timeline

| Time | Step |
|---|---|
| 0:00-0:15 | 3. Git workflow |
| 0:15-0:30 | 4. Run the game, tests, Docker |
| 0:30-0:55 | 5. CI/CD |
| 0:55-1:10 | 6. Kubernetes |
| 1:10-1:25 | 7. Monitoring and alerts (local) |
| 1:25-1:50 | 8. Terraform on AWS |
| 1:50-2:00 | 9. Screenshots, README |

## 3. Git workflow (0:00-0:15)

1. On GitHub create a **public** repo named exactly `snake-game` (public so CodeQL is free; the name
   keeps the image path `ghcr.io/vibrantaqua/snake-game` correct).
2. Unzip, format Terraform once (CI checks formatting), and push:

```bash
unzip snake-game.zip && cd snake-game
terraform -chdir=terraform fmt -recursive
git init -b main
git add . && git commit -m "chore: initial project"
git remote add origin https://github.com/Vibrantaqua/snake-game.git
git push -u origin main
git checkout -b dev && git push -u origin dev
```

3. Repo Settings > Branches: protect `main` (require a pull request and the `lint-test` check).
4. Normal PR flow: `git checkout -b feature/readme-note`, edit, push, PR into `dev`, merge, PR `dev` into `main`.
5. Deliberate merge conflict:

```bash
git checkout dev && git pull
bash scripts/git_flow_demo.sh
# fix VERSION by hand, then:
git add VERSION && git commit && git push origin dev
```

Screenshots: branch protection, PR with checks, conflict in terminal, resolved merge commit,
`git log --oneline --graph --all`.

## 4. Run the game, tests, Docker (0:15-0:30)

```bash
python3 -m venv .venv && source .venv/bin/activate
make install && make lint && make test
make run                               # http://localhost:5000 , play a round, save a score
```

Docker (stop `make run` first):

```bash
docker build -t snake-game:1.0 .
docker run --rm -d -p 5000:5000 --name snake snake-game:1.0
curl localhost:5000/health
docker exec snake id                   # uid=10001 proves non-root
docker images snake-game
docker stop snake
```

Why it scores: multi-stage build, slim base, non-root, HEALTHCHECK, `.dockerignore`, CSP and other
security headers in the app.

## 5. CI/CD (0:30-0:55)

1. Repo Settings > Actions > General > Workflow permissions: **Read and write**.
2. Merge to `main` (or push `dev`). Open the Actions tab.
3. Stages:
   - `lint-test`: flake8, pytest with coverage, packages a `.tgz`, uploads artifacts
   - `codeql`: SAST (results in Security > Code scanning)
   - `iac-validate`: `terraform fmt/validate` and a Trivy misconfiguration scan of Terraform, K8s and Dockerfile
   - `build-scan-push`: build, **Trivy image scan** (fails on CRITICAL), push to GHCR on non-PR runs
   - `deploy-kubernetes`: creates a kind cluster in the runner, deploys, rolling update, smoke test
4. After the first push to GHCR: profile > Packages > `snake-game` > Package settings > visibility **Public**
   (so the EC2 server can pull it).

Screenshots: full green job graph, artifacts, Trivy log, CodeQL page, GHCR package page.

## 6. Kubernetes (0:55-1:10)

```bash
make kind-up
make kind-deploy                       # builds, loads into kind, applies manifests
kubectl -n snake-game get all
kubectl -n snake-game port-forward svc/snake-game 8080:80 &
curl localhost:8080/health             # or open http://localhost:8080 and play

make kind-update                       # rolling update 1.0 -> 1.1, zero downtime
kubectl -n snake-game rollout history deploy/snake-game
kubectl -n snake-game rollout undo deploy/snake-game      # rollback
kubectl -n snake-game scale deploy/snake-game --replicas=5
```

Optional, so the HPA shows real CPU numbers:

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl -n kube-system patch deploy metrics-server --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
kubectl -n snake-game get hpa
```

Note: the leaderboard is stored in memory per pod, so the Service uses `sessionAffinity: ClientIP` to keep
a player on one pod, and a rolling update resets scores. Moving scores to a database (Redis/Postgres) is
the obvious next improvement; mention it in the report.

## 7. Monitoring and alerts, local (1:10-1:25)

```bash
make kind-down
docker compose up -d --build
```

- Prometheus: http://localhost:9090 > Status > Targets (app, node, prometheus all UP)
- Grafana: http://localhost:3000 (admin / admin) > Dashboards > Snake Game > Overview
- Play the game and save a few scores, then watch **Highest score** and **Scores submitted** change.
- Generate load:

```bash
for i in $(seq 1 200); do curl -s localhost:5000/api/scores >/dev/null; done
```

- Trigger the alert (run about 2 minutes, then open Prometheus > Alerts):

```bash
for i in $(seq 1 600); do curl -s localhost:5000/api/error >/dev/null; sleep 0.3; done
```

`HighErrorRate` goes Pending, then Firing. Screenshot it. `docker compose stop app` shows `InstanceDown`.

## 8. Terraform on AWS (1:25-1:50)

Prerequisite: the repo is pushed and public (the server clones it), and ideally the GHCR image exists
and is public (otherwise the server builds the image itself, which is slower).

```bash
cd terraform
terraform init
terraform plan  -var "my_ip_cidr=$(curl -s ifconfig.me)/32"
terraform apply -var "my_ip_cidr=$(curl -s ifconfig.me)/32" -auto-approve
```

What it creates: key pair, security group (SSH, Grafana and Prometheus only from your IP; game port
open), an encrypted Ubuntu 22.04 EC2 instance with IMDSv2 required, and two generated passwords
(`random_password`). A cloud-init script (`user_data.sh.tftpl`) installs Docker, clones the repo, writes a
`0600` `.env` with the secrets, and runs `docker compose up -d`.

Wait 3-5 minutes for first boot, then:

```bash
terraform output                                  # URLs
terraform output -raw grafana_password            # Grafana login: admin + this
curl $(terraform output -raw game_url)/health
```

Open `game_url` in a browser and play. Open `grafana_url` for the dashboard.

If something is missing, SSH in and check the boot log:

```bash
ssh ubuntu@$(terraform output -raw public_ip)
sudo tail -n 50 /var/log/cloud-init-output.log
```

Updating the game later: merge to `main` (CI pushes a new `latest` image), then from the repo root run
`make ec2-update`.

Note for the viva: `user_data` is visible to anyone on the instance and Terraform state contains the
generated passwords (state is git-ignored). In production use AWS Secrets Manager or SSM Parameter
Store with an IAM role.

## 9. Screenshot checklist (take as you go)

1. Branch protection rule
2. PR with passing checks
3. Merge conflict in terminal, then the resolution commit
4. `git log --graph`
5. Game running in the browser with the leaderboard
6. `docker images` and `docker exec snake id`
7. Actions run: full job graph green
8. Artifacts list
9. Trivy image scan log and config scan log
10. CodeQL / Security tab
11. GHCR package page
12. `kubectl get all -n snake-game`
13. Rolling update `rollout status` output
14. HPA output
15. Prometheus Targets (all UP)
16. Prometheus Alerts with an alert firing
17. Grafana dashboard with live data
18. `terraform plan` and `terraform apply` output
19. AWS console: EC2 instance and security group
20. Browser showing the game on the EC2 public IP

## 10. Report, slides, viva

### Report (5 marks): outline

1. Title, objectives, problem statement
2. Architecture diagram (Mermaid chart from `README.md`, exported as an image)
3. DevOps lifecycle and branching strategy (screenshots 1-4)
4. CI/CD design, stage by stage (7-11)
5. Containerization and Kubernetes (6, 12-14)
6. Infrastructure as Code with Terraform and cloud-init bootstrap (18-20)
7. Monitoring and alerting: metrics, dashboard, alert rules (15-17)
8. Security: non-root containers, security headers and input validation, CodeQL, Trivy, secrets handling, IMDSv2, security group scoping
9. Challenges, limitations (in-memory leaderboard), future work, mapping to course outcomes
10. References

### Presentation (10 marks): 10 slides, about 6 minutes

Problem and goal, architecture, Git flow, pipeline, container, Kubernetes, Terraform and cloud,
monitoring and alerting, security, demo or screenshots plus conclusion. Play the game live and show the
Grafana score panels moving.

### Viva (5 marks): likely questions

| Question | Short answer |
|---|---|
| What does the app do? | Serves a Snake game and a leaderboard API; exposes `/metrics`. The DevOps pipeline is the focus. |
| CI vs CD? | CI tests and builds every change; CD delivers the validated build to an environment. |
| Why multi-stage Dockerfile? | Build dependencies stay in the first stage; the final image is smaller with less attack surface. |
| Why non-root? | Limits damage if compromised; K8s enforces it again with `runAsNonRoot`. |
| Rolling update? | Pods are replaced gradually; `maxUnavailable: 0` keeps capacity, so no downtime. |
| Readiness vs liveness probe? | Readiness gates traffic; liveness restarts a stuck container. |
| Why `sessionAffinity`? | The leaderboard lives in each pod's memory, so a player is kept on one pod. A database would remove this. |
| SAST vs image scan vs config scan? | CodeQL reads source; Trivy image scan checks OS and library packages; Trivy config scan checks Terraform, K8s and Dockerfile misconfigurations. |
| How are secrets handled? | GitHub token for GHCR, K8s Secret in the cluster, Terraform `random_password` for the server, `.env` at 0600, nothing in Git. |
| What does Terraform do vs cloud-init? | Terraform creates the infrastructure; cloud-init runs once at first boot to install Docker and start the stack. |
| Why Prometheus pull model? | It scrapes `/metrics` every 15 s; alert rules are evaluated by Prometheus. |
| Why one gunicorn worker? | Counters and the in-memory leaderboard live in one process; threads give concurrency. |
| What does the HPA do? | Scales between 3 and 6 replicas at 70% CPU (needs metrics-server). |
| Which custom metrics? | `game_scores_submitted_total` and `game_high_score`, plus request count and latency. |
| How to roll back? | `kubectl rollout undo`, or redeploy a previous image tag. |

## 11. Troubleshooting

| Symptom | Fix |
|---|---|
| Push to GHCR denied | Settings > Actions > Workflow permissions = Read and write |
| CodeQL fails | Repo must be public (private needs GitHub Advanced Security) |
| `terraform fmt -check` fails in CI | Run `terraform -chdir=terraform fmt -recursive`, commit |
| Trivy image scan fails | Read the CVE, bump the base image tag or `requirements.txt` |
| Game URL does not load on EC2 | Wait for cloud-init (3-5 min); check `/var/log/cloud-init-output.log` |
| EC2 cannot pull the image | GHCR package is private; make it public (the server falls back to building) |
| Cannot SSH or open Grafana | Your IP changed; re-run `terraform apply` with the new `my_ip_cidr` |
| HPA shows `<unknown>` | Install metrics-server (section 6) |
| `ImagePullBackOff` in kind | Re-run `kind load docker-image ... --name snake` |
| Grafana shows no data | Prometheus Targets page; confirm `app` is UP; generate traffic |

## 12. Cleanup (avoid AWS charges)

Take your AWS screenshots first.

```bash
terraform -chdir=terraform destroy -var "my_ip_cidr=$(curl -s ifconfig.me)/32" -auto-approve
make kind-down
docker compose down -v
```
