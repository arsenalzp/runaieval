# AI Agents and RAG-system CI/CD Gate

A GitHub Composite Action to trigger, monitor, and report on Kubernetes-based evaluations (EvalRun CRD) for AI Agents and RAG (Retrieval-Augmented Generation) systems.

This action dynamically configures the evaluation suite and target endpoints based on Pull Request labels, renders Kubernetes manifests from templates, applies them to the cluster, and waits for the evaluation verdict. Finally, it generates a detailed Markdown report in the GitHub Actions Step Summary.

## Features

- **Dynamic Routing via PR Labels:** 
- **Evaluation Suite:** Select an `EvalSuite` dynamically using the `evalsuite:suiteName` label.
- **Evaluation Type:** Switch between `type:rag` (default) and `type:agent` testing via PR labels.
- **Kubernetes Native:** Deploys and monitors an EvalRun Custom Resource Definition (CRD) directly in your cluster.
- **Automated Polling and Timeout:** Waits for the evaluation to complete, tracking the phase and verdict in real-time.
- **Rich Reporting:** Publishes a Markdown summary with execution status, root causes, and artifact URLs directly to the GitHub Actions UI.
- **CI/CD Enforcer:** Fails the workflow if the AI evaluation verdict is anything other than PASS.

## Prerequisites

Since this action interacts with a Kubernetes cluster, it is designed to run on a self-hosted runner (e.g., ARC - Actions Runner Controller) with the following tools installed:
- `kubectl` (configured with RBAC permissions to create/read EvalRun resources)
- `jq` (for JSON processing)
- `envsubst` (usually available via the `gettext` package)

## PR Labels Configuration

The action reads Pull Request labels at runtime to dynamically configure the test run without changing workflow definitions or codebase.

### 1. Selecting Evaluation Type (`type:<type>`)
Controls which endpoint and template file (`template_path_rag` vs `template_path_agent`) are used:

| Label | Description |
| :--- | :--- |
| `type:rag` | **(Default)** Runs evaluation in RAG mode using `endpoint_rag`. |
| `type:agent` | Switches evaluation to AI Agent mode using `endpoint_agent`. |

*Note: If no `type:*` label is present on the PR, the action defaults to `type:rag`.*

### 2. Dynamic EvalSuite Selection (`evalsuite:suiteName`)
To override the default test suite (`default_evalsuite`), attach a label with the `evalsuite:` prefix:

- **Format:** `evalsuite:suiteName`
- **Example:** Applying label `evalsuite:smoke-tests` sets the `$EVALSUITE_NAME` variable to `smoke-tests`.
- **Fallback:** If no `evalsuite:*` label is found on the PR, the action falls back to the value passed in `default_evalsuite`.

---

## Usage Example

> **Important:** Make sure your workflow includes `labeled` under `on.pull_request.types` so GitHub Actions triggers the evaluation whenever you apply or change PR labels.

Create a workflow file in your repository (e.g., `.github/workflows/ai-eval.yml`):

```yaml
name: AI Evaluation Gate

on: 
  pull_request:
    types: [opened, synchronize, reopened, labeled] # Required to trigger re-evaluations when PR labels change
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
          default_namespace: "eval-namespace"
          default_evalsuite: "demo-suite"
          endpoint_rag: "[http://rag-service.default.svc:8080/query](http://rag-service.default.svc:8080/query)"
          endpoint_agent: "[http://agent-service.default.svc:8080/invoke](http://agent-service.default.svc:8080/invoke)"