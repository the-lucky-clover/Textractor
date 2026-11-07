#!/usr/bin/env python3
"""Score matched OCR captures. Never substitute estimated results for missing measurements."""
import argparse
import json
import math
import statistics
from pathlib import Path


def distance(expected, actual):
    row = list(range(len(actual) + 1))
    for i, left in enumerate(expected, 1):
        next_row = [i]
        for j, right in enumerate(actual, 1):
            next_row.append(min(next_row[-1] + 1, row[j] + 1, row[j - 1] + (left != right)))
        row = next_row
    return row[-1]


def score(data):
    samples = data['samples']
    if not samples:
        raise ValueError('No measured samples')
    errors = characters = exact = 0
    times = []
    ids = set()
    for sample in samples:
        key = (sample['case_id'], sample['iteration'])
        if key in ids:
            raise ValueError(f'Duplicate sample: {key}')
        ids.add(key)
        expected, actual = sample['expected'], sample['actual']
        if not expected:
            raise ValueError('Expected text cannot be empty')
        duration = float(sample['latency_ms'])
        if not math.isfinite(duration) or duration < 0:
            raise ValueError('Latency must be finite and nonnegative')
        times.append(duration)
        errors += distance(expected, actual)
        characters += len(expected)
        exact += expected == actual
    ordered = sorted(times)
    return {'sample_count': len(samples), 'character_error_rate': errors / characters,
            'exact_match_rate': exact / len(samples), 'latency_p50_ms': statistics.median(times),
            'latency_p95_ms': ordered[math.ceil(0.95 * len(times)) - 1]}


def compare(baseline, candidate):
    if baseline.get('environment') != candidate.get('environment'):
        raise ValueError('Use identical hardware, OS, display scale and capture corpus')
    left = {(x['case_id'], x['iteration']): x['expected'] for x in baseline['samples']}
    right = {(x['case_id'], x['iteration']): x['expected'] for x in candidate['samples']}
    if left != right:
        raise ValueError('Samples or expected text do not match')
    before, after = score(baseline), score(candidate)
    return {'baseline': before, 'candidate': after,
            'character_error_rate_change_pp': 100 * (after['character_error_rate'] - before['character_error_rate']),
            'p95_latency_reduction_percent': None if before['latency_p95_ms'] == 0 else 100 * (1 - after['latency_p95_ms'] / before['latency_p95_ms'])}


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('candidate', type=Path)
    parser.add_argument('--baseline', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    candidate = json.loads(args.candidate.read_text())
    result = compare(json.loads(args.baseline.read_text()), candidate) if args.baseline else score(candidate)
    content = json.dumps(result, indent=2)
    if args.output:
        args.output.write_text(content + '\n')
    print(content)
