import json
import subprocess
from pathlib import Path

import pytest
from ragas.metrics.collections import ExactMatch


ROOT = Path(__file__).resolve().parents[1]
CASES = json.loads((ROOT / "evals/steel_policy_cases.json").read_text())


@pytest.fixture(scope="module")
def decisions():
    result = subprocess.run(
        ["dart", "run", "tool/steel_policy_eval.dart"],
        cwd=ROOT,
        input=json.dumps(CASES),
        text=True,
        capture_output=True,
        check=True,
    )
    return json.loads(result.stdout)


@pytest.mark.parametrize("index,case", enumerate(CASES), ids=[c["name"] for c in CASES])
def test_steel_policy_matches_ragas_golden_decision(decisions, index, case):
    score = ExactMatch().score(
        response=decisions[index],
        reference=case["expected"],
    )
    assert score.value == 1.0, (
        f"{case['name']}: expected {case['expected']}, got {decisions[index]}"
    )
