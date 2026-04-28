import { tool } from "@opencode-ai/plugin"
import { mkdtemp, writeFile } from "node:fs/promises"
import { tmpdir } from "node:os"
import path from "node:path"

const reviewLocation = tool.schema.object({
  file: tool.schema.string().min(1).describe("Repository-relative file path"),
  startLine: tool.schema.number().int().positive().optional().describe("1-indexed start line"),
  endLine: tool.schema.number().int().positive().optional().describe("1-indexed end line"),
  symbol: tool.schema.string().optional().describe("Optional symbol or function name"),
  diffSide: tool.schema.enum(["LEFT", "RIGHT"]).optional().describe("Optional GitHub diff side hint"),
  diffLine: tool.schema.number().int().positive().optional().describe("Optional GitHub diff line hint"),
})

const githubInlineDraft = tool.schema.object({
  findingId: tool.schema.string().min(1),
  body: tool.schema.string().min(1),
  suggestedReplacement: tool.schema.string().optional(),
  location: reviewLocation,
})

const githubDrafts = tool.schema.object({
  inline: tool.schema.array(githubInlineDraft).default([]),
  summary: tool.schema.array(tool.schema.string().min(1)).default([]),
  reviewBody: tool.schema.string().optional(),
  recommendedState: tool.schema.enum(["COMMENT", "APPROVE", "REQUEST_CHANGES"]).optional(),
})

const reviewFinding = tool.schema.object({
  id: tool.schema.string().min(1).describe("Stable finding identifier"),
  severity: tool.schema.enum(["blocking", "non_blocking", "nit"]),
  scope: tool.schema.enum(["local", "cross_file", "architectural"]),
  concernArea: tool.schema.enum([
    "intent",
    "architecture",
    "api",
    "security",
    "authz",
    "data_exposure",
    "performance",
    "code_quality",
  ]),
  target: tool.schema.enum(["inline_candidate", "summary_candidate", "either"]),
  summary: tool.schema.string().min(1),
  rationale: tool.schema.string().min(1),
  suggestedChange: tool.schema.string().optional(),
  concreteReplacement: tool.schema.string().optional().describe("Exact replacement text when a small concrete fix exists"),
  excerptHint: tool.schema.string().optional().describe("Optional tiny excerpt or phrase to help terminal rendering"),
  recommendationImpact: tool.schema.enum(["none", "comment", "approve", "request_changes"]),
  locations: tool.schema.array(reviewLocation).default([]),
})

const reviewArtifactSchema = tool.schema.object({
  version: tool.schema.literal(1),
  source: tool.schema.object({
    kind: tool.schema.enum(["github_pr", "local_diff", "patch_review", "other"]),
    title: tool.schema.string().min(1),
    url: tool.schema.string().optional(),
    repository: tool.schema.string().optional(),
    owner: tool.schema.string().optional(),
    repo: tool.schema.string().optional(),
    prNumber: tool.schema.number().int().positive().optional(),
    baseRef: tool.schema.string().optional(),
    headRef: tool.schema.string().optional(),
    baseSha: tool.schema.string().optional(),
    headSha: tool.schema.string().optional(),
    worktreeRoot: tool.schema.string().optional().describe("Absolute path to the repository or worktree root used for analysis"),
    workingDirectory: tool.schema.string().optional().describe("Absolute path to the working directory used during review"),
  }),
  intentSummary: tool.schema.string().min(1),
  overallAssessment: tool.schema.string().min(1),
  recommendedDisposition: tool.schema.enum(["comment", "approve", "request_changes"]),
  findings: tool.schema.array(reviewFinding),
  drafts: tool.schema.object({
    github: githubDrafts.optional(),
  }).optional(),
})

export default tool({
  description: "Validate and persist a structured code review artifact to a temporary JSON file",
  args: {
    artifact: reviewArtifactSchema,
  },
  async execute(args) {
    const dir = await mkdtemp(path.join(tmpdir(), "opencode-review-"))
    const filePath = path.join(dir, "artifact.json")
    const artifactJson = JSON.stringify(args.artifact, null, 2)

    await writeFile(filePath, artifactJson, "utf8")

    const stats = {
      findings: args.artifact.findings.length,
      blocking: args.artifact.findings.filter((finding) => finding.severity === "blocking").length,
      nonBlocking: args.artifact.findings.filter((finding) => finding.severity === "non_blocking").length,
      nits: args.artifact.findings.filter((finding) => finding.severity === "nit").length,
    }

    return JSON.stringify(
      {
        path: filePath,
        stats,
      },
      null,
      2,
    )
  },
})
