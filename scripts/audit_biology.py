#!/usr/bin/env python3
"""Offline curriculum integrity check; no network or third-party dependencies.

The independent reference below is the factual topic roadmap, not a copy of
IB's explanatory syllabus text. Presence never certifies complete teaching.
"""
from __future__ import annotations
import argparse
import collections
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
REFERENCE = dict(line.split('|', 1) for line in '''A1.1|Water
A1.2|Nucleic acids
A2.1|Origins of cells
A2.2|Cell structure
A2.3|Viruses
A3.1|Diversity of organisms
A3.2|Classification and cladistics
A4.1|Evolution and speciation
A4.2|Conservation of biodiversity
B1.1|Carbohydrates and lipids
B1.2|Proteins
B2.1|Membranes and membrane transport
B2.2|Organelles and compartmentalization
B2.3|Cell specialization
B3.1|Gas exchange
B3.2|Transport
B3.3|Muscle and motility
B4.1|Adaptation to environment
B4.2|Ecological niches
C1.1|Enzymes and metabolism
C1.2|Cell respiration
C1.3|Photosynthesis
C2.1|Chemical signalling
C2.2|Neural signalling
C3.1|Integration of body systems
C3.2|Defence against disease
C4.1|Populations and communities
C4.2|Transfers of energy and matter
D1.1|DNA replication
D1.2|Protein synthesis
D1.3|Mutations and gene editing
D2.1|Cell and nuclear division
D2.2|Gene expression
D2.3|Water potential
D3.1|Reproduction
D3.2|Inheritance
D3.3|Homeostasis
D4.1|Natural selection
D4.2|Stability and change
D4.3|Climate change'''.splitlines())
HL_ONLY = {'A2.1', 'A2.3', 'A3.2', 'B3.3', 'C2.1', 'D2.2'}
# Boundaries independently checked in the IB-authored guide. Other topics are
# deliberately not assigned a fabricated numbered-understanding denominator.
POINT_BOUNDARIES = {
    'A1.1': (6, 8), 'B2.3': (6, 10), 'B4.2': (13, 13),
    'C2.2': (7, 16), 'C4.2': (22, 22), 'D1.3': (7, 10),
    'D2.3': (7, 11), 'D3.3': (6, 11),
}
COMMANDS = {'identify', 'state', 'outline', 'describe', 'distinguish', 'compare',
            'explain', 'suggest', 'calculate', 'determine', 'discuss', 'evaluate'}


def audit(root: Path = ROOT) -> dict:
    topics = []
    for theme in 'ABCD':
        path = root / 'IBVault' / 'Materials' / 'Biology' / f'{theme}.json'
        rows = json.loads(path.read_text())
        assert all(t['code'].startswith(theme) for t in rows), f'{path}: wrong theme'
        topics.extend(rows)
    assert len(topics) == len(REFERENCE), 'Wrong topic count'
    assert {t['code']: t['title'] for t in topics} == REFERENCE, 'Roadmap mismatch'
    assert len({t['code'] for t in topics}) == len(topics), 'Duplicate topic codes'
    prompts: set[str] = set()
    rows = []
    totals: collections.Counter[str] = collections.Counter()
    referenced: set[str] = set()
    graph = {}
    for topic in topics:
        code = topic['code']
        assert topic['hlOnly'] == (code in HL_ONLY), f'{code}: wrong level'
        assert topic['remaining'].strip(), f'{code}: no coverage limitations'
        sections = topic['sections']
        questions = topic['questions']
        assert sections and questions, f'{code}: no resources'
        assert len({s['key'] for s in sections}) == len(sections), f'{code}: duplicate lesson keys'
        assert len({q['key'] for q in questions}) == len(questions), f'{code}: duplicate question keys'
        section_map = {s['key']: s for s in sections}
        graph[code] = topic['prerequisites']
        assert len(set(graph[code])) == len(graph[code]), f'{code}: duplicate prerequisites'
        assert all(p in REFERENCE and p != code for p in graph[code]), f'{code}: invalid prerequisite'
        mapped = set()
        for section in sections:
            for key in ('key', 'title', 'body', 'pitfall'):
                assert section[key].strip(), f'{code}: empty section {key}'
            ids = section.get('syllabusPoints', [])
            assert len(set(ids)) == len(ids), f'{code}: duplicate references'
            for point in ids:
                assert re.fullmatch(re.escape(code) + r'\.[1-9][0-9]*', point), f'{code}: invalid point {point}'
                mapped.add(point)
                if code in POINT_BOUNDARIES:
                    core, total = POINT_BOUNDARIES[code]
                    number = int(point.rsplit('.', 1)[1])
                    assert 1 <= number <= total, f'{point}: outside reference range'
                    assert (number > core) == bool(section.get('hlOnly', False)), f'{point}: SL/HL mismatch'
            assert any(q['sectionKey'] == section['key'] for q in questions), f'{code}/{section["key"]}: no question'
        for question in questions:
            section = section_map[question['sectionKey']]
            assert topic['hlOnly'] or not section.get('hlOnly') or question.get('hlOnly'), f'{code}: HL question leaks into SL'
            assert question['command'] in COMMANDS, f'{code}: invalid command'
            for key in ('key', 'prompt', 'answer', 'explanation'):
                assert question[key].strip(), f'{code}: empty question {key}'
            normalized = question['prompt'].strip().casefold()
            assert normalized not in prompts, f'{code}: duplicate question'
            prompts.add(normalized)
            assert all(p.strip() for p in question['answer'].split('~')), f'{code}: empty mark point'
            if question['kind'] == 'mcq':
                options = [question['answer'], *question['distractors']]
                assert len(options) == 4 and len({p.strip().casefold() for p in options}) == 4, f'{code}: invalid MCQ'
                assert all(p.strip() for p in options), f'{code}: empty option'
            else:
                assert question['kind'] in ('written', 'data') and not question['distractors'], f'{code}: invalid type'
        counts = collections.Counter(q['kind'] for q in questions)
        sl_sections = [s for s in sections if not topic['hlOnly'] and not s.get('hlOnly')]
        sl_questions = [q for q in questions if not topic['hlOnly'] and not q.get('hlOnly')]
        totals.update(lessons=len(sections), flashcards=len(sections), mcq=counts['mcq'],
                      written=counts['written'], data=counts['data'], questions=len(questions),
                      sl_lessons=len(sl_sections), sl_questions=len(sl_questions))
        referenced.update(mapped)
        rows.append({'code': code, 'title': topic['title'], 'hl_only': topic['hlOnly'],
                     'coverage': 'partial', 'lessons': len(sections), 'flashcards': len(sections),
                     'question_types': dict(counts), 'mapped_understandings': sorted(mapped),
                     'unmapped_understandings_within_checked_range': [
                         f'{code}.{i}' for i in range(1, POINT_BOUNDARIES.get(code, (0, 0))[1] + 1)
                         if f'{code}.{i}' not in mapped
                     ] if code in POINT_BOUNDARIES else None,
                     'remaining': topic['remaining']})
    def visit(code: str, active: set[str], visited: set[str]) -> None:
        assert code not in active, f'Cyclic prerequisites: {code}'
        if code in visited:
            return
        for prerequisite in graph[code]:
            visit(prerequisite, active | {code}, visited)
        visited.add(code)
    visited: set[str] = set()
    for code in graph:
        visit(code, set(), visited)
    baseline = None
    try:
        text = subprocess.check_output(['git', 'show', 'c65af39d06b5e8bb69d5757d9097e2158933f547:IBVault/Services/SyllabusSeeder.swift'],
                                       cwd=root, text=True, stderr=subprocess.DEVNULL)
        segment = text.split('private static var biologyCurriculum:', 1)[1].split('private static var mathAACurriculum:', 1)[0]
        baseline = {'grouped_topic_headings': segment.count('CurriculumTopic(name:'),
                    'bundled_biology_lessons': 0, 'bundled_biology_questions': 0,
                    'note': 'Repository content only. Existing users may have generated or custom cards.'}
    except (subprocess.CalledProcessError, IndexError):
        pass
    return {'reference_checked': '2026-09-24', 'first_assessment': 2025,
            'sources': ['https://www.ibo.org/programmes/diploma-programme/curriculum/sciences/biology/',
                        'https://anatolia.edu.gr/images/highschool/IBDP/Biology%20Guide%202025.pdf'],
            'baseline': baseline, 'canonical_topics': len(topics), 'sl_topics': 34, 'hl_topics_including_core': 40,
            'fully_verified_complete_topics': 0, 'partial_topics': len(topics),
            'missing_topic_packages': 0, 'resource_totals': dict(totals),
            'distinct_explicit_understanding_references': len(referenced),
            'total_official_understandings': None, 'full_syllabus_coverage_percentage': None,
            'coverage_note': 'Referenced means relevant teaching exists, not that every requirement is complete. No full-syllabus denominator or completeness percentage has been invented.',
            'topics': rows}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    report = audit()
    serialized = json.dumps(report, ensure_ascii=False, indent=2) + '\n'
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(serialized)
    print(json.dumps({k: v for k, v in report.items() if k != 'topics'}, indent=2))


if __name__ == '__main__':
    main()
