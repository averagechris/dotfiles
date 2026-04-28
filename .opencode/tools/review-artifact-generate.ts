import { tool } from "@opencode-ai/plugin"
import { readFile } from "node:fs/promises"
import path from "node:path"

type GhPrView = {
  url: string
  title: string
  body: string
  baseRefName: string
  headRefName: string
  changedFiles: number
  files: Array<{
    path: string
    additions: number
    deletions: number
    changeType: string
  }>
  commits: Array<{
    oid: string
    messageHeadline: string
  }>
}

type DiffCue = {
  file: string
  addedLines: number
  removedLines: number
  touchedKeywords: string[]
  firstAddedLine?: number
  firstHunkHeader?: string
}

const classifyConcern = (filePath: string) => {
  if (filePath.includes("/domain/") || filePath.includes("/domain_models/")) {
    return "domain"
  }
  if (filePath.includes("/endpoints/")) {
    return "endpoint"
  }
  if (filePath.includes("/repositories/") || filePath.includes("/migrations/")) {
    return "persistence"
  }
  if (filePath.includes("openapi") || filePath.includes("schema")) {
    return "api"
  }
  if (filePath.startsWith("tests/")) {
    return "test"
  }
  if (filePath.startsWith("docs/") || filePath === "README.md") {
    return "docs"
  }
  return "other"
}

const excerptFromLocalFile = async (repoPath: string | undefined, filePath: string) => {
  if (!repoPath) return undefined

  try {
    const absolute = path.join(repoPath, filePath)
    const content = await readFile(absolute, "utf8")
    const lines = content.split(/\r?\n/).slice(0, 6).join("\n").trim()
    return lines.length > 240 ? `${lines.slice(0, 237)}...` : lines
  } catch {
    return undefined
  }
}

const parseDiffCues = (patchText: string) => {
  const cues = new Map<string, DiffCue>()
  let currentFile: string | null = null
  let currentRightLine: number | null = null

  for (const line of patchText.split(/\r?\n/)) {
    if (line.startsWith("diff --git ")) {
      const match = line.match(/^diff --git a\/(.+) b\/(.+)$/)
      currentFile = match?.[2] ?? null
      if (currentFile && !cues.has(currentFile)) {
        cues.set(currentFile, {
          file: currentFile,
          addedLines: 0,
          removedLines: 0,
          touchedKeywords: [],
        })
      }
      currentRightLine = null
      continue
    }

    if (!currentFile) continue
    const cue = cues.get(currentFile)
    if (!cue) continue

    if (line.startsWith("@@ ")) {
      const match = line.match(/^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@/)
      currentRightLine = match ? Number(match[1]) : null
      if (!cue.firstHunkHeader) {
        cue.firstHunkHeader = line
      }
      continue
    }

    if (line.startsWith("+++") || line.startsWith("---")) continue

    if (line.startsWith("+")) {
      cue.addedLines += 1
      if (cue.firstAddedLine === undefined && currentRightLine !== null) {
        cue.firstAddedLine = currentRightLine
      }
      if (currentRightLine !== null) currentRightLine += 1
      continue
    }

    if (line.startsWith("-")) {
      cue.removedLines += 1
      continue
    }

    if (!line.startsWith("\\")) {
      if (currentRightLine !== null) currentRightLine += 1
    }

    const interesting = [
      "auth",
      "authorize",
      "routing_scope",
      "cluster",
      "token",
      "scope",
      "permission",
      "query",
      "select",
      "migration",
      "validate",
      "null",
    ].filter((keyword) => line.toLowerCase().includes(keyword))

    for (const keyword of interesting) {
      if (!cue.touchedKeywords.includes(keyword)) {
        cue.touchedKeywords.push(keyword)
      }
    }
  }

  return cues
}

export default tool({
  description: "Generate a draft review artifact JSON payload for a GitHub PR, with optional local repo context",
  args: {
    repoPath: tool.schema.string().optional().describe("Optional absolute local repository path for local context and excerpts"),
    prViewJson: tool.schema.string().min(1).describe("JSON output from gh pr view --json ..."),
    prDiff: tool.schema.string().min(1).describe("Unified diff from gh pr diff or equivalent source"),
  },
  async execute(args) {
    const pr = JSON.parse(args.prViewJson) as GhPrView
    const diffCues = parseDiffCues(args.prDiff)
    const headSha = pr.commits.at(-1)?.oid
    const hotspots = pr.files
      .map((file) => ({
        ...file,
        concern: classifyConcern(file.path),
        delta: file.additions + file.deletions,
        cue: diffCues.get(file.path),
      }))
      .sort((a, b) => {
        const rank = (concern: string) =>
          ["domain", "endpoint", "persistence", "api", "test", "docs", "other"].indexOf(concern)
        const aKeywordWeight = a.cue?.touchedKeywords.length ?? 0
        const bKeywordWeight = b.cue?.touchedKeywords.length ?? 0
        return rank(a.concern) - rank(b.concern) || bKeywordWeight - aKeywordWeight || b.delta - a.delta
      })

    const topHotspots = hotspots.slice(0, 5)

    const findings = await Promise.all(
      topHotspots.map(async (file, index) => ({
        id: `hotspot-${index + 1}-${file.path.replaceAll(/[/.]/g, "-")}`,
        severity:
          file.concern === "domain" || file.concern === "endpoint"
            ? "non_blocking"
            : file.concern === "persistence" || file.concern === "api"
              ? "non_blocking"
              : "nit",
        scope:
          file.concern === "domain" || file.concern === "endpoint"
            ? "cross_file"
            : file.concern === "persistence"
              ? "architectural"
              : "local",
        concernArea:
          file.concern === "domain"
            ? "architecture"
            : file.concern === "endpoint"
              ? "authz"
              : file.concern === "persistence"
                ? "performance"
                : file.concern === "api"
                  ? "api"
                  : file.concern === "test"
                    ? "code_quality"
                    : "intent",
        target:
          file.concern === "domain" || file.concern === "persistence"
            ? "summary_candidate"
            : "either",
        summary: `Review hotspot in ${file.path}`,
        rationale:
          [
            file.concern === "domain"
              ? "Behavioral domain changes deserve the highest review attention because they shape the actual routing and authorization semantics."
              : file.concern === "endpoint"
                ? "Endpoint-layer changes can change validation, authz, and public API behavior."
                : file.concern === "persistence"
                  ? "Repository and migration changes can lock in data shape and query behavior."
                  : file.concern === "api"
                    ? "Schema-level changes can create external API commitments or mismatches."
                    : file.concern === "test"
                      ? "Tests validate intent and coverage, but should confirm the important behavior rather than distract from it."
                      : "This file changed materially enough to deserve explicit review attention.",
            file.cue?.touchedKeywords.length
              ? `Diff cues touched: ${file.cue.touchedKeywords.join(", ")}.`
              : null,
          ]
            .filter(Boolean)
            .join(" "),
        suggestedChange:
          file.concern === "docs"
            ? "Check that the documentation matches the final runtime behavior exactly."
            : file.cue?.touchedKeywords.includes("null")
              ? "Double-check that nullability and runtime validation still match the public API contract."
              : file.cue?.touchedKeywords.includes("migration")
                ? "Verify the migration semantics and rollout assumptions carefully."
                : undefined,
        concreteReplacement:
          file.concern === "docs" && file.cue?.touchedKeywords.includes("routing_scope")
            ? "Clarify the doc text so runtime behavior and documented routing semantics stay aligned."
            : undefined,
        excerptHint: await excerptFromLocalFile(args.repoPath, file.path),
        recommendationImpact: "comment",
        locations: [
          {
            file: file.path,
            ...(file.cue?.firstAddedLine !== undefined
              ? {
                  startLine: file.cue.firstAddedLine,
                  diffLine: file.cue.firstAddedLine,
                  diffSide: "RIGHT" as const,
                }
              : {}),
          },
        ],
      })),
    )

    const summaryDrafts = topHotspots.slice(0, 3).map((file) => {
      if (file.concern === "domain") {
        return `${file.path} is the main behavior hotspot here. I would spend most review time on whether the routing and auth semantics are actually what we want long term.${
          file.cue?.touchedKeywords.length ? ` Diff cues: ${file.cue.touchedKeywords.join(", ")}.` : ""
        }`
      }
      if (file.concern === "endpoint") {
        return `${file.path} changes public validation/serialization behavior, so I would sanity-check contract changes and authz boundaries closely.${
          file.cue?.touchedKeywords.length ? ` Diff cues: ${file.cue.touchedKeywords.join(", ")}.` : ""
        }`
      }
      if (file.concern === "persistence") {
        return `${file.path} carries persistence or migration risk. I would verify the data-shape and rollout assumptions carefully.${
          file.cue?.touchedKeywords.length ? ` Diff cues: ${file.cue.touchedKeywords.join(", ")}.` : ""
        }`
      }
      return `${file.path} is one of the main review hotspots in this PR.`
    })

    const artifact = {
      version: 1,
      source: {
        kind: "github_pr",
        title: pr.title,
        url: pr.url,
        repository: (() => {
          const match = pr.url.match(/^https:\/\/github\.com\/([^/]+)\/([^/]+)\/pull\/(\d+)$/)
          return match ? `${match[1]}/${match[2]}` : undefined
        })(),
        owner: (() => {
          const match = pr.url.match(/^https:\/\/github\.com\/([^/]+)\/([^/]+)\/pull\/(\d+)$/)
          return match?.[1]
        })(),
        repo: (() => {
          const match = pr.url.match(/^https:\/\/github\.com\/([^/]+)\/([^/]+)\/pull\/(\d+)$/)
          return match?.[2]
        })(),
        prNumber: (() => {
          const match = pr.url.match(/^https:\/\/github\.com\/([^/]+)\/([^/]+)\/pull\/(\d+)$/)
          return match ? Number(match[3]) : undefined
        })(),
        baseRef: pr.baseRefName,
        headRef: pr.headRefName,
        headSha,
        worktreeRoot: args.repoPath,
        workingDirectory: args.repoPath,
      },
      intentSummary:
        pr.body
          .split("\n")
          .slice(0, 8)
          .join(" ")
          .replace(/\s+/g, " ")
          .trim() || pr.title,
      overallAssessment:
        `This PR changes ${pr.changedFiles} files across ${topHotspots
          .map((file) => file.concern)
          .filter((value, index, array) => array.indexOf(value) === index)
          .join(", ")} concerns. The draft artifact is intentionally conservative: it uses diff-derived cues to prioritize likely review hotspots and draft comment directions, but it does not post or finalize a review state.`,
      recommendedDisposition: "comment",
      findings,
      drafts: {
        github: {
          inline: findings
            .filter((finding) => finding.target !== "summary_candidate")
            .slice(0, 2)
            .map((finding) => ({
              findingId: finding.id,
              body: `${finding.summary.toLowerCase()}. ${finding.rationale}`,
              location: finding.locations[0],
            })),
          summary: summaryDrafts,
          reviewBody: [
            "Draft review focus:",
            ...summaryDrafts.map((entry) => `- ${entry}`),
            "",
            "This is a draft comment-oriented review artifact only. Final inline comments and review state still need human confirmation.",
          ].join("\n"),
          recommendedState: "COMMENT",
        },
      },
    }

    return JSON.stringify(artifact, null, 2)
  },
})
