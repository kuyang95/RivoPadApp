#!/usr/bin/env python3
"""Compare structure/text exactly and report every floating-point difference."""
import copy
import json
import math
import sys
from pathlib import Path

host = json.loads(Path(sys.argv[1]).read_text())
android = json.loads(Path(sys.argv[2]).read_text())
host_structure, android_structure = copy.deepcopy(host), copy.deepcopy(android)
host_formula = next(x for x in host_structure['checks'] if x['check'] == 'xlsx-formula-fixture')
android_formula = next(x for x in android_structure['checks'] if x['check'] == 'xlsx-formula-fixture')
a, b = host_formula.pop('values'), android_formula.pop('values')
host_display, android_display = host_formula.pop('displayValues'), android_formula.pop('displayValues')
# File preservation and calculated value types must match exactly. Display differences
# are findings reported explicitly, not swallowed by the numeric tolerance.
assert host_structure == android_structure, 'Structure, types, or file preservation differ'
assert host_display.keys() == android_display.keys(), 'Displayed cell sets differ'
display_differences = [{'cell': k, 'host': host_display[k], 'android': android_display[k]}
                       for k in sorted(host_display) if host_display[k] != android_display[k]]
assert a.keys() == b.keys(), 'Calculated formula cell sets differ'
exact = 0
numeric_differences = []
for key in sorted(a):
    if a[key] == b[key]:
        exact += 1
        continue
    assert host_formula['types'][key] == 'n', f'Text/error/boolean changed: {key}'
    x, y = float(a[key]), float(b[key])
    assert math.isfinite(x) and math.isfinite(y), f'Nonfinite value changed: {key}'
    assert math.isclose(x, y, rel_tol=1e-12, abs_tol=1e-12), f'Numeric result changed: {key}: {x} vs {y}'
    numeric_differences.append({'cell': key, 'host': a[key], 'android': b[key],
                                'absoluteDifference': abs(x-y)})
report = {'passedChecks': host['passed'], 'exactFormulaValues': exact,
          'comparedFormulaValues': len(a), 'numericDifferences': numeric_differences,
          'relativeTolerance': 1e-12, 'absoluteTolerance': 1e-12,
          'displayDifferences': display_differences,
          'strictParity': not numeric_differences and not display_differences,
          'filePreservationAndValueTypesExactlyEqual': True}
print(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True))
