# AI Agents and RAG-system CI/CD Gate

A GitHub Composite Action to trigger, monitor, and report on Kubernetes-based evaluations (EvalRun CRD) for AI Agents and RAG (Retrieval-Augmented Generation) systems.

This action dynamically configures the evaluation suite and target endpoints based on Pull Request labels, renders Kubernetes manifests from templates, applies them to the cluster, and waits for the evaluation verdict. Finally, it generates a detailed Markdown report in the GitHub Actions Step Summary.

## Features

- **Dynamic Routing via PR Labels:** Automatically switch between RAG and AI Agent testing, and select specific evaluation suites just by applying or updating labels on a Pull Request.
- **Kubernetes Native:** Deploys and monitors an EvalRun Custom Resource Definition (CRD) directly in your cluster.
- **Automated Polling and Timeout:** Waits for the evaluation to complete, tracking the phase and verdict in real-time.
- **Rich Reporting:** Publishes a Markdown summary with execution status, root causes, and artifact URLs directly to the GitHub Actions UI.
- **CI/CD Enforcer:** Fails the workflow if the AI evaluation verdict is anything other than PASS.

## Prerequisites

Since this action interacts with a Kubernetes cluster, it is designed to run on a self-hosted runner (e.g., ARC - Actions Runner Controller) with the following tools installed:
- `kubectl` (configured with RBAC permissions to create/read EvalRun resources)
- `jq` (for JSON processing)
- `envsubst` (usually available via the `gettext` package)

## Usage & PR Label Integration

> **Important:** To enable dynamic configuration via PR labels, make sure your workflow includes `labeled` (and optionally `unlabeled`) under `on.pull_request.types`.

Create a workflow file in your repository (e.g., `.github/workflows/ai-eval.yml`):

```yaml
name: AI Evaluation Gate

on: 
  pull_request:
    types: [opened, synchronize, reopened, labeled] # 'labeled' is required to trigger re-evaluations when PR labels change
  workflow_dispatch:

jobs:
  run-evaluation:
    runs-on: self-hosted
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Run AI Eval Gate
        uses: your-org/your-repo-name@main
        with:
          default_namespace: "default"
          default_evalsuite: "demo-suite"
          endpoint_rag: "[http://rag-service.default.svc:8080/query](http://rag-service.default.svc:8080/query)"
          endpoint_agent: "[http://agent-service.default.svc:8080/invoke](http://agent-service.default.svc:8080/invoke)"