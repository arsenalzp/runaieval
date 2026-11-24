# RAG suite: the judge LLM scores the ragas metrics and the Safety Judge; the embedder comes from the same provider.
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
    embedder: "${LLM_EMBEDDER}"
${LLM_CONNECTION}
  summaryBucket: "${SUMMARY_BUCKET}"
  suiteRef:
    name: ${EVALSUITE_NAME}
  revision:
    gitSHA: "${GIT_SHA}"
    prNumber: ${PR_NUMBER}
  targetEndpoint: "${TARGET_ENDPOINT}"
