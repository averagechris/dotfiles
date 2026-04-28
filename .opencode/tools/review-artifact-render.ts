import { tool } from "@opencode-ai/plugin"
import { readFile } from "node:fs/promises"
import path from "node:path"

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

type ReviewFinding = {
  id: string
  severity: "blocking" | "non_blocking" | "nit"
  scope: "local" | "cross_file" | "architectural"
  concernArea:
    | "intent"
    | "architecture"
    | "api"
    | "security"
    | "authz"
    | "data_exposure"
    | "performance"
    | "code_quality"
  target: "inline_candidate" | "summary_candidate" | "either"
  summary: string
  rationale: string
  suggestedChange?: string
  concreteReplacement?: string
  excerptHint?: string
  recommendationImpact: "none" | "comment" | "approve" | "request_changes"
  locations: ReviewLocation[]
}

type ReviewArtifact = {
  version: 1
  source: {
    kind: "github_pr" | "local_diff" | "patch_review" | "other"
    title: string
    url?: string
    repository?: string
    owner?: string
    repo?: string
    prNumber?: number
    baseRef?: string
    headRef?: string
    baseSha?: string
    headSha?: string
    worktreeRoot?: string
    workingDirectory?: string
  }
  intentSummary: string
  overallAssessment: string
  recommendedDisposition: "comment" | "approve" | "request_changes"
  findings: ReviewFinding[]
  drafts?: {
    github?: GithubDrafts
  }
}

const formatLocation = (location: ReviewLocation) => {
  const linePart =
    location.startLine === undefined
      ? ""
      : location.endLine !== undefined && location.endLine !== location.startLine
        ? `:${location.startLine}-${location.endLine}`
        : `:${location.startLine}`

  const symbolPart = location.symbol ? ` (${location.symbol})` : ""
  return `${location.file}${linePart}${symbolPart}`
}

const concernLabel = (value: ReviewFinding["concernArea"]) => value.replaceAll("_", "-")

const severityLabel = (value: ReviewFinding["severity"]) => {
  switch (value) {
    case "blocking":
      return "blocking"
    case "non_blocking":
      return "non-blocking"
    case "nit":
      return "nit"
  }
}

const dispositionLabel = (value: ReviewArtifact["recommendedDisposition"]) => value.replaceAll("_", " ")

const bucket = (findings: ReviewFinding[], predicate: (finding: ReviewFinding) => boolean) =>
  findings.filter(predicate)

const synthesizeExcerpt = async (artifact: ReviewArtifact, finding: ReviewFinding) => {
  if (finding.excerptHint) {
    return finding.excerptHint
  }

  const location = finding.locations[0]
  if (!location || !location.file || location.startLine === undefined) {
    return null
  }

  const baseDirectory = artifact.source.worktreeRoot ?? artifact.source.workingDirectory
  if (!baseDirectory) {
    return null
  }

  const absolute = path.resolve(baseDirectory, location.file)

  try {
    const fileContent = await readFile(absolute, "utf8")
    const lines = fileContent.split(/\r?\n/)
    const start = Math.max(location.startLine - 1, 0)
    const end = Math.min((location.endLine ?? location.startLine) + 1, lines.length)
    const excerpt = lines.slice(start, end).join("\n").trim()
    return excerpt.length > 300 ? `${excerpt.slice(0, 297)}...` : excerpt
  } catch {
    return null
  }
}

export default tool({
  description: "Render a compact terminal digest and posting plan from a persisted review artifact",
  args: {
    artifactPath: tool.schema.string().min(1).describe("Path returned by review-artifact-write"),
  },
  async execute(args) {
    const raw = await readFile(args.artifactPath, "utf8")
    const artifact = JSON.parse(raw) as ReviewArtifact

    const blocking = bucket(artifact.findings, (finding) => finding.severity === "blocking")
    const nonBlocking = bucket(artifact.findings, (finding) => finding.severity === "non_blocking")
    const nits = bucket(artifact.findings, (finding) => finding.severity === "nit")
    const inlineCandidates = bucket(
      artifact.findings,
      (finding) => finding.target === "inline_candidate" || finding.target === "either",
    )
    const summaryCandidates = bucket(
      artifact.findings,
      (finding) => finding.target === "summary_candidate" || finding.target === "either",
    )

    const hotspots = Array.from(
      new Map(
        artifact.findings
          .flatMap((finding) => finding.locations)
          .map((location) => [formatLocation(location), formatLocation(location)]),
      ).values(),
    )

    const sections: string[] = []

    sections.push(`# Review Digest`)
    sections.push(``)
    sections.push(`## Summary`)
    sections.push(`- title: ${artifact.source.title}`)
    sections.push(`- source: ${artifact.source.kind}`)
    if (artifact.source.repository) sections.push(`- repo: ${artifact.source.repository}`)
    if (artifact.source.owner && artifact.source.repo) sections.push(`- slug: ${artifact.source.owner}/${artifact.source.repo}`)
    if (artifact.source.prNumber) sections.push(`- pr: #${artifact.source.prNumber}`)
    if (artifact.source.baseRef || artifact.source.headRef) {
      sections.push(`- refs: ${artifact.source.baseRef ?? "?"} <- ${artifact.source.headRef ?? "?"}`)
    }
    if (artifact.source.baseSha || artifact.source.headSha) {
      sections.push(`- shas: ${artifact.source.baseSha ?? "?"} <- ${artifact.source.headSha ?? "?"}`)
    }
    if (artifact.source.url) sections.push(`- url: ${artifact.source.url}`)
    sections.push(`- recommended disposition: ${dispositionLabel(artifact.recommendedDisposition)}`)
    sections.push(``)
    sections.push(`## Intent`)
    sections.push(artifact.intentSummary)
    sections.push(``)
    sections.push(`## Overall assessment`)
    sections.push(artifact.overallAssessment)
    sections.push(``)
    sections.push(`## Hotspots`)
    if (hotspots.length === 0) {
      sections.push(`- none recorded`)
    } else {
      hotspots.forEach((hotspot) => sections.push(`- ${hotspot}`))
    }

    const appendFindings = async (title: string, findings: ReviewFinding[]) => {
      sections.push(``)
      sections.push(`## ${title}`)
      if (findings.length === 0) {
        sections.push(`- none`)
        return
      }

      for (const finding of findings) {
        sections.push(`- [${severityLabel(finding.severity)} | ${concernLabel(finding.concernArea)} | ${finding.target}] ${finding.summary}`)
        sections.push(`  rationale: ${finding.rationale}`)
        if (finding.locations.length > 0) {
          sections.push(`  locations: ${finding.locations.map(formatLocation).join(", ")}`)
        }
        if (finding.suggestedChange) {
          sections.push(`  suggested change: ${finding.suggestedChange}`)
        }
        const excerpt = await synthesizeExcerpt(artifact, finding)
        if (excerpt) {
          sections.push(`  excerpt:`)
          excerpt.split("\n").forEach((line) => sections.push(`    ${line}`))
        }
      }
    }

    await appendFindings("Blocking findings", blocking)
    await appendFindings("Non-blocking findings", nonBlocking)
    await appendFindings("Nits", nits)

    sections.push(``)
    sections.push(`## Draft posting plan`)
    sections.push(``)
    const githubDrafts = artifact.drafts?.github

    sections.push(`### Inline comments`)
    if (githubDrafts && githubDrafts.inline.length > 0) {
      githubDrafts.inline.forEach((draft) => {
        sections.push(`- ${formatLocation(draft.location)}: ${draft.body}`)
        if (draft.suggestedReplacement) {
          sections.push(`  suggested replacement:`)
          draft.suggestedReplacement.split("\n").forEach((line) => sections.push(`    ${line}`))
        }
      })
    } else if (inlineCandidates.length === 0) {
      sections.push(`- none`)
    } else {
      inlineCandidates.forEach((finding) => {
        const location = finding.locations[0]
        sections.push(
          `- ${location ? formatLocation(location) : finding.id}: ${finding.summary}`,
        )
      })
    }

    sections.push(``)
    sections.push(`### Top-level review notes`)
    if (githubDrafts && githubDrafts.summary.length > 0) {
      githubDrafts.summary.forEach((entry) => {
        sections.push(`- ${entry}`)
      })
      if (githubDrafts.reviewBody) {
        sections.push(``)
        sections.push(`### Draft review body`)
        sections.push(githubDrafts.reviewBody)
      }
    } else if (summaryCandidates.length === 0) {
      sections.push(`- none`)
    } else {
      summaryCandidates.forEach((finding) => {
        sections.push(`- ${finding.summary}`)
      })
    }

    sections.push(``)
    sections.push(`### Recommended review state`)
    sections.push(`- ${githubDrafts?.recommendedState?.replaceAll("_", " ").toLowerCase() ?? dispositionLabel(artifact.recommendedDisposition)}`)

    return sections.join("\n")
  },
})
