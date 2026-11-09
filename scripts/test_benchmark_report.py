import copy
import unittest
from benchmark_report import compare, distance, score

class BenchmarkTests(unittest.TestCase):
    def sample(self):
        return {'environment': {'hardware': 'fixture-only'}, 'samples': [
            {'case_id': 'unicode', 'iteration': 1, 'expected': 'café', 'actual': 'cafe', 'latency_ms': 120},
            {'case_id': 'numbers', 'iteration': 1, 'expected': '1234', 'actual': '1234', 'latency_ms': 80}]}
    def test_edit_distance(self):
        self.assertEqual(distance('kitten', 'sitting'), 3)
        self.assertEqual(distance('你好', '你好'), 0)
        self.assertEqual(distance('abc', ''), 3)
    def test_weighted_error_and_percentiles(self):
        result = score(self.sample())
        self.assertEqual(result['character_error_rate'], 1 / 8)
        self.assertEqual(result['latency_p50_ms'], 100)
        self.assertEqual(result['latency_p95_ms'], 120)
    def test_relative_improvement(self):
        baseline = self.sample()
        candidate = copy.deepcopy(baseline)
        candidate['samples'][0]['actual'] = 'café'
        candidate['samples'][0]['latency_ms'] = 60
        self.assertAlmostEqual(compare(baseline, candidate)['p95_latency_reduction_percent'], 100 / 3)
    def test_rejects_unmatched_corpus(self):
        candidate = self.sample()
        candidate['samples'].pop()
        with self.assertRaises(ValueError): compare(self.sample(), candidate)
    def test_rejects_other_environment(self):
        candidate = self.sample()
        candidate['environment']['hardware'] = 'other'
        with self.assertRaises(ValueError): compare(self.sample(), candidate)
    def test_rejects_duplicate_samples(self):
        candidate = self.sample()
        candidate['samples'].append(candidate['samples'][0])
        with self.assertRaises(ValueError): score(candidate)
    def test_rejects_invalid_latency(self):
        for value in [-1, float('nan'), float('inf')]:
            candidate = self.sample()
            candidate['samples'][0]['latency_ms'] = value
            with self.assertRaises(ValueError): score(candidate)
    def test_zero_baseline_does_not_claim_infinite_improvement(self):
        data = self.sample()
        for sample in data['samples']: sample['latency_ms'] = 0
        self.assertIsNone(compare(data, data)['p95_latency_reduction_percent'])

if __name__ == '__main__': unittest.main()
