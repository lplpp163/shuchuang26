#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Build the Vietnamese native-speaker review page and portable packet.

The generator binds three independent things:

* the exact 119-file Piper manifest (bytes and SHA-256 included);
* the current Flutter runtime usage catalog (Chinese intent and context); and
* a blank reviewer instrument whose decisions remain local until export.

Creating the page or ZIP never counts as human review evidence.
"""

from __future__ import annotations

import argparse
import hashlib
import html
import json
import os
import re
import shutil
import subprocess
import tempfile
import zipfile
from collections import defaultdict
from pathlib import Path
from typing import Any


FLUTTER_ROOT = Path(__file__).resolve().parents[1]
PROJECT_ROOT = FLUTTER_ROOT.parents[1]
DEFAULT_MANIFEST = FLUTTER_ROOT / "assets" / "audio" / "piper_generation_manifest.json"
DEFAULT_OUTPUT = (
    PROJECT_ROOT
    / "交付成果"
    / "語言審閱"
    / "傳家話_越南語119句母語審閱工具.html"
)
DEFAULT_CONTEXT_NAME = "傳家話_越南語119句語境目錄.json"
DEFAULT_ZIP_NAME = "傳家話_越南語119句母語審閱可攜包.zip"
CONTEXT_SCHEMA = "our-family-says/native-review-context/v1"
EVIDENCE_SCHEMA = "our-family-says/native-review/v2"


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest().upper()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest().upper()


def json_for_script(value: Any) -> str:
    """Serialize data without permitting an HTML raw-text closing sequence."""

    return (
        json.dumps(value, ensure_ascii=False, separators=(",", ":"))
        .replace("&", "\\u0026")
        .replace("<", "\\u003c")
        .replace(">", "\\u003e")
        .replace("\u2028", "\\u2028")
        .replace("\u2029", "\\u2029")
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--manifest",
        type=Path,
        default=DEFAULT_MANIFEST,
        help="Piper manifest to bind (default: project assets/audio manifest).",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=DEFAULT_OUTPUT,
        help="Generated HTML path.",
    )
    parser.add_argument(
        "--audio-prefix",
        default="auto",
        help=(
            "Prefix prepended to manifest paths. 'auto' supports the canonical "
            "deliverables route and the full workspace offline layout."
        ),
    )
    parser.add_argument(
        "--flutter-root",
        type=Path,
        default=FLUTTER_ROOT,
        help="Flutter project root used for assets and context extraction.",
    )
    parser.add_argument(
        "--context-catalog",
        type=Path,
        help="Reuse a previously generated context catalog instead of running Flutter.",
    )
    parser.add_argument(
        "--context-output",
        type=Path,
        help="Context catalog output (default: beside HTML).",
    )
    parser.add_argument(
        "--zip-output",
        type=Path,
        help="Portable ZIP output (default: beside HTML).",
    )
    parser.add_argument(
        "--no-zip",
        action="store_true",
        help="Generate HTML and context catalog without the portable ZIP.",
    )
    parser.add_argument(
        "--flutter",
        type=Path,
        help="Explicit Flutter executable used to read runtime catalogs.",
    )
    return parser.parse_args()


def validate_manifest(manifest_path: Path, flutter_root: Path) -> tuple[dict[str, Any], bytes, list[dict[str, Any]]]:
    raw = manifest_path.read_bytes()
    manifest = json.loads(raw.decode("utf-8-sig"))
    files = manifest.get("files")
    if not isinstance(files, list) or len(files) != 119:
        count = len(files) if isinstance(files, list) else "not-a-list"
        raise SystemExit(f"Expected 119 manifest records, found {count}")

    path_pattern = re.compile(r"^assets/audio/[A-Za-z0-9._-]+\.mp3$")
    seen: set[str] = set()
    normalized: list[dict[str, Any]] = []
    for index, raw_record in enumerate(files, start=1):
        if not isinstance(raw_record, dict):
            raise SystemExit(f"Manifest record {index} is not an object")
        path = raw_record.get("path")
        text = raw_record.get("text")
        byte_count = raw_record.get("bytes")
        declared_hash = raw_record.get("sha256")
        if not isinstance(path, str) or not path_pattern.fullmatch(path):
            raise SystemExit(f"Unsafe or invalid manifest path at record {index}: {path!r}")
        folded = path.casefold()
        if folded in seen:
            raise SystemExit(f"Duplicate manifest path: {path}")
        seen.add(folded)
        if not isinstance(text, str) or not text.strip():
            raise SystemExit(f"Manifest text is blank for {path}")
        if isinstance(byte_count, bool) or not isinstance(byte_count, int) or byte_count <= 0:
            raise SystemExit(f"Manifest bytes are invalid for {path}")
        if not isinstance(declared_hash, str) or not re.fullmatch(r"[A-Fa-f0-9]{64}", declared_hash):
            raise SystemExit(f"Manifest SHA-256 is invalid for {path}")

        audio_path = (flutter_root / Path(*path.split("/"))).resolve()
        audio_root = (flutter_root / "assets" / "audio").resolve()
        if audio_path.parent != audio_root:
            raise SystemExit(f"Manifest path escaped assets/audio: {path}")
        if not audio_path.is_file():
            raise SystemExit(f"Manifest audio is missing: {audio_path}")
        if audio_path.stat().st_size != byte_count:
            raise SystemExit(f"Manifest byte count drifted: {path}")
        actual_hash = sha256_file(audio_path)
        if actual_hash != declared_hash.upper():
            raise SystemExit(f"Manifest SHA-256 drifted: {path}")
        normalized.append(
            {
                "path": path,
                "text": text,
                "bytes": byte_count,
                "sha256": declared_hash.upper(),
            }
        )

    actual_mp3 = {p.name.casefold() for p in (flutter_root / "assets" / "audio").glob("*.mp3")}
    manifest_mp3 = {Path(record["path"]).name.casefold() for record in normalized}
    if actual_mp3 != manifest_mp3:
        missing = sorted(manifest_mp3 - actual_mp3)
        extra = sorted(actual_mp3 - manifest_mp3)
        raise SystemExit(f"Manifest/MP3 set mismatch; missing={missing}, extra={extra}")
    return manifest, raw, normalized


def find_flutter(explicit: Path | None) -> Path:
    candidates: list[Path] = []
    if explicit:
        candidates.append(explicit.expanduser())
    if os.environ.get("FLUTTER"):
        candidates.append(Path(os.environ["FLUTTER"]))
    discovered = shutil.which("flutter")
    if discovered:
        candidates.append(Path(discovered))
    sdk_root = os.environ.get("FLUTTER_ROOT")
    if sdk_root:
        candidates.extend([Path(sdk_root) / "bin" / "flutter.bat", Path(sdk_root) / "bin" / "flutter"])
    if os.name == "nt":
        candidates.append(Path(r"C:\tools\flutter\bin\flutter.bat"))
    for candidate in candidates:
        resolved = candidate.resolve()
        if resolved.is_file():
            return resolved
    raise SystemExit(
        "Flutter executable not found. Pass --flutter, set FLUTTER/FLUTTER_ROOT, "
        "or pass --context-catalog from a previously verified generation."
    )


RUNTIME_CONTEXT_TEST = r"""
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hometongue_tags/models/conversation_episode.dart';
import 'package:hometongue_tags/services/app_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('export native review context catalog', () async {
    final usages = <Map<String, Object?>>[];
    String relative(String value) => value.startsWith('asset://')
        ? value.substring('asset://'.length)
        : value;

    void theaterUsage({
      required ConversationEpisode episode,
      required ConversationPrompt prompt,
      required ConversationLine line,
      required String usageType,
      required String semanticSpeaker,
      required String semanticListener,
      required String usageContext,
      ConversationChoice? choice,
    }) {
      usages.add({
        'path': relative(line.audioPath!),
        'targetText': line.targetText,
        'translationZh': line.translationZh,
        'episodeId': episode.id,
        'episodeTitleZh': episode.title,
        'act': prompt.step,
        'lessonStage': null,
        'promptId': prompt.id,
        'choiceId': choice?.id,
        'usageType': usageType,
        'semanticSpeakerZh': semanticSpeaker,
        'semanticListenerZh': semanticListener,
        'kinshipZh': episode.elderName,
        'relationshipKnown': true,
        'usageContextZh': usageContext,
        'sourceReference': 'lib/models/conversation_episode.dart',
      });
    }

    for (final episode in ConversationEpisodeCatalog.defaults) {
      for (final prompt in episode.prompts) {
        theaterUsage(
          episode: episode,
          prompt: prompt,
          line: prompt.elderLine,
          usageType: 'elder_prompt',
          semanticSpeaker: episode.elderName,
          semanticListener: '孩子／孫輩',
          usageContext: prompt.stageDirectionZh,
        );
        for (final choice in prompt.choices) {
          theaterUsage(
            episode: episode,
            prompt: prompt,
            line: choice.line,
            usageType: 'child_choice',
            semanticSpeaker: '孩子／孫輩',
            semanticListener: episode.elderName,
            usageContext: prompt.stageDirectionZh,
            choice: choice,
          );
          theaterUsage(
            episode: episode,
            prompt: prompt,
            line: choice.elderReply,
            usageType: 'elder_reply',
            semanticSpeaker: episode.elderName,
            semanticListener: '孩子／孫輩',
            usageContext: choice.storyBeatZh,
            choice: choice,
          );
        }
      }
    }

    SharedPreferences.setMockInitialValues({});
    final store = await AppStore.load();
    for (final story in store.stories.where((story) => story.isSample)) {
      void curriculumUsage({
        required String path,
        required String targetText,
        required String translationZh,
        required String lessonStage,
        required String usageType,
        required String usageContext,
        required String sourceReference,
      }) {
        usages.add({
          'path': relative(path),
          'targetText': targetText,
          'translationZh': translationZh,
          'episodeId': story.id,
          'episodeTitleZh': story.title,
          'act': null,
          'lessonStage': lessonStage,
          'promptId': null,
          'choiceId': null,
          'usageType': usageType,
          // The curriculum data does not structurally encode semantic roles.
          // Do not infer them from the sample voice persona or filename.
          'semanticSpeakerZh': null,
          'semanticListenerZh': null,
          'kinshipZh': null,
          'relationshipKnown': false,
          'usageContextZh': usageContext,
          'sourceReference': sourceReference,
        });
      }

      if (story.audioPath case final path?) {
        curriculumUsage(
          path: path,
          targetText: story.vietnamese,
          translationZh: story.chinese,
          lessonStage: 'full_sentence',
          usageType: 'curriculum_sentence',
          usageContext: '${story.objectName}｜${story.promptZh}',
          sourceReference: 'lib/services/app_store.dart#${story.id}',
        );
      }
      final lesson = story.lessonContent;
      if (lesson != null) {
        for (final segment in lesson.segments) {
          if (segment.audio?.path case final path?) {
            curriculumUsage(
              path: path,
              targetText: segment.text,
              translationZh: segment.translationZh,
              lessonStage: 'segment',
              usageType: 'lesson_segment',
              usageContext: '${story.objectName}｜${lesson.coachIntroZh ?? story.promptZh}',
              sourceReference: 'lib/services/app_store.dart#${story.id}/segment/${segment.id}',
            );
          }
        }
        for (final pattern in lesson.patterns) {
          for (var index = 0; index < pattern.examples.length; index++) {
            final example = pattern.examples[index];
            if (example.audio?.path case final path?) {
              curriculumUsage(
                path: path,
                targetText: example.targetText,
                translationZh: example.translationZh,
                lessonStage: 'pattern_example',
                usageType: 'lesson_example',
                usageContext: '${story.objectName}｜${pattern.meaningZh}｜${pattern.usageTipZh ?? ''}',
                sourceReference: 'lib/services/app_store.dart#${story.id}/pattern/${pattern.id}/$index',
              );
            }
          }
        }
      }
    }
    File(__OUTPUT_PATH__).writeAsStringSync(jsonEncode({'usages': usages}));
  });
}
"""


def extract_runtime_contexts(flutter_root: Path, flutter_executable: Path) -> list[dict[str, Any]]:
    conversation_source = flutter_root / "lib" / "models" / "conversation_episode.dart"
    store_source = flutter_root / "lib" / "services" / "app_store.dart"
    for required in (conversation_source, store_source, flutter_root / "pubspec.yaml"):
        if not required.is_file():
            raise SystemExit(f"Context source is missing: {required}")

    with tempfile.TemporaryDirectory(prefix="native-review-context-") as temp_dir:
        temp = Path(temp_dir)
        output_path = temp / "contexts.json"
        test_path = temp / "context_catalog_test.dart"
        dart_output_literal = json.dumps(str(output_path).replace("\\", "/"))
        test_path.write_text(
            RUNTIME_CONTEXT_TEST.replace("__OUTPUT_PATH__", dart_output_literal),
            encoding="utf-8",
        )
        result = subprocess.run(
            [
                str(flutter_executable),
                "test",
                str(test_path),
                "--reporter=compact",
                "--concurrency=1",
            ],
            cwd=flutter_root,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=180,
            check=False,
        )
        if result.returncode != 0 or not output_path.is_file():
            details = (result.stdout + "\n" + result.stderr)[-6000:]
            raise SystemExit(f"Flutter context extraction failed (exit {result.returncode}):\n{details}")
        payload = json.loads(output_path.read_text(encoding="utf-8"))
    usages = payload.get("usages")
    if not isinstance(usages, list):
        raise SystemExit("Flutter context extraction did not return a usages list")
    return usages


def normalized_phrase(value: str) -> str:
    return re.sub(r"[^0-9A-Za-zÀ-ỹ]+", "", value).casefold()


def build_context_catalog(
    manifest_records: list[dict[str, Any]],
    manifest_sha256: str,
    flutter_root: Path,
    flutter_executable: Path | None,
    existing_catalog: Path | None,
) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    source_paths = [
        flutter_root / "lib" / "models" / "conversation_episode.dart",
        flutter_root / "lib" / "services" / "app_store.dart",
    ]
    source_hashes = {
        path.relative_to(flutter_root).as_posix(): sha256_file(path)
        for path in source_paths
        if path.is_file()
    }

    if existing_catalog:
        catalog = json.loads(existing_catalog.read_text(encoding="utf-8-sig"))
        if not isinstance(catalog, dict):
            raise SystemExit("Context catalog root must be an object")
        if catalog.get("schema") != CONTEXT_SCHEMA:
            raise SystemExit(f"Unsupported context catalog schema: {catalog.get('schema')!r}")
        if catalog.get("manifestSha256") != manifest_sha256:
            raise SystemExit("Context catalog is bound to a different audio manifest")
        declared_context_hash = catalog.get("contextCatalogSha256")
        if not isinstance(declared_context_hash, str) or not re.fullmatch(
            r"[A-F0-9]{64}", declared_context_hash
        ):
            raise SystemExit("Context catalog SHA-256 is missing or invalid")
        catalog_without_hash = {
            key: value for key, value in catalog.items() if key != "contextCatalogSha256"
        }
        actual_context_hash = sha256_bytes(
            json.dumps(
                catalog_without_hash,
                ensure_ascii=False,
                sort_keys=True,
                separators=(",", ":"),
            ).encode("utf-8")
        )
        if actual_context_hash != declared_context_hash:
            raise SystemExit("Context catalog SHA-256 drifted")
        if catalog.get("sourceSha256") != source_hashes:
            raise SystemExit("Context catalog source hashes do not match the current Dart sources")
        catalog_records = catalog.get("records")
        if not isinstance(catalog_records, list) or len(catalog_records) != 119:
            raise SystemExit("Context catalog must contain exactly 119 audio records")
        contexts_by_path = {}
        catalog_text_by_path: dict[str, str] = {}
        for index, catalog_record in enumerate(catalog_records, start=1):
            if not isinstance(catalog_record, dict):
                raise SystemExit(f"Context catalog record {index} is not an object")
            path = catalog_record.get("path")
            contexts = catalog_record.get("contexts")
            if not isinstance(path, str) or path in contexts_by_path:
                raise SystemExit(f"Invalid or duplicate context catalog path at record {index}: {path!r}")
            if not isinstance(contexts, list) or not contexts:
                raise SystemExit(f"Context catalog has no usages for {path}")
            text = catalog_record.get("text")
            if not isinstance(text, str) or not text:
                raise SystemExit(f"Context catalog text is invalid for {path}")
            contexts_by_path[path] = contexts
            catalog_text_by_path[path] = text
    else:
        if flutter_executable is None:
            raise SystemExit("A Flutter executable is required when --context-catalog is not supplied")
        usages = extract_runtime_contexts(flutter_root, flutter_executable)
        contexts_by_path: dict[str, list[dict[str, Any]]] = defaultdict(list)
        for usage in usages:
            if not isinstance(usage, dict) or not isinstance(usage.get("path"), str):
                raise SystemExit(f"Invalid runtime context usage: {usage!r}")
            contexts_by_path[usage["path"]].append(usage)

    manifest_by_path = {record["path"]: record for record in manifest_records}
    extra_context_paths = sorted(set(contexts_by_path) - set(manifest_by_path))
    if extra_context_paths:
        raise SystemExit(f"Runtime catalog has paths absent from manifest: {extra_context_paths}")
    missing_context_paths = sorted(set(manifest_by_path) - set(contexts_by_path))
    if missing_context_paths:
        raise SystemExit(f"Runtime catalog does not map manifest paths: {missing_context_paths}")
    if existing_catalog:
        drifted_text_paths = sorted(
            path
            for path, record in manifest_by_path.items()
            if catalog_text_by_path.get(path) != record["text"]
        )
        if drifted_text_paths:
            raise SystemExit(f"Context catalog text drifted for: {drifted_text_paths}")

    enriched: list[dict[str, Any]] = []
    context_records: list[dict[str, Any]] = []
    total_usages = 0
    unknown_relationship_paths = 0
    for record in manifest_records:
        raw_contexts = contexts_by_path.get(record["path"], [])

        unique_contexts: list[dict[str, Any]] = []
        seen_contexts: set[str] = set()
        for context in raw_contexts:
            if not isinstance(context, dict):
                raise SystemExit(f"Context usage is not an object for {record['path']}")
            if context.get("path") != record["path"]:
                raise SystemExit(f"Context usage path drifted for {record['path']}")
            target = str(context.get("targetText") or "")
            if normalized_phrase(target) != normalized_phrase(record["text"]):
                raise SystemExit(
                    f"Context target text drifted for {record['path']}: {target!r} != {record['text']!r}"
                )
            for key in ("translationZh", "episodeTitleZh", "usageType", "usageContextZh", "sourceReference"):
                if not isinstance(context.get(key), str) or not context[key].strip():
                    raise SystemExit(f"Context {key} is blank for {record['path']}")
            if not isinstance(context.get("relationshipKnown"), bool):
                raise SystemExit(f"Context relationshipKnown is invalid for {record['path']}")
            if context["relationshipKnown"] is True:
                for key in ("semanticSpeakerZh", "semanticListenerZh", "kinshipZh"):
                    if not isinstance(context.get(key), str) or not context[key].strip():
                        raise SystemExit(f"Known context {key} is blank for {record['path']}")
            canonical = json.dumps(context, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
            if canonical not in seen_contexts:
                seen_contexts.add(canonical)
                unique_contexts.append(context)
        unique_contexts.sort(
            key=lambda item: (
                str(item.get("episodeId") or ""),
                int(item.get("act") or 0),
                str(item.get("promptId") or ""),
                str(item.get("choiceId") or ""),
                str(item.get("usageType") or ""),
                str(item.get("sourceReference") or ""),
            )
        )
        meanings = sorted(
            {str(item.get("translationZh") or "").strip() for item in unique_contexts}
            - {""}
        )
        relationship_known = all(item.get("relationshipKnown") is True for item in unique_contexts)
        if not relationship_known:
            unknown_relationship_paths += 1
        register_scope = (
            "contextual-speaker-listener"
            if relationship_known
            else "explicit-markers-only; speaker/listener not structurally encoded"
        )
        total_usages += len(unique_contexts)
        enriched_record = {
            **record,
            "intendedMeaningsZh": meanings or ["未知"],
            "contexts": unique_contexts,
            "registerReviewScope": register_scope,
        }
        enriched.append(enriched_record)
        context_records.append(
            {
                "path": record["path"],
                "text": record["text"],
                "intendedMeaningsZh": enriched_record["intendedMeaningsZh"],
                "registerReviewScope": register_scope,
                "contexts": unique_contexts,
            }
        )

    catalog_without_hash = {
        "schema": CONTEXT_SCHEMA,
        "manifestSha256": manifest_sha256,
        "sourceSha256": source_hashes,
        "audioPathCount": len(context_records),
        "usageCount": total_usages,
        "unknownRelationshipPathCount": unknown_relationship_paths,
        "records": context_records,
    }
    canonical = json.dumps(
        catalog_without_hash,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
    context_sha256 = sha256_bytes(canonical)
    catalog = {**catalog_without_hash, "contextCatalogSha256": context_sha256}
    return catalog, enriched


PAGE_TEMPLATE = r"""<!doctype html>
<html lang="zh-Hant">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="color-scheme" content="light">
  <title>傳家話｜119 句越南語母語審閱</title>
  <style>
    :root { --ink:#20332f; --jade:#147f70; --jade2:#dff3ee; --cream:#fffaf1;
      --coral:#b94738; --line:#d8dfdc; --muted:#61736e; --amber:#8b5a12; }
    * { box-sizing:border-box; }
    body { margin:0; color:var(--ink); background:linear-gradient(145deg,#f7f4e9,#eef7f3);
      font:16px/1.55 system-ui,-apple-system,"Noto Sans TC",sans-serif; }
    header { padding:32px max(20px,calc((100vw - 1120px)/2)); color:white; background:var(--ink); }
    h1 { margin:0 0 8px; font-size:clamp(26px,4vw,40px); line-height:1.2; }
    header p { max-width:850px; margin:8px 0; color:#dce9e5; }
    main { max-width:1120px; margin:auto; padding:24px 20px 64px; }
    .warning,.panel,.review-card { border:1px solid var(--line); border-radius:18px; background:#fff; }
    .warning { margin-bottom:20px; padding:16px 18px; border-left:6px solid var(--coral); background:#fff1ee; }
    .panel { margin-bottom:20px; padding:20px; box-shadow:0 8px 30px rgba(31,52,47,.07); }
    .meta-grid { display:grid; grid-template-columns:repeat(auto-fit,minmax(220px,1fr)); gap:14px; }
    label { display:block; font-weight:700; }
    input,select,textarea,button { font:inherit; }
    input,select,textarea { width:100%; min-height:46px; margin-top:6px; padding:10px 12px;
      color:var(--ink); background:white; border:1px solid #aebbb7; border-radius:11px; }
    textarea { min-height:78px; resize:vertical; }
    .attestations { display:grid; gap:8px; margin-top:14px; padding:12px; background:var(--cream); border-radius:12px; }
    .attestations label,.radio-row label { display:flex; gap:9px; align-items:flex-start; }
    .attestations input,.radio-row input { width:22px; min-height:22px; margin:2px 0 0; flex:none; }
    .toolbar { position:sticky; top:0; z-index:5; display:flex; flex-wrap:wrap; gap:10px;
      align-items:center; margin-bottom:16px; padding:12px; border:1px solid var(--line);
      border-radius:15px; background:rgba(255,250,241,.97); backdrop-filter:blur(8px); }
    button { min-height:46px; padding:10px 16px; color:white; font-weight:800; cursor:pointer;
      background:var(--jade); border:0; border-radius:12px; }
    button.secondary { color:var(--jade); background:white; border:1px solid var(--jade); }
    button.danger { color:#92382d; background:white; border:1px solid #cf8f86; }
    button:disabled { cursor:not-allowed; opacity:.45; filter:grayscale(.5); }
    .progress { flex:1 1 250px; font-weight:800; }
    progress { width:100%; height:12px; accent-color:var(--jade); }
    .filters { display:flex; flex-wrap:wrap; gap:10px; margin-bottom:16px; }
    .filters button[aria-pressed="true"] { background:var(--ink); }
    .review-card { margin-bottom:14px; padding:18px; box-shadow:0 4px 18px rgba(31,52,47,.05); }
    .review-card.pass { border-left:7px solid var(--jade); }
    .review-card.revise { border-left:7px solid var(--coral); }
    .card-head { display:flex; gap:12px; align-items:flex-start; }
    .index { display:inline-grid; min-width:42px; height:42px; place-items:center; color:white;
      font-weight:900; background:var(--ink); border-radius:50%; }
    .phrase { min-width:0; flex:1; }
    .phrase strong { display:block; font-size:22px; line-height:1.35; }
    .path { color:var(--muted); font:12px/1.4 ui-monospace,SFMono-Regular,Consolas,monospace;
      overflow-wrap:anywhere; }
    .context-box { margin:14px 0; padding:14px; background:#f2f8f6; border-radius:14px; }
    .context-box h3 { margin:0 0 8px; font-size:16px; }
    .meaning { margin:6px 0; font-weight:800; }
    .scope { display:inline-flex; margin:4px 0; padding:4px 9px; color:#075b4f; font-size:13px;
      font-weight:800; background:var(--jade2); border-radius:999px; }
    .scope.limited { color:#71470b; background:#fff0c9; }
    details { margin-top:8px; }
    .usage { margin:8px 0 0; padding:10px 12px; background:white; border-left:4px solid #8ebbb1; border-radius:8px; }
    .usage p { margin:3px 0; }
    audio { width:100%; min-height:48px; margin:4px 0 8px; }
    .playback-state { display:inline-flex; min-height:34px; align-items:center; margin-bottom:10px;
      padding:5px 11px; color:var(--amber); font-weight:800; background:#fff0c9; border-radius:999px; }
    .playback-state.played { color:#075b4f; background:var(--jade2); }
    .criteria { display:grid; grid-template-columns:repeat(auto-fit,minmax(235px,1fr)); gap:10px; }
    fieldset { min-width:0; margin:0; padding:12px; background:var(--cream); border:1px solid var(--line); border-radius:12px; }
    legend { padding:0 4px; font-weight:800; }
    .radio-row { display:flex; gap:18px; margin-top:8px; }
    .row { display:grid; grid-template-columns:minmax(180px,.7fr) minmax(260px,2fr); gap:12px; margin-top:12px; }
    .status { display:flex; gap:8px; margin-top:12px; }
    .status button { flex:1; }
    .pass-btn { color:#075b4f; background:var(--jade2); border:1px solid #79b9aa; }
    .revise-btn { color:#963a2f; background:#fff0ed; border:1px solid #e3a096; }
    .status button[aria-pressed="true"] { outline:3px solid var(--ink); outline-offset:2px; }
    .decision-hint,.small { color:var(--muted); font-size:14px; }
    .hidden { display:none!important; }
    code { overflow-wrap:anywhere; }
    @media(max-width:650px) { .row { grid-template-columns:1fr; } .card-head { align-items:center; } }
    @media print { header,.toolbar,.filters { display:none!important; } body { background:white; }
      main { padding:0; } .review-card { break-inside:avoid; box-shadow:none; } }
  </style>
</head>
<body>
  <header>
    <h1>119 句越南語母語審閱</h1>
    <p>逐檔聽完目前交付音訊，再依可追溯的中文意圖與使用語境，分開判斷文字、稱謂／禮貌線索與合成音訊。草稿只留在這台裝置。</p>
  </header>
  <main>
    <div class="warning" role="note"><strong>證據邊界：</strong>這是一份空白真人審閱工具，不是審閱成果。課程素材沒有結構化記錄說話者與聽者時，工具會明示「未知」，稱謂題只涵蓋句內明示線索；不能外推成所有家庭的標準說法。</div>
    <section class="panel" aria-labelledby="review-meta-title">
      <h2 id="review-meta-title">審閱資料</h2>
      <div class="meta-grid">
        <label>匿名審閱者代碼<input id="reviewerCode" autocomplete="off" pattern="R[0-9A-Z]{2,8}" maxlength="9" placeholder="例如 R01；只填代碼"></label>
        <label>審閱日期<input id="reviewDate" type="date"></label>
        <label>主要越南語使用地區／家庭用語<input id="languageContext" autocomplete="off" maxlength="80" placeholder="例如：胡志明市家庭用語"></label>
        <label>與 6–12 歲兒童互動經驗<select id="childExperience"><option value="">請選擇</option><option>經常</option><option>偶爾</option><option>很少</option><option>沒有</option></select></label>
      </div>
      <label style="margin-top:14px">審閱範圍或限制<textarea id="reviewLimits" maxlength="500" placeholder="例如：只評估南部家庭口語；未評估教科書標準音"></textarea></label>
      <div class="attestations">
        <label><input id="nativeSpeakerAttestation" type="checkbox">我本人是越南語母語成人，並由本人完成本次逐檔判定</label>
        <label><input id="anonymousUseConsent" type="checkbox">我同意團隊以匿名代碼保存與彙整本次審閱紀錄</label>
      </div>
      <p class="small">請勿填姓名、電話、地址、電子郵件、學校或社群帳號。匿名代碼格式為 R 加 2–8 位大寫英數字。</p>
      <p class="small">模型：__MODEL_HTML__；產生器：__GENERATOR_HTML__<br>音訊 manifest SHA-256：<code>__MANIFEST_SHA__</code><br>語境目錄 SHA-256：<code>__CONTEXT_SHA__</code></p>
    </section>
    <div class="toolbar" aria-label="審閱工具列">
      <div class="progress"><span id="progressText">已判定 0／119</span><progress id="progressBar" max="119" value="0"></progress></div>
      <button type="button" id="exportJson">匯出 JSON 紀錄</button>
      <button type="button" id="exportCsv" class="secondary">匯出 CSV 摘要</button>
      <button type="button" id="resetDraft" class="danger">清除本機草稿</button>
    </div>
    <div class="filters" aria-label="篩選">
      <button type="button" data-filter="all" aria-pressed="true">全部 119</button>
      <button type="button" data-filter="blank" aria-pressed="false">未判定</button>
      <button type="button" data-filter="revise" aria-pressed="false">需修訂</button>
      <button type="button" data-filter="pass" aria-pressed="false">可保留</button>
    </div>
    <section id="reviews" aria-live="polite"></section>
  </main>
  <script>
  (() => {
    'use strict';
    const manifestFiles = __RECORDS_JSON__;
    const manifestSha256 = '__MANIFEST_SHA__';
    const contextCatalogSha256 = '__CONTEXT_SHA__';
    const contextSourceSha256 = __CONTEXT_SOURCES_JSON__;
    const evidenceSchema = '__EVIDENCE_SCHEMA__';
    const storageKey = 'our-family-says-native-review-' + manifestSha256.slice(0,12) + '-' + contextCatalogSha256.slice(0,12);
    const audioPrefix = __AUDIO_PREFIX_JS__;
    const metaIds = ['reviewerCode','reviewDate','languageContext','childExperience','reviewLimits','nativeSpeakerAttestation','anonymousUseConsent'];
    const criteria = ['textNatural','familyRegister','audioClear'];
    let draft = loadDraft();
    let activeFilter = 'all';

    function emptyDraft() { return {meta:{},reviews:{}}; }
    function loadDraft() {
      try {
        const parsed = JSON.parse(localStorage.getItem(storageKey) || 'null');
        return {meta:parsed && typeof parsed.meta==='object' && parsed.meta ? parsed.meta : {},
          reviews:parsed && typeof parsed.reviews==='object' && parsed.reviews ? parsed.reviews : {}};
      } catch (_) { return emptyDraft(); }
    }
    function saveDraft() { localStorage.setItem(storageKey,JSON.stringify(draft)); updateProgress(); }
    function escaped(value) { const d=document.createElement('div'); d.textContent=value ?? ''; return d.innerHTML; }
    function reviewFor(path) {
      if (!draft.reviews[path]) draft.reviews[path]={textNatural:'',familyRegister:'',audioClear:'',rating:'',correction:'',notes:'',status:'',played:false,playCount:0,lastPlayedAt:'',lastDurationSeconds:null};
      return draft.reviews[path];
    }
    function contextMarkup(item) {
      const limited=item.registerReviewScope.startsWith('explicit-markers-only');
      const usages=item.contexts.map((c,i)=>`<div class="usage" data-context-index="${i}">
        <p><strong>${escaped(c.episodeTitleZh || '未知情境')}</strong> · ${c.act ? `第 ${c.act} 幕` : escaped(c.lessonStage || '未標示階段')} · ${escaped(c.usageType)}</p>
        <p>中文意圖：${escaped(c.translationZh || '未知')}</p>
        <p>說話者 → 聽者／親屬：${c.relationshipKnown ? `${escaped(c.semanticSpeakerZh)} → ${escaped(c.semanticListenerZh)}（${escaped(c.kinshipZh)}）` : '未知；現有課程資料未結構化標示'}</p>
        <p>使用情境：${escaped(c.usageContextZh || '未知')}</p>
        <p class="small">來源：<code>${escaped(c.sourceReference || 'unknown')}</code></p></div>`).join('');
      return `<div class="context-box"><h3>可追溯語境</h3>
        <p class="meaning">中文意圖：${item.intendedMeaningsZh.map(escaped).join('／')}</p>
        <span class="scope${limited?' limited':''}">${limited?'稱謂題僅限句內明示線索':'可依說話者／聽者語境審閱稱謂'}</span>
        <details${item.contexts.length===1?' open':''}><summary>${item.contexts.length} 個實際使用位置</summary>${usages}</details></div>`;
    }
    function criterionMarkup(key,label,r,index) {
      const checked=value=>r[key]===value?' checked':'';
      return `<fieldset data-criterion="${key}"><legend>${label}</legend><div class="radio-row">
        <label><input type="radio" name="${key}-${index}" data-key="${key}" value="yes"${checked('yes')}>是</label>
        <label><input type="radio" name="${key}-${index}" data-key="${key}" value="no"${checked('no')}>否</label></div></fieldset>`;
    }
    function eligibility(r) {
      const answered=criteria.every(key=>r[key]==='yes'||r[key]==='no');
      const anyNo=criteria.some(key=>r[key]==='no');
      const rated=/^[1-5]$/.test(String(r.rating));
      const explained=String(r.correction||'').trim().length>0||String(r.notes||'').trim().length>0;
      return {pass:r.played&&answered&&!anyNo&&rated,revise:r.played&&answered&&anyNo&&rated&&explained};
    }
    function cardMarkup(item,index) {
      const r=reviewFor(item.path); const allowed=eligibility(r);
      const pressed=status=>r.status===status?'true':'false';
      return `<article class="review-card ${escaped(r.status)}" data-path="${escaped(item.path)}" data-status="${escaped(r.status||'blank')}" data-bytes="${item.bytes}" data-sha256="${escaped(item.sha256)}">
        <div class="card-head"><span class="index">${index+1}</span><div class="phrase"><strong lang="vi">${escaped(item.text)}</strong><span class="path">${escaped(item.path)} · ${item.bytes} bytes · ${escaped(item.sha256.slice(0,12))}…</span></div></div>
        ${contextMarkup(item)}
        <audio controls preload="none" data-review-audio src="${escaped(audioPrefix+item.path)}"><span>瀏覽器無法播放此音檔。</span></audio>
        <span class="playback-state${r.played?' played':''}" data-playback-state>${r.played?`已完整播放 ${r.playCount} 次`:'尚未完整播放；聽完才可判定'}</span>
        <div class="criteria">
          ${criterionMarkup('textNatural','文字符合上列中文意圖，且在所示情境自然？',r,index)}
          ${criterionMarkup('familyRegister',item.registerReviewScope.startsWith('explicit-markers-only')?'單看句內明示的稱謂／禮貌詞，是否沒有明顯衝突？':'依說話者、聽者與親屬語境，稱謂／禮貌層級合適？',r,index)}
          ${criterionMarkup('audioClear','合成音訊可清楚理解，且沒有影響辨義的錯音？',r,index)}
        </div>
        <div class="row"><label>合成語音自然度（1 很不自然；5 很自然）<select data-key="rating"><option value="">未評</option>${[1,2,3,4,5].map(n=>`<option value="${n}"${String(n)===String(r.rating)?' selected':''}>${n}</option>`).join('')}</select></label>
        <label>建議修訂<textarea data-key="correction" maxlength="800" placeholder="請寫修訂後越南語、分段或重錄建議">${escaped(r.correction)}</textarea></label></div>
        <label style="margin-top:12px">理由／地區差異備註<textarea data-key="notes" maxlength="1200" placeholder="若選『否』，建議修訂或理由至少填一項">${escaped(r.notes)}</textarea></label>
        <p class="decision-hint" data-decision-hint></p>
        <div class="status"><button type="button" class="pass-btn" data-set-status="pass" aria-pressed="${pressed('pass')}"${allowed.pass?'':' disabled'}>可保留</button><button type="button" class="revise-btn" data-set-status="revise" aria-pressed="${pressed('revise')}"${allowed.revise?'':' disabled'}>需要修訂</button></div>
      </article>`;
    }
    function setStatusVisual(card,r) {
      card.dataset.status=r.status||'blank'; card.className='review-card '+r.status;
      card.querySelectorAll('[data-set-status]').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.setStatus===r.status)));
    }
    function refreshCard(card,clearInvalid=true) {
      const r=reviewFor(card.dataset.path); const allowed=eligibility(r);
      if (clearInvalid&&((r.status==='pass'&&!allowed.pass)||(r.status==='revise'&&!allowed.revise))) r.status='';
      card.querySelector('[data-set-status="pass"]').disabled=!allowed.pass;
      card.querySelector('[data-set-status="revise"]').disabled=!allowed.revise;
      const hint=card.querySelector('[data-decision-hint]');
      if (!r.played) hint.textContent='先完整播放音檔。';
      else if (!criteria.every(k=>r[k]==='yes'||r[k]==='no')) hint.textContent='三項都必須明確選「是」或「否」。';
      else if (!/^[1-5]$/.test(String(r.rating))) hint.textContent='請填 1–5 自然度。';
      else if (criteria.some(k=>r[k]==='no')&&!String(r.correction||'').trim()&&!String(r.notes||'').trim()) hint.textContent='選「否」時，建議修訂或理由至少填一項。';
      else hint.textContent=criteria.some(k=>r[k]==='no')?'可判定「需要修訂」。':'可判定「可保留」。';
      setStatusVisual(card,r);
    }
    function render() { document.getElementById('reviews').innerHTML=manifestFiles.map(cardMarkup).join(''); document.querySelectorAll('.review-card').forEach(c=>refreshCard(c,false)); applyFilter(); updateProgress(); }
    function updateProgress() {
      const values=manifestFiles.map(item=>reviewFor(item.path));
      const judged=values.filter(r=>r.status==='pass'||r.status==='revise').length;
      const revise=values.filter(r=>r.status==='revise').length;
      const played=values.filter(r=>r.played).length;
      document.getElementById('progressText').textContent=`已聽完 ${played}／119 · 已判定 ${judged}／119 · 需修訂 ${revise}`;
      document.getElementById('progressBar').value=judged;
    }
    function applyFilter() { document.querySelectorAll('.review-card').forEach(card=>card.classList.toggle('hidden',activeFilter!=='all'&&(card.dataset.status||'blank')!==activeFilter)); }
    metaIds.forEach(id=>{const element=document.getElementById(id);if(element.type==='checkbox')element.checked=draft.meta[id]===true;else element.value=draft.meta[id]||'';element.addEventListener('input',()=>{draft.meta[id]=element.type==='checkbox'?element.checked:element.value;saveDraft();});});
    document.getElementById('reviews').addEventListener('play',event=>{if(!event.target.matches('[data-review-audio]'))return;document.querySelectorAll('[data-review-audio]').forEach(a=>{if(a!==event.target&&!a.paused)a.pause();});},true);
    document.getElementById('reviews').addEventListener('ended',event=>{if(!event.target.matches('[data-review-audio]')||!event.target.ended)return;const card=event.target.closest('.review-card');const r=reviewFor(card.dataset.path);r.played=true;r.playCount=Number(r.playCount||0)+1;r.lastPlayedAt=new Date().toISOString();r.lastDurationSeconds=Number.isFinite(event.target.duration)?Number(event.target.duration.toFixed(3)):null;const state=card.querySelector('[data-playback-state]');state.textContent=`已完整播放 ${r.playCount} 次`;state.classList.add('played');refreshCard(card);saveDraft();},true);
    document.getElementById('reviews').addEventListener('input',event=>{const card=event.target.closest('.review-card');const key=event.target.dataset.key;if(!card||!key)return;reviewFor(card.dataset.path)[key]=event.target.value;refreshCard(card);saveDraft();applyFilter();});
    document.getElementById('reviews').addEventListener('click',event=>{const button=event.target.closest('[data-set-status]');if(!button)return;const card=button.closest('.review-card');const r=reviewFor(card.dataset.path);const allowed=eligibility(r);if(!allowed[button.dataset.setStatus])return;r.status=r.status===button.dataset.setStatus?'':button.dataset.setStatus;setStatusVisual(card,r);saveDraft();applyFilter();});
    document.querySelectorAll('[data-filter]').forEach(button=>button.addEventListener('click',()=>{activeFilter=button.dataset.filter;document.querySelectorAll('[data-filter]').forEach(b=>b.setAttribute('aria-pressed',String(b===button)));applyFilter();}));
    function metadataComplete() { const code=String(draft.meta.reviewerCode||'');const date=String(draft.meta.reviewDate||'');return /^R[0-9A-Z]{2,8}$/.test(code)&&/^\d{4}-\d{2}-\d{2}$/.test(date)&&date<=new Date().toISOString().slice(0,10)&&String(draft.meta.languageContext||'').trim()&&String(draft.meta.childExperience||'').trim()&&draft.meta.nativeSpeakerAttestation===true&&draft.meta.anonymousUseConsent===true; }
    function evidence() {
      const reviews=manifestFiles.map((item,index)=>Object.assign({},reviewFor(item.path),{index:index+1,path:item.path,text:item.text,bytes:item.bytes,sha256:item.sha256,intendedMeaningsZh:item.intendedMeaningsZh,contexts:item.contexts,registerReviewScope:item.registerReviewScope}));
      const judged=reviews.filter(r=>r.status==='pass'||r.status==='revise').length;
      return {schema:evidenceSchema,exportedAt:new Date().toISOString(),manifestSha256,contextCatalogSha256,contextSourceSha256,model:__MODEL_JSON__,generatedAudioCount:119,meta:draft.meta,completion:{metadataComplete:Boolean(metadataComplete()),playedCount:reviews.filter(r=>r.played).length,judgedCount:judged,complete:Boolean(metadataComplete())&&judged===119},reviews};
    }
    function download(name,type,content) { const blob=new Blob([content],{type});const url=URL.createObjectURL(blob);const a=document.createElement('a');a.href=url;a.download=name;a.click();setTimeout(()=>URL.revokeObjectURL(url),1000); }
    document.getElementById('exportJson').addEventListener('click',()=>download('傳家話_越南語母語審閱.json','application/json;charset=utf-8',JSON.stringify(evidence(),null,2)));
    document.getElementById('exportCsv').addEventListener('click',()=>{const rows=[['序號','音檔','越南語文字','中文意圖','語境範圍','已完整播放','文字自然','稱謂合適','音訊清楚','自然度1-5','判定','建議修訂','備註']];evidence().reviews.forEach(r=>rows.push([r.index,r.path,r.text,r.intendedMeaningsZh.join('／'),r.registerReviewScope,r.played,r.textNatural,r.familyRegister,r.audioClear,r.rating,r.status,r.correction,r.notes]));const safe=v=>{let s=String(v??'');if(/^[\s\u0000-\u001F\u007F]*[=+\-@]/.test(s))s="'"+s;return '"'+s.replaceAll('"','""')+'"';};download('傳家話_越南語母語審閱.csv','text/csv;charset=utf-8','\ufeff'+rows.map(row=>row.map(safe).join(',')).join('\r\n'));});
    document.getElementById('resetDraft').addEventListener('click',()=>{if(!confirm('確定清除這台裝置上的全部審閱草稿？請先匯出需要保留的紀錄。'))return;localStorage.removeItem(storageKey);draft=emptyDraft();location.reload();});
    render();
  })();
  </script>
</body>
</html>
"""


def audio_prefix_js(audio_prefix: str) -> str:
    if audio_prefix == "auto":
        return "location.pathname.toLowerCase().includes('/deliverables/review/') ? '../app/assets/' : '../../正式版/flutter_app/'"
    return json_for_script(audio_prefix)


def build_page(
    records: list[dict[str, Any]],
    manifest: dict[str, Any],
    manifest_sha256: str,
    context_catalog: dict[str, Any],
    audio_prefix: str,
) -> str:
    replacements = {
        "__RECORDS_JSON__": json_for_script(records),
        "__MANIFEST_SHA__": manifest_sha256,
        "__CONTEXT_SHA__": str(context_catalog["contextCatalogSha256"]),
        "__CONTEXT_SOURCES_JSON__": json_for_script(context_catalog.get("sourceSha256", {})),
        "__MODEL_JSON__": json_for_script(manifest.get("model", "")),
        "__MODEL_HTML__": html.escape(str(manifest.get("model", ""))),
        "__GENERATOR_HTML__": html.escape(str(manifest.get("generator", ""))),
        "__AUDIO_PREFIX_JS__": audio_prefix_js(audio_prefix),
        "__EVIDENCE_SCHEMA__": EVIDENCE_SCHEMA,
    }
    page = PAGE_TEMPLATE
    for marker, value in replacements.items():
        page = page.replace(marker, value)
    remaining = sorted(set(re.findall(r"__[A-Z0-9_]+__", page)))
    if remaining:
        raise SystemExit(f"Unresolved page template markers: {remaining}")
    return page


def zip_write(zf: zipfile.ZipFile, name: str, data: bytes, compress_type: int) -> None:
    info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
    info.compress_type = compress_type
    info.external_attr = 0o100644 << 16
    zf.writestr(info, data)


def build_portable_zip(
    zip_path: Path,
    page: str,
    manifest_raw: bytes,
    context_raw: bytes,
    records: list[dict[str, Any]],
    flutter_root: Path,
) -> None:
    portable_readme = """傳家話｜越南語 119 句母語審閱可攜包

1. 先把 ZIP 完整解壓縮；不要直接在壓縮檔預覽視窗中開啟。
2. 開啟 index.html。119 個音檔位於 assets/audio，無須網路。
3. 每檔必須完整播放，再填三項是／否、1–5 自然度與判定。
4. 課程卡若顯示說話者／聽者未知，稱謂題只判斷句內明示線索。
5. 匯出 JSON 才是原始紀錄；completion.complete=true 才表示 119 檔形式上填完。

空白工具、ZIP、檔案存在或自動化測試都不等於真人母語審閱成果。
請勿填姓名、電話、地址、電子郵件、學校或社群帳號。
""".encode("utf-8")
    entries: list[tuple[str, bytes, int]] = [
        ("index.html", page.encode("utf-8"), zipfile.ZIP_DEFLATED),
        ("README.txt", portable_readme, zipfile.ZIP_DEFLATED),
        ("assets/audio/piper_generation_manifest.json", manifest_raw, zipfile.ZIP_DEFLATED),
        ("context/native_review_context_catalog.json", context_raw, zipfile.ZIP_DEFLATED),
    ]
    for record in records:
        audio = flutter_root / Path(*record["path"].split("/"))
        entries.append((record["path"], audio.read_bytes(), zipfile.ZIP_STORED))
    sums = "".join(f"{sha256_bytes(data)}  {name}\n" for name, data, _ in entries).encode("utf-8")
    entries.append(("SHA256SUMS.txt", sums, zipfile.ZIP_DEFLATED))

    zip_path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(zip_path, "w", allowZip64=False) as zf:
        for name, data, compression in entries:
            zip_write(zf, name, data, compression)


def main() -> None:
    args = parse_args()
    flutter_root = args.flutter_root.expanduser().resolve()
    manifest_path = args.manifest.expanduser().resolve()
    output_path = args.output.expanduser().resolve()
    context_output = (
        args.context_output.expanduser().resolve()
        if args.context_output
        else output_path.with_name(DEFAULT_CONTEXT_NAME)
    )
    zip_output = (
        args.zip_output.expanduser().resolve()
        if args.zip_output
        else output_path.with_name(DEFAULT_ZIP_NAME)
    )

    manifest, manifest_raw, records = validate_manifest(manifest_path, flutter_root)
    manifest_sha256 = sha256_bytes(manifest_raw)
    existing_catalog = args.context_catalog.expanduser().resolve() if args.context_catalog else None
    flutter_executable = None if existing_catalog else find_flutter(args.flutter)
    context_catalog, enriched_records = build_context_catalog(
        records,
        manifest_sha256,
        flutter_root,
        flutter_executable,
        existing_catalog,
    )
    context_text = json.dumps(context_catalog, ensure_ascii=False, indent=2) + "\n"
    page = build_page(
        enriched_records,
        manifest,
        manifest_sha256,
        context_catalog,
        args.audio_prefix,
    )

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_bytes(page.encode("utf-8"))
    context_output.parent.mkdir(parents=True, exist_ok=True)
    context_output.write_bytes(context_text.encode("utf-8"))
    if not args.no_zip:
        portable_page = build_page(
            enriched_records,
            manifest,
            manifest_sha256,
            context_catalog,
            "./",
        )
        build_portable_zip(
            zip_output,
            portable_page,
            manifest_raw,
            context_text.encode("utf-8"),
            records,
            flutter_root,
        )

    print(output_path)
    print(context_output)
    if not args.no_zip:
        print(zip_output)
    print(
        "records=119 "
        f"usages={context_catalog['usageCount']} "
        f"unknown_relationship_paths={context_catalog['unknownRelationshipPathCount']} "
        f"manifest_sha256={manifest_sha256} "
        f"context_sha256={context_catalog['contextCatalogSha256']}"
    )


if __name__ == "__main__":
    main()
