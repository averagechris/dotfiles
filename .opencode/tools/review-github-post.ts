import { tool } from "@opencode-ai/plugin"
import { readFile } from "node:fs/promises"

type ReviewLocation = {
  file: string
  startLine?: number
  endLine?: number
  symbol?: string
  diffSide?: "LEFT" | "RIGHT"
  diffLine?: number
}

type GithubInlineDraft = {
  findingId: string
  body: string
  suggestedReplacement?: string
  location: ReviewLocation
}

type GithubDrafts = {
  inline: GithubInlineDraft[]
  summary: string[]
  reviewBody?: string
  recommendedState?: "COMMENT" | "APPROVE" | "REQUEST_CHANGES"
}

type ReviewArtifact = {
  source: {
    kind: "github_pr" | "local_diff" | "patch_review" | "other"
    owner?: string
    repo?: string
    prNumber?: number
    url?: string
    headSha?: string
  }
  drafts?: {
    github?: GithubDrafts
  }
}

const renderSuggestedReplacement = (replacement: string) => {
  return ["```suggestion", replacement, "```"].join("\n")
}

export default tool({
  description: "Submit a batched GitHub PR review from a persisted review artifact after explicit confirmation",
  args: {
    artifactPath: tool.schema.string().min(1).describe("Path returned by review-artifact-write"),
    finalState: tool.schema.enum(["COMMENT", "APPROVE", "REQUEST_CHANGES"]).describe("Explicit final GitHub review state"),
  },
  async execute(args) {
    const raw = await readFile(args.artifactPath, "utf8")
    const artifact = JSON.parse(raw) as ReviewArtifact

    if (artifact.source.kind !== "github_pr") {
      throw new Error("review-github-post requires a github_pr artifact")
    }

    const drafts = artifact.drafts?.github
    if (!drafts) {
      throw new Error("Artifact is missing drafts.github")
    }

    const owner = artifact.source.owner
    const repo = artifact.source.repo
    const pullNumber = artifact.source.prNumber
    const commitId = artifact.source.headSha

    if (!owner || !repo || !pullNumber) {
      throw new Error("Artifact source is missing owner/repo/prNumber metadata")
    }

    const reviewComments: Array<Record<string, unknown>> = []
    const promotedNotes: string[] = []

    for (const draft of drafts.inline) {
      const location = draft.location
      const body = draft.suggestedReplacement
        ? `${draft.body}\n\n${renderSuggestedReplacement(draft.suggestedReplacement)}`
        : draft.body

      if (location.diffLine !== undefined && location.diffSide && commitId) {
        reviewComments.push({
          path: location.file,
          line: location.diffLine,
          side: location.diffSide,
          body,
        })
        continue
      }

      if (location.startLine !== undefined && commitId) {
        reviewComments.push({
          path: location.file,
          line: location.startLine,
          ...(location.endLine && location.endLine !== location.startLine
            ? { start_line: location.startLine, line: location.endLine }
            : {}),
          side: "RIGHT",
          body,
        })
        continue
      }

      promotedNotes.push(`${location.file}: ${draft.body}`)
    }

    const summaryLines = [...drafts.summary]
    if (promotedNotes.length > 0) {
      summaryLines.push("", "Promoted from inline drafts due to missing robust inline location metadata:")
      promotedNotes.forEach((note) => summaryLines.push(`- ${note}`))
    }

    const body = drafts.reviewBody
      ? promotedNotes.length > 0
        ? [drafts.reviewBody, summaryLines.slice(drafts.summary.length).join("\n")].filter(Boolean).join("\n\n")
        : drafts.reviewBody
      : summaryLines.join("\n")

    const payload = {
      event: args.finalState,
      body,
      comments: reviewComments,
      ...(commitId ? { commit_id: commitId } : {}),
    }

    const result = await Bun.$`
      gh api \
        --method POST \
        repos/${owner}/${repo}/pulls/${pullNumber}/reviews \
        --input -
    `.stdin(JSON.stringify(payload)).text()

    return JSON.stringify(
      {
        submitted: true,
        owner,
        repo,
        pullNumber,
        finalState: args.finalState,
        inlineSubmitted: reviewComments.length,
        promotedToTopLevel: promotedNotes.length,
        response: result.trim(),
      },
      null,
      2,
    )
  },
})
