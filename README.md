# AI Agents and RAG-system CI/CD Gate

A GitHub composite action that turns an [EvalRun](https://github.com/arsenalzp/aievaluation) evaluation of an AI Agent or a
RAG (Retrieval-Augmented Generation) system into a pull-request gate.

The action selects the evaluation suite and the target endpoint from Pull Request labels, renders an `EvalRun` manifest from a
template, applies it to the cluster, waits for the verdict of **this commit**, reports the result in the job summary and in a
PR comment, and fails the workflow unless the verdict is `PASS`.

## Features

- **Dynamic routing via PR labels**
  - **Evaluation suite:** select an `EvalSuite` with an `evalsuite:<suite-name>` label.
  - **Evaluation type:** RAG by default; switch to AI Agent evaluation with a `type:agent` (or `agent`) label.
- **Kubernetes native:** creates and monitors an `EvalRun` custom resource in your cluster; the EvalRun operator runs the evaluation.
- **Commit-accurate verdicts:** one `EvalRun` per PR is re-applied on every push; the action waits for the result of the spec
  generation it applied and never reports the previous commit's verdict.
- **Rich reporting:** a Markdown job summary and a single, updated PR comment with phase, verdict, detailed root cause and artifact links.
- **CI/CD enforcer:** fails the workflow if the evaluation did not complete or the verdict is anything other than `PASS`.

## Prerequisites

- **EvalRun operator** installed in the cluster, in a version that reports `status.observedGeneration` (re-evaluation support).
  With an older controller the wait step times out.
- The `EvalSuite`, `EvalDataset` and Secrets referenced by your templates exist in the target namespace.
- A **self-hosted runner** with network access to the cluster (for example ARC - Actions Runner Controller) and these tools:
  - `kubectl`, with an identity allowed to `create`, `get` and `patch` `evalruns.ai.evaluation.io` in the target namespace
    (the action checks this before applying anything);
  - `jq`;
  - `envsubst` (package `gettext`);
  - `curl`.
- Workflow permission `pull-requests: write` for the PR comment (see [Usage](#usage-example)).

## Inputs

| Input | Default | Description |
| :--- | :--- | :--- |
| `template_path_rag` | `.github/templates/evalrun-rag.yaml.tpl` | `EvalRun` template used for RAG evaluation. |
| `template_path_agent` | `.github/templates/evalrun-agent.yaml.tpl` | `EvalRun` template used for AI Agent evaluation. |
| `endpoint_rag` | `http://k8s:8080/rag/query?debug=true` | Target endpoint for RAG evaluation. |
| `endpoint_agent` | `http://k8s:8080/agent/invoke` | Target endpoint for AI Agent evaluation. |
| `default_namespace` | `default` | Namespace in which the `EvalRun` is created. |
| `default_evalsuite` | `demo-suite` | `EvalSuite` used when the PR has no `evalsuite:` label. |

## PR Labels Configuration

The action reads Pull Request labels at runtime, so the evaluation can be changed without editing the workflow or the code.

### 1. Selecting the evaluation type

Controls which template (`template_path_rag` / `template_path_agent`) and endpoint (`endpoint_rag` / `endpoint_agent`) are used:

| Label | Description |
| :--- | :--- |
| *(none)* | **Default.** RAG evaluation using `template_path_rag` and `endpoint_rag`. |
| `type:agent` or `agent` | AI Agent evaluation using `template_path_agent` and `endpoint_agent`. |

Any other label (including `type:rag`) leaves the default RAG mode. Runs started with `workflow_dispatch` always use RAG mode.

### 2. Selecting the EvalSuite (`evalsuite:<suite-name>`)

To override `default_evalsuite`, add a label with the `evalsuite:` prefix:

- **Format:** `evalsuite:<suite-name>`
- **Example:** the label `evalsuite:smoke-tests` sets `EVALSUITE_NAME` to `smoke-tests`.
- **Several labels:** the first `evalsuite:` label returned by GitHub is used.
- **Fallback:** without an `evalsuite:` label, `default_evalsuite` is used.

## EvalRun Templates

Templates are rendered with `envsubst`. These variables are available:

| Variable | Value |
| :--- | :--- |
| `EVALRUN_NAME` | `pr-<pr-number>-ai-eval` for pull requests, `manual-ai-eval-<run-number>` otherwise (lowercased, DNS-safe). |
| `EVALSUITE_NAME` | Selected suite (label or `default_evalsuite`). |
| `NAMESPACE` | `default_namespace`. |
| `TARGET_ENDPOINT` | Selected endpoint (`endpoint_rag` or `endpoint_agent`). |
| `PR_NUMBER` | Pull request number, `0` for manual runs. |
| `GIT_SHA` | Commit SHA (`github.sha`). |
| `GITHUB_REPOSITORY`, `GITHUB_WORKFLOW` | Repository and workflow name. |

Minimal template (for example `.github/templates/evalrun-rag.yaml.tpl`):

```yaml
apiVersion: ai.evaluation.io/v1alpha1
kind: EvalRun
metadata:
  name: ${EVALRUN_NAME}
  namespace: ${NAMESPACE}
spec:
  suiteRef:
    name: ${EVALSUITE_NAME}
  targetEndpoint: "${TARGET_ENDPOINT}"
  revision:
    gitSHA: "${GIT_SHA}"
    prNumber: ${PR_NUMBER}
```

Keep `revision.gitSHA` in the template: a new commit changes the `EvalRun` spec, and that change is what makes the operator
evaluate again (see below). If the template sets `metadata.namespace`, it must equal `${NAMESPACE}`.

## How It Works

1. Selects the suite and the evaluation type from the PR labels.
2. Checks that the runner identity may `create`, `get` and `patch` `evalruns` in `default_namespace`.
3. Renders the template and runs `kubectl apply`, remembering the `metadata.generation` it applied.
4. Polls the `EvalRun` every 10 seconds for up to 1500 seconds until `status.observedGeneration` equals that generation and
   `status.phase` is `COMPLETED` or `FAILED`.
5. Writes the job summary and creates or updates one PR comment (identified by a hidden marker).
6. Fails the job unless the phase is `COMPLETED` and the verdict is `PASS`.

### Re-evaluation on new commits

All pushes to a PR use the same `EvalRun` (`pr-<number>-ai-eval`). A push re-applies it with a new `gitSHA`; the operator
notices the spec change, discards the previous result and evaluates again, keeping the previous artifacts. The action only
accepts a result whose `status.observedGeneration` equals the generation it applied, so it never reports the verdict of the
previous commit.

- **Superseded runs:** if a newer push re-applies the `EvalRun` while an older workflow is still waiting, the older workflow
  fails with `EvalRun/... was superseded by a newer apply`. Use a `concurrency` group (see the example) to cancel it instead.
- **Label changes:** changing the `evalsuite:` or `type:` label changes the spec and triggers a new evaluation. Adding an
  unrelated label leaves the spec unchanged and returns the existing result immediately.
- **Re-running a workflow** for the same commit does not re-evaluate either: the applied spec is unchanged.

### Report

The job summary and the PR comment contain phase, verdict, suite, evaluation type, `EvalRun` name, commit and the artifact
links (`scoresUri`, `gateSummaryUri`, `detailsUri`). For a failed gate the root cause lists `stage` and, when the runner
reports them, `code`, `metric`, `evaluator`, `case`, `turn`, `observed`, `required`, `details` and an evidence link, for example:

```text
stage: Policy
code: ACTION_WITHOUT_APPROVAL
case: travel-approval-001
turn: 4
observed: 1
required: 0
```

Artifact links point to the object-store HTTP gateway inside the cluster; they are reachable only from where that gateway is.

### Verdicts

| Phase / verdict | Job result |
| :--- | :--- |
| `COMPLETED` / `PASS` | Success |
| `COMPLETED` / `FAIL` | Failure |
| `COMPLETED` / `WARN` | Failure (only `PASS` passes the gate) |
| `FAILED` (runner, dataset or configuration error) | Failure |
| Timeout, superseded run, missing RBAC or template | Failure |

---

## Usage Example

> **Important:** include `labeled` (and preferably `unlabeled`) under `on.pull_request.types` so that adding, changing or
> removing an `evalsuite:` / `type:` label re-runs the gate.

Create a workflow file in your repository (e.g., `.github/workflows/ai-eval.yml`):

```yaml
name: AI Evaluation Gate

on:
  pull_request:
    types: [opened, synchronize, reopened, labeled, unlabeled]
  workflow_dispatch:

permissions:
  contents: read
  pull-requests: write   # create/update the PR comment

concurrency:
  # One gate per PR: a new push cancels the evaluation wait of the previous one.
  group: ai-eval-${{ github.event.pull_request.number || github.run_id }}
  cancel-in-progress: true

jobs:
  run-evaluation:
    runs-on: self-hosted
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Run AI Eval Gate
        uses: your-org/your-action-repo@v1   # pin a release tag or a commit SHA, not a branch
        with:
          default_namespace: "eval-namespace"
          default_evalsuite: "demo-suite"
          endpoint_rag: "http://rag-service.default.svc:8080/query"
          endpoint_agent: "http://agent-service.default.svc:8080/invoke"
```

To make the gate block merging, mark the `run-evaluation` check as required in the branch protection rules.

## Troubleshooting

| Symptom | Cause / fix |
| :--- | :--- |
| `The runner identity cannot 'create' evalruns in namespace ...` | Grant the runner's service account `create`, `get` and `patch` on `evalruns.ai.evaluation.io` in that namespace. |
| `Template not found: ...` | The template path is relative to the checked-out repository; keep `actions/checkout` before the action. |
| `envsubst is required in the ARC runner image` | Add the `gettext` package to the runner image. |
| Timeout, `observed=0` the whole time | The operator does not report `status.observedGeneration`: upgrade it. |
| Timeout, phase stays `PENDING` | The `EvalSuite` or `EvalDataset` is missing or invalid; see `kubectl describe evalrun <name>` (conditions such as `SuiteNotFound`, `SuiteInvalid`). |
| `superseded by a newer apply` | A newer push re-applied the same `EvalRun`; the newer workflow reports the result. |
| Warning `Could not post/update the PR comment` | Missing `pull-requests: write`, or a PR from a fork (read-only token). The verdict is still in the job summary and still decides the job result. |

## Security Notes

- PR label names and inputs are passed to shell steps through environment variables, never interpolated into the scripts.
- The PR comment uses the workflow's `GITHUB_TOKEN`; no other credentials are read by the action.
- Run the action only on self-hosted runners you trust with cluster access. Be careful with workflows triggered by pull requests
  from forks: they run code from the PR on a runner that can reach your cluster.
