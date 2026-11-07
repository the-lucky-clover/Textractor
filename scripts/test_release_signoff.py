import unittest
from check_release_signoff import REQUIRED, validate

class ReleaseGateTests(unittest.TestCase):
    def test_pending_is_not_signoff(self):
        with self.assertRaises(ValueError): validate({'status': 'blocked'})
    def test_each_check_is_mandatory(self):
        for omitted in REQUIRED:
            record = {'status':'approved', 'tested_commit':'fixture', 'evidence':['fixture'],
                      'checks':dict.fromkeys(REQUIRED, 'passed')}
            record['checks'][omitted] = 'pending'
            with self.assertRaises(ValueError): validate(record)
    def test_evidence_required(self):
        with self.assertRaises(ValueError):
            validate({'status':'approved','checks':dict.fromkeys(REQUIRED,'passed')})
    def test_complete_record(self):
        validate({'status':'approved','checks':dict.fromkeys(REQUIRED,'passed'),
                  'tested_commit':'fixture','evidence':['fixture']})

if __name__ == '__main__': unittest.main()
