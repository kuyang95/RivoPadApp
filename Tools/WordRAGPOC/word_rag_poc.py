#!/usr/bin/env python3
"""Non-AI paragraph retrieval POC for long Word-like documents.

This intentionally implements only the proposed first-pass baseline:
local keyword scoring, heading boosts, rare-term boosts, and neighbor expansion.
It does not use an LLM, embeddings, synonyms, or benchmark-specific aliases.
"""

from __future__ import annotations

import argparse
import json
import math
import re
import statistics
import sys
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


STOPWORDS = {
    "ai", "excel", "xlsx", "값", "것", "관련", "검색", "검색해줘", "검색해주세요",
    "그", "내역", "데이터", "문서", "뭐야", "무엇", "보여줘", "보여주세요", "시트",
    "알려줘", "알려주세요", "어디", "어떤", "엑셀", "에서", "있는", "좀", "중",
    "찾아", "찾아줘", "찾아주세요", "표", "해줘", "해주세요", "행", "항목",
}

PARTICLES = (
    "으로", "에서", "에게", "부터", "까지", "처럼", "보다", "하고",
    "과", "와", "을", "를", "은", "는", "이", "가", "의", "에", "로", "도", "만",
)

TOKEN_RE = re.compile(r"[0-9A-Za-z가-힣_.-]+")
PAGE_NUMBER_RE = re.compile(r"^(?:-\s*)?\d+(?:\s*-)?$")
HEADING_RE = re.compile(
    r"^(?:"
    r"제\s*\d+\s*(?:편|장|절|관|조)"
    r"|[ⅠⅡⅢⅣⅤⅥⅦⅧⅨⅩ]+\s+"
    r"|\d+(?:-\d+)?[.)]\s+"
    r"|(?:BOX|Box|요약|경제전망|대내외 여건|경상수지|물가|고용)\b"
    r")"
)


@dataclass(frozen=True)
class Paragraph:
    index: int
    page: int
    heading: str
    text: str


@dataclass(frozen=True)
class ScoredParagraph:
    paragraph: Paragraph
    score: float
    matched_terms: tuple[str, ...]


def normalize_space(value: str) -> str:
    return re.sub(r"\s+", " ", value).strip()


def normalize_search(value: str) -> str:
    return normalize_space(value).casefold()


def tokenize_query(question: str) -> list[str]:
    terms: list[str] = []
    seen: set[str] = set()
    for raw in TOKEN_RE.findall(question.casefold()):
        token = raw.strip("-_.")
        if not token or token in STOPWORDS:
            continue
        for particle in PARTICLES:
            if token.endswith(particle) and len(token) > len(particle) + 1:
                token = token[: -len(particle)]
                break
        if len(token) < 2 or token in STOPWORDS or token in seen:
            continue
        seen.add(token)
        terms.append(token)
        if len(terms) == 8:
            break
    return terms


def is_heading(text: str) -> bool:
    return len(text) <= 140 and bool(HEADING_RE.match(text))


def parse_pdf_text(raw: str) -> list[Paragraph]:
    """Make paragraph-like units while retaining realistic PDF extraction noise."""
    paragraphs: list[Paragraph] = []
    current_heading = ""
    page = 1
    index = 0

    for page_text in raw.split("\f"):
        for raw_block in re.split(r"\n\s*\n", page_text):
            lines = [normalize_space(line) for line in raw_block.splitlines()]
            lines = [line for line in lines if line and not PAGE_NUMBER_RE.fullmatch(line)]
            text = normalize_space(" ".join(lines))
            if not text:
                continue
            if is_heading(text):
                current_heading = text[:140]
            elif HEADING_RE.match(text):
                heading_match = re.match(r"^(.{1,80}?(?:\)|\]|\.|\s))", text)
                if heading_match:
                    current_heading = heading_match.group(1).strip()
            paragraphs.append(Paragraph(index=index, page=page, heading=current_heading, text=text))
            index += 1
        page += 1
    return paragraphs


def document_frequencies(paragraphs: Iterable[Paragraph], terms: Iterable[str]) -> Counter[str]:
    frequencies: Counter[str] = Counter()
    normalized = [normalize_search(p.text) for p in paragraphs]
    for term in terms:
        frequencies[term] = sum(1 for text in normalized if term in text)
    return frequencies


def score_paragraphs(paragraphs: list[Paragraph], terms: list[str]) -> list[ScoredParagraph]:
    if not terms:
        return []
    frequencies = document_frequencies(paragraphs, terms)
    count = len(paragraphs)
    results: list[ScoredParagraph] = []

    for paragraph in paragraphs:
        text = normalize_search(paragraph.text)
        heading = normalize_search(paragraph.heading)
        matched: list[str] = []
        score = 0.0
        for term in terms:
            occurrences = text.count(term)
            if occurrences == 0:
                continue
            matched.append(term)
            inverse_frequency = math.log((count + 1) / (frequencies[term] + 1)) + 1
            score += inverse_frequency * (2.0 + min(occurrences - 1, 2) * 0.35)
            if term in heading:
                score += inverse_frequency * 2.5
            if any(ch.isdigit() for ch in term):
                score += inverse_frequency * 1.5
        coverage = len(matched) / len(terms)
        if len(matched) >= 2:
            score += 3.0 * coverage
        if len(matched) == len(terms) and len(terms) >= 2:
            score += 5.0
        if score > 0:
            results.append(
                ScoredParagraph(
                    paragraph=paragraph,
                    score=score,
                    matched_terms=tuple(matched),
                )
            )

    return sorted(results, key=lambda item: (-item.score, item.paragraph.index))


def confidence(scored: list[ScoredParagraph], terms: list[str]) -> tuple[str, float, float]:
    if not scored or not terms:
        return "low", 0.0, 0.0
    best = scored[0]
    coverage = len(best.matched_terms) / len(terms)
    runner_up = scored[1].score if len(scored) > 1 else 0.0
    margin = (best.score - runner_up) / max(best.score, 0.001)
    if coverage >= 0.75 and (best.score >= 12 or margin >= 0.20):
        level = "high"
    elif coverage >= 0.40 and best.score >= 5:
        level = "medium"
    else:
        level = "low"
    return level, coverage, margin


def expand_neighbors(
    paragraphs: list[Paragraph],
    scored: list[ScoredParagraph],
    anchor_limit: int = 10,
    neighbor_radius: int = 1,
    context_limit: int = 30,
) -> tuple[list[ScoredParagraph], list[Paragraph]]:
    anchors = scored[:anchor_limit]
    included: set[int] = set()
    for anchor in anchors:
        center = anchor.paragraph.index
        for index in range(max(0, center - neighbor_radius), min(len(paragraphs), center + neighbor_radius + 1)):
            included.add(index)
            if len(included) >= context_limit:
                break
        if len(included) >= context_limit:
            break
    return anchors, [paragraphs[index] for index in sorted(included)]


def patterns_match(patterns: list[str], paragraphs: Iterable[Paragraph]) -> bool:
    if not patterns:
        return False
    context = "\n".join(p.text for p in paragraphs)
    return all(re.search(pattern, context, flags=re.IGNORECASE | re.DOTALL) for pattern in patterns)


def first_evidence_rank(patterns: list[str], anchors: list[ScoredParagraph], paragraphs: list[Paragraph]) -> int | None:
    if not patterns:
        return None
    for rank, anchor in enumerate(anchors, start=1):
        index = anchor.paragraph.index
        neighborhood = paragraphs[max(0, index - 1) : min(len(paragraphs), index + 2)]
        if patterns_match(patterns, neighborhood):
            return rank
    return None


def preview(item: ScoredParagraph, limit: int = 220) -> str:
    text = item.paragraph.text
    return text if len(text) <= limit else text[: limit - 1] + "…"


def evaluate(benchmark_path: Path, source_dir: Path) -> dict:
    benchmark = json.loads(benchmark_path.read_text(encoding="utf-8"))
    parsed_sources: dict[str, list[Paragraph]] = {}
    source_stats: dict[str, dict] = {}

    for source_id, source in benchmark["sources"].items():
        source_path = source_dir / source["text_file"]
        raw = source_path.read_text(encoding="utf-8", errors="replace")
        paragraphs = parse_pdf_text(raw)
        parsed_sources[source_id] = paragraphs
        source_stats[source_id] = {
            "title": source["title"],
            "characters": len(raw),
            "paragraphs": len(paragraphs),
            "source_url": source["source_url"],
        }

    cases: list[dict] = []
    for case in benchmark["questions"]:
        paragraphs = parsed_sources[case["source"]]
        terms = tokenize_query(case["question"])
        scored = score_paragraphs(paragraphs, terms)
        anchors, context = expand_neighbors(paragraphs, scored)
        level, coverage, margin = confidence(scored, terms)
        context_chars = sum(len(p.text) for p in context)
        source_chars = source_stats[case["source"]]["characters"]

        if case["intent"] == "retrieve":
            passed = patterns_match(case["evidence_patterns"], context)
            evidence_rank = first_evidence_rank(case["evidence_patterns"], anchors, paragraphs)
            outcome = "hit" if passed else "miss"
        else:
            passed = level == "low"
            evidence_rank = None
            outcome = "clarify" if passed else "unsafe_answer"

        cases.append(
            {
                "id": case["id"],
                "source": case["source"],
                "question": case["question"],
                "intent": case["intent"],
                "difficulty": case["difficulty"],
                "terms": terms,
                "confidence": level,
                "term_coverage": round(coverage, 3),
                "score_margin": round(margin, 3),
                "outcome": outcome,
                "passed": passed,
                "evidence_anchor_rank": evidence_rank,
                "anchor_count": len(anchors),
                "context_paragraphs": len(context),
                "context_characters": context_chars,
                "source_characters": source_chars,
                "context_ratio": round(context_chars / max(source_chars, 1), 5),
                "top_results": [
                    {
                        "rank": rank,
                        "score": round(item.score, 3),
                        "page": item.paragraph.page,
                        "matched_terms": list(item.matched_terms),
                        "heading": item.paragraph.heading,
                        "preview": preview(item),
                    }
                    for rank, item in enumerate(anchors[:5], start=1)
                ],
            }
        )

    retrieval_cases = [case for case in cases if case["intent"] == "retrieve"]
    clarify_cases = [case for case in cases if case["intent"] == "clarify"]
    hits = sum(case["passed"] for case in retrieval_cases)
    safe_clarifications = sum(case["passed"] for case in clarify_cases)
    ratios = [case["context_ratio"] for case in cases]
    context_sizes = [case["context_characters"] for case in cases]

    return {
        "configuration": {
            "runtime_ai_calls": 0,
            "anchor_limit": 10,
            "neighbor_radius": 1,
            "context_limit": 30,
            "max_query_terms": 8,
            "features": ["keyword", "heading_boost", "rare_term_boost", "numeric_boost", "neighbor_expansion"],
            "excluded": ["llm", "embedding", "synonym_dictionary", "morphological_analyzer", "reranker"],
        },
        "sources": source_stats,
        "summary": {
            "questions": len(cases),
            "retrieval_questions": len(retrieval_cases),
            "retrieval_hits": hits,
            "retrieval_recall": round(hits / max(len(retrieval_cases), 1), 3),
            "clarification_questions": len(clarify_cases),
            "safe_clarifications": safe_clarifications,
            "unsafe_ambiguity_answers": len(clarify_cases) - safe_clarifications,
            "overall_passes": hits + safe_clarifications,
            "median_context_characters": int(statistics.median(context_sizes)),
            "median_context_ratio": round(statistics.median(ratios), 5),
        },
        "cases": cases,
    }


def print_markdown(result: dict) -> None:
    summary = result["summary"]
    print(
        f"Retrieval: {summary['retrieval_hits']}/{summary['retrieval_questions']} | "
        f"safe clarification: {summary['safe_clarifications']}/{summary['clarification_questions']} | "
        f"overall: {summary['overall_passes']}/{summary['questions']}"
    )
    print("| ID | result | confidence | evidence rank | context/source | query |")
    print("|---|---|---:|---:|---:|---|")
    for case in result["cases"]:
        rank = case["evidence_anchor_rank"] or "-"
        ratio = f"{case['context_ratio'] * 100:.2f}%"
        print(
            f"| {case['id']} | {case['outcome']} | {case['confidence']} | "
            f"{rank} | {ratio} | {case['question']} |"
        )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--benchmark", type=Path, default=Path(__file__).with_name("benchmark.json"))
    parser.add_argument("--source-dir", type=Path, required=True)
    parser.add_argument("--format", choices=("json", "markdown"), default="json")
    args = parser.parse_args()

    try:
        result = evaluate(args.benchmark, args.source_dir)
    except (OSError, ValueError, KeyError) as error:
        print(f"POC failed: {error}", file=sys.stderr)
        return 1

    if args.format == "markdown":
        print_markdown(result)
    else:
        json.dump(result, sys.stdout, ensure_ascii=False, indent=2)
        print()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
