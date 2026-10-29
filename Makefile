.PHONY: install lint test run build up down kind-up kind-deploy kind-update kind-down fmt ec2-update

install:
	pip install -r requirements-dev.txt

lint:
	flake8 .

test:
	pytest --cov=app --cov-report=term

run:
	python -m app.app

build:
	docker build -t snake-game:1.0 .

up:
	docker compose up -d --build

down:
	docker compose down

fmt:
	terraform -chdir=terraform fmt -recursive

kind-up:
	kind create cluster --name snake

kind-deploy: build
	kind load docker-image snake-game:1.0 --name snake
	kubectl apply -f k8s/namespace.yaml
	-kubectl -n snake-game create secret generic app-secret --from-literal=APP_SECRET_KEY=$$(openssl rand -hex 16)
	kubectl apply -f k8s/deployment.yaml -f k8s/service.yaml -f k8s/hpa.yaml
	kubectl -n snake-game rollout status deploy/snake-game

kind-update:
	docker tag snake-game:1.0 snake-game:1.1
	kind load docker-image snake-game:1.1 --name snake
	kubectl -n snake-game set image deploy/snake-game app=snake-game:1.1
	kubectl -n snake-game rollout status deploy/snake-game

kind-down:
	kind delete cluster --name snake

# Pull the newest image on the EC2 server (needs: terraform applied, SSH key in ~/.ssh)
ec2-update:
	ssh ubuntu@$$(terraform -chdir=terraform output -raw public_ip) \
	  'cd /opt/snake-game && sudo docker compose pull app && sudo docker compose up -d'
