# Suite without an LLM judge: multi-turn agent without a deepeval evaluator (built-in deterministic checks only).
# spec.llm must be absent: the controller rejects an LLM that nothing uses (condition LLMInvalid).
apiVersion: ai.evaluation.io/v1alpha1
kind: EvalRun
metadata:
  name: ${EVALRUN_NAME}
  namespace: ${NAMESPACE}
  annotations:
    ai.evaluation.io/github-repository: "${GITHUB_REPOSITORY}"
    ai.evaluation.io/github-run-id: "${GITHUB_RUN_ID}"
spec:
  summaryBucket: "${SUMMARY_BUCKET}"
  suiteRef:
    name: ${EVALSUITE_NAME}
  revision:
    gitSHA: "${GIT_SHA}"
    prNumber: ${PR_NUMBER}
  targetEndpoint: "${TARGET_ENDPOINT}"
