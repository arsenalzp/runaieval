# Agent suite with an LLM judge: single-turn agent (Phoenix judges) or multi-turn with a deepeval evaluator.
# No embedder: only RAG suites use an embedding model.
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
