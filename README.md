# AI Agents and RAG-system CI/CD Gate

A GitHub composite action that turns an [EvalRun](https://github.com/arsenalzp/aievaluation) evaluation of an AI Agent or a
RAG (Retrieval-Augmented Generation) system into a pull-request gate.

The action reads the `EvalSuite` selected by a PR label, picks the matching `EvalRun` template and target endpoint from the
suite itself, renders the manifest (including the judge LLM), applies it to the cluster, waits for the verdict of **this commit**,
reports the result in the job summary and in a PR comment, and fails the workflow unless the verdict is `PASS`.

## Features

- **One label, no guessing:** select an `EvalSuite` with an `evalsuite:<suite-name>` label. Whether it is a RAG, single-turn
  agent or multi-turn agent evaluation, and whether it needs a judge LLM, is read from the suite - developers do not label the
  evaluation type.
- **Built-in templates:** the action ships its `EvalRun` templates, versioned with the action release; callers only pass
  parameters. Custom templates are still possible.
- **Any judge LLM:** the public OpenAI API with a key from a Kubernetes Secret, or any OpenAI-compatible server inside your
  perimeter (vLLM, Ollama, LiteLLM, ...) by URL, with or without a key.
- **Kubernetes native:** creates and monitors an `EvalRun` custom resource; the EvalRun operator runs the evaluation.
- **Commit-accurate verdicts:** one `EvalRun` per PR is re-applied on every push; the action waits for the result of the spec
  generation it applied and never reports the previous commit's verdict.
- **Early, readable errors:** a missing model, embedder, key or URL is reported before anything is applied; while the run is
  `PENDING`, the reason reported by the operator is printed in the log.
- **Rich reporting:** a Markdown job summary and a single, updated PR comment with phase, verdict, detailed root cause and every
  artifact link (including multi-turn violations and conversations).
- **CI/CD enforcer:** fails the workflow if the evaluation did not complete or the verdict is anything other than `PASS`.

## Prerequisites

- **EvalRun operator** installed in the cluster, in a version that supports `EvalRun.spec.llm` and reports
  `status.observedGeneration` (re-evaluation support). With an older controller the apply is rejected or the wait step times out.
- The `EvalSuite`, `EvalDataset` and the judge API-key Secret (if you use one) exist in the target namespace.
- A **self-hosted runner** with network access to the cluster (for example ARC - Actions Runner Controller) and these tools:
  - `kubectl`, with an identity allowed to `create`, `get` and `patch` `evalruns.ai.evaluation.io` and to `get`
    `evalsuites.ai.evaluation.io` in the target namespace (the action checks this before applying anything);
  - `jq`;
  - `envsubst` (package `gettext`);
  - `curl`.
- Workflow permission `pull-requests: write` for the PR comment (see [Usage](#usage-example)).

## Inputs

| Input | Default | Description |
| :--- | :--- | :--- |
| `default_evalsuite` | `demo-suite` | `EvalSuite` used when the PR has no `evalsuite:` label. |
| `default_namespace` | `default` | Namespace in which the `EvalRun` is created and the `EvalSuite` is read. |
| `endpoint_rag` | `http://k8s:8080/rag/query?debug=true` | Target endpoint when the suite is a RAG suite. |
| `endpoint_agent` | `http://k8s:8088/agent/run` | Target endpoint when the suite is an agent suite (single- or multi-turn). |
| `summary_bucket` | `eval-artifacts` | Object-store bucket for the run artifacts (`EvalRun.spec.summaryBucket`). |
| `llm_model` | *(empty)* | Judge model (`spec.llm.model`). Required when the suite uses an LLM judge. |
| `llm_embedder` | *(empty)* | Embedding model (`spec.llm.embedder`). Required for RAG suites, not used by agent suites. |
| `llm_url` | *(empty)* | Base URL of an OpenAI-compatible server inside your perimeter. Empty = public OpenAI API. |
| `llm_api_key_secret` | *(empty)* | Name of the Kubernetes Secret holding the judge API key. Required without `llm_url`. |
| `llm_api_key_secret_key` | `apiKey` | Key inside that Secret. |
| `template_path_rag` | *(empty = built-in)* | Custom template for RAG suites, path in **your** repository. |
| `template_path_agent` | *(empty = built-in)* | Custom template for agent suites with an LLM judge, path in **your** repository. |
| `template_path_agent_deterministic` | *(empty = built-in)* | Custom template for suites without an LLM judge, path in **your** repository. |

The `llm_*` inputs can be set once for the whole workflow: the action uses only what the selected suite needs and prints a
`::notice::` for inputs that this particular suite does not use (for example `llm_embedder` on an agent suite).

## Selecting the EvalSuite (`evalsuite:<suite-name>`)

The action reads Pull Request labels at runtime, so the evaluation can be changed without editing the workflow or the code.

- **Format:** `evalsuite:<suite-name>`
- **Example:** the label `evalsuite:smoke-tests` evaluates the `EvalSuite` `smoke-tests`.
- **Several labels:** the first `evalsuite:` label returned by GitHub is used.
- **Fallback:** without an `evalsuite:` label (and for `workflow_dispatch` runs), `default_evalsuite` is used.
- The name must be a valid Kubernetes object name; anything else fails the job.

The former `type:agent` / `agent` labels are no longer needed and are ignored: the evaluation type comes from the suite.

## How the template and the judge LLM are chosen

The action reads the `EvalSuite` and applies the same rules the operator enforces, so the rendered `EvalRun` always matches what
the suite's runner needs:

| EvalSuite | Template | `spec.llm` | Endpoint |
| :--- | :--- | :--- | :--- |
| RAG (`spec.metrics.rag`) | `evalrun-rag` | judge + embedder | `endpoint_rag` |
| Single-turn agent (`spec.metrics.agent`) | `evalrun-agent` | judge, no embedder | `endpoint_agent` |
| Multi-turn agent with a `deepeval` evaluator | `evalrun-agent` | judge, no embedder | `endpoint_agent` |
| Multi-turn agent without a `deepeval` evaluator | `evalrun-agent-deterministic` | none | `endpoint_agent` |
| `spec.execution.mode: dummy` | `evalrun-agent-deterministic` | none | by metrics section |

Why it matters: the operator rejects an `EvalRun` whose `spec.llm` does not fit the suite (missing judge, embedder on an agent
suite, or an LLM that nothing uses) and leaves it `PENDING` with condition `LLMInvalid`. Choosing by suite avoids that class of
mistakes entirely.

### Judge LLM connection

| Setup | Inputs | Rendered `spec.llm` |
| :--- | :--- | :--- |
| Public OpenAI API | `llm_model`, `llm_api_key_secret` | `model` + `apiKeySecretRef` |
| LLM inside your perimeter, no auth | `llm_model`, `llm_url` | `model` + `url` |
| LLM inside your perimeter with a key | `llm_model`, `llm_url`, `llm_api_key_secret` | `model` + `url` + `apiKeySecretRef` |

RAG suites additionally need `llm_embedder`; the embedder uses the same provider, URL and key as the judge. The API key itself never
passes through GitHub: the action only renders the Secret's *name*, and the operator injects the key into the evaluation Job.

Create the Secret once per namespace:

```bash
kubectl -n eval-namespace create secret generic openai-credentials --from-literal=apiKey=sk-...
```

## EvalRun Templates

The built-in templates live in this action's repository under `.github/templates/` and are addressed via `$GITHUB_ACTION_PATH`,
so they always match the action release you pinned:

- `evalrun-rag.yaml.tpl`
- `evalrun-agent.yaml.tpl`
- `evalrun-agent-deterministic.yaml.tpl`

To use your own template, set the corresponding `template_path_*` input to a path in **your** repository (and keep
`actions/checkout` before the action). Templates are rendered with `envsubst`; **only** these variables are substituted, any other
`$...` stays as written:

| Variable | Value |
| :--- | :--- |
| `EVALRUN_NAME` | `pr-<pr-number>-ai-eval` for pull requests, `manual-ai-eval-<run-number>` otherwise (lowercased, DNS-safe). |
| `EVALSUITE_NAME` | Selected suite (label or `default_evalsuite`). |
| `NAMESPACE` | `default_namespace`. |
| `TARGET_ENDPOINT` | `endpoint_rag` or `endpoint_agent`, chosen by the suite. |
| `PR_NUMBER` | Pull request number, `0` for manual runs. |
| `GIT_SHA` | Commit SHA (`github.sha`). |
| `SUMMARY_BUCKET` | `summary_bucket`. |
| `LLM_MODEL`, `LLM_EMBEDDER` | `llm_model`, `llm_embedder`. |
| `LLM_CONNECTION` | Pre-indented optional lines of `spec.llm`: `url` and/or `apiKeySecretRef` (empty when neither is set). |
| `GITHUB_REPOSITORY`, `GITHUB_RUN_ID` | Repository and workflow run id (rendered as annotations by the built-in templates). |

Built-in template for agent suites with a judge (`evalrun-agent.yaml.tpl`):

```yaml
apiVersion: ai.evaluation.io/v1alpha1
kind: EvalRun
metadata:
  name: ${EVALRUN_NAME}
  namespace: ${NAMESPACE}
  annotations:
    ai.evaluation.io/github-repository: "${GITHUB_REPOSITORY}"
    ai.evaluation.io/github-run-id: "${GITHUB_RUN_ID}"
spec:
  llm:
    provider: openai
    model: "${LLM_MODEL}"
${LLM_CONNECTION}
  summaryBucket: "${SUMMARY_BUCKET}"
  suiteRef:
    name: ${EVALSUITE_NAME}
  revision:
    gitSHA: "${GIT_SHA}"
    prNumber: ${PR_NUMBER}
  targetEndpoint: "${TARGET_ENDPOINT}"
```

Rules for custom templates:

- Keep `revision.gitSHA`: a new commit changes the `EvalRun` spec, and that change is what makes the operator evaluate again (see below).
- If the template sets `metadata.namespace`, it must equal `${NAMESPACE}`.
- Keep `${LLM_CONNECTION}` on its own line at column 0 directly under the `spec.llm` fields: its lines are already indented.
- A template for a suite without an LLM judge must not contain `spec.llm` at all.

## How It Works

1. Selects the suite from the PR labels (or `default_evalsuite`).
2. Checks that the runner identity may `create`, `get` and `patch` `evalruns` and `get` `evalsuites` in `default_namespace`.
3. Reads the `EvalSuite` and chooses the template, the endpoint and the `spec.llm` shape.
4. Validates the `llm_*` inputs for that suite, renders the template and runs `kubectl apply`, remembering the
   `metadata.generation` it applied.
5. Polls the `EvalRun` every 10 seconds for up to 1500 seconds until `status.observedGeneration` equals that generation and
   `status.phase` is `COMPLETED` or `FAILED`. While the run is `PENDING`, the operator's reason (`status.summary`) is printed.
6. Writes the job summary and creates or updates one PR comment (identified by a hidden marker; all comment pages are searched).
7. Fails the job unless the phase is `COMPLETED` and the verdict is `PASS`.

### Re-evaluation on new commits

All pushes to a PR use the same `EvalRun` (`pr-<number>-ai-eval`). A push re-applies it with a new `gitSHA`; the operator
notices the spec change, discards the previous result and evaluates again, keeping the previous artifacts. The action only
accepts a result whose `status.observedGeneration` equals the generation it applied, so it never reports the verdict of the
previous commit.

- **Superseded runs:** if a newer push re-applies the `EvalRun` while an older workflow is still waiting, the older workflow
  fails with `EvalRun/... was superseded by a newer apply`. Use a `concurrency` group (see the example) to cancel it instead.
- **Label changes:** changing the `evalsuite:` label changes the spec and triggers a new evaluation. Adding an unrelated label
  leaves the spec unchanged and returns the existing result immediately.
- **Input changes:** changing `llm_*`, an endpoint or `summary_bucket` also changes the spec and triggers a new evaluation.
- **Re-running a workflow** for the same commit and inputs does not re-evaluate: the applied spec is unchanged.
- **Editing the `EvalSuite`** does not re-evaluate an existing `EvalRun` (the operator only sets the `SuiteChanged` condition);
  push a commit or delete the `EvalRun` to evaluate against the new suite.

### Report

The job summary and the PR comment contain phase, verdict, suite, evaluation type (`rag` / `agent`), `EvalRun` name, commit and
every artifact link the runner reported: scores, gate summary and raw results, plus manifest, violations and conversations for
multi-turn runs. For a failed gate the root cause lists `stage` and, when the runner reports them, `code`, `metric`, `evaluator`,
`case`, `turn`, `observed`, `required`, `details` and an evidence link, for example:

```text
stage: Policy
code: ACTION_WITHOUT_APPROVAL
case: travel-approval-001
turn: 4
evidence: http://object-store:9876/buckets/eval-artifacts/objects/runs/pr-42-ai-eval/violations.jsonl
```

Artifact links point to the object-store HTTP gateway inside the cluster; they are reachable only from where that gateway is.

### Verdicts

| Phase / verdict | Job result |
| :--- | :--- |
| `COMPLETED` / `PASS` | Success |
| `COMPLETED` / `FAIL` | Failure |
| `COMPLETED` / `WARN` | Failure (only `PASS` passes the gate) |
| `FAILED` (runner, dataset or configuration error) | Failure |
| Invalid inputs, missing suite, timeout, superseded run, missing RBAC or template | Failure |

---

## Usage Example

> **Important:** include `labeled` (and preferably `unlabeled`) under `on.pull_request.types` so that adding, changing or
> removing an `evalsuite:` label re-runs the gate.

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
      # Needed only for custom templates (template_path_* inputs); the built-in templates ship with the action.
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Run AI Eval Gate
        uses: your-org/your-action-repo@v2   # pin a release tag or a commit SHA, not a branch
        with:
          default_namespace: "eval-namespace"
          default_evalsuite: "demo-suite"
          endpoint_rag: "http://rag-service.default.svc:8080/query"
          endpoint_agent: "http://agent-service.default.svc:8088/agent/run"
          # Judge LLM: public OpenAI API with a key from a Secret in eval-namespace...
          llm_model: "gpt-5-mini"
          llm_embedder: "text-embedding-3-small"   # used by RAG suites only
          llm_api_key_secret: "openai-credentials"
          # ...or a model inside your perimeter (add llm_api_key_secret if it requires a key):
          # llm_url: "http://vllm.models.svc:8000/v1"
```

To make the gate block merging, mark the `run-evaluation` check as required in the branch protection rules.

## Upgrading from v1

- Requires an operator with `EvalRun.spec.llm` (it replaced `spec.model` / `spec.embedder` and the fixed Secret `openai-credentials`).
- Remove your copies of `.github/templates/evalrun-{rag,agent}.yaml.tpl` from the application repository, or point
  `template_path_*` at them after migrating them to `spec.llm` and `${LLM_CONNECTION}`.
- Add the `llm_*` inputs (and `summary_bucket` if your bucket is not `eval-artifacts`).
- Grant the runner identity `get` on `evalsuites.ai.evaluation.io`.
- Drop `type:agent` / `agent` labels; they no longer have any effect.
- The default `endpoint_agent` changed to `http://k8s:8088/agent/run`.

## Troubleshooting

| Symptom | Cause / fix |
| :--- | :--- |
| `The runner identity cannot '<verb>' <resource> in namespace ...` | Grant the runner's service account `create`, `get`, `patch` on `evalruns` and `get` on `evalsuites` (`ai.evaluation.io`) in that namespace. |
| `EvalSuite '<name>' not found in namespace ...` | Wrong `evalsuite:` label or `default_evalsuite`, or the suite lives in another namespace. |
| `Invalid EvalSuite name ...` | The label value is not a Kubernetes object name (lowercase letters, digits, `-`, `.`). |
| `... uses an LLM judge: set the input llm_model` | The suite needs a judge; set `llm_model`. |
| `RAG EvalSuite ... needs an embedding model` | Set `llm_embedder` (served by the same provider / URL as the judge). |
| `Set llm_api_key_secret ... or llm_url ...` | The public API needs a key: set the Secret name, or point `llm_url` at your own server. |
| `llm_url must start with http:// or https://` | Fix the URL (e.g. `http://vllm.models.svc:8000/v1`). |
| `Input for ... must not contain quotes, backslashes or newlines` | Remove those characters; they would break the rendered YAML. |
| `::notice:: ... is not used for this run` | Informational: the selected suite does not use that `llm_*` input (e.g. no judge, or embedder on an agent suite). |
| `Template not found: ...` | A custom `template_path_*` is relative to the checked-out repository; keep `actions/checkout` before the action. |
| `envsubst is required in the ARC runner image` | Add the `gettext` package to the runner image. |
| Timeout, phase stays `PENDING` | The log shows the operator's reason. Typical conditions: `SuiteNotFound`, `SuiteInvalid`, `EvalDatasetNotFound`, `DatasetRefMissing`, `DatasetObjectKeyMissing`, `LLMInvalid` (`kubectl describe evalrun <name>`). The action currently waits for the full timeout in this case. |
| Timeout, `observed=0` while the run is not `PENDING` | The operator does not report `status.observedGeneration`: upgrade it. |
| Job pod stuck in `CreateContainerConfigError` | A Secret referenced by the Job is missing in the namespace (the judge key Secret, or the operator's object-store Secret `eval-s3-credentials`). |
| `superseded by a newer apply` | A newer push re-applied the same `EvalRun`; the newer workflow reports the result. |
| Warning `Could not post/update the PR comment` | Missing `pull-requests: write`, or a PR from a fork (read-only token). The verdict is still in the job summary and still decides the job result. |

## Security Notes

- PR label names and inputs are passed to shell steps through environment variables, never interpolated into the scripts; the
  suite name must be a Kubernetes object name and values rendered into YAML may not contain quotes, backslashes or newlines.
- The judge API key never passes through the workflow: only the Secret name is rendered, and the operator reads the key in the cluster.
- The PR comment uses the workflow's `GITHUB_TOKEN`; no other credentials are read by the action.
- Run the action only on self-hosted runners you trust with cluster access. Be careful with workflows triggered by pull requests
  from forks: they run code from the PR on a runner that can reach your cluster.
