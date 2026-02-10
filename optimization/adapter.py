from typing import List, Optional, TypedDict, Dict
import os
import sys

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

import dotenv
import gepa
from gepa import GEPAAdapter, EvaluationBatch
from gepa.strategies.instruction_proposal import InstructionProposalSignature


from evaluation.evaluate_skill import (
    build_evaluation_report,
    compute_evaluation_scores,
    evaluate_skill_meta,
)

from optimization.constants import ENV_FILE
from optimization.proposer import SKILL_OPTIMIZATION_PROMPT


dotenv.load_dotenv(override=True, dotenv_path=ENV_FILE)

InstructionProposalSignature.default_prompt_template = SKILL_OPTIMIZATION_PROMPT


class DataInst(TypedDict):
    skill_md: str
    references: Dict[str, str]
    scripts: Dict[str, str]
    skill_name: str


class Trajectory(TypedDict):
    skill_content: str
    score: float
    feedback: str
    # Add input/output for dataset construction
    input: str
    output: str


class RolloutOutput(TypedDict):
    text: Optional[str]


class EvalItem(TypedDict):
    trajectory: Trajectory
    rollout_output: RolloutOutput


class GEPAEvaluationAdapter(GEPAAdapter[DataInst, Trajectory, RolloutOutput]):
    def __init__(self):
        super().__init__()
        self.history = []  # Store evaluation history

    def evaluate(
        self,
        batch: List[DataInst],
        candidate: Dict[str, str],
        capture_traces: bool = False,
    ) -> EvaluationBatch:
        eval_items = []

        # Candidate contains the optimized skill content.
        skill_content = candidate.get("skill_md") or candidate.get("instruction") or ""

        for example in batch:
            skill_name = example.get("skill_name", "")
            try:
                meta_results, meta_comment = evaluate_skill_meta(skill_content)
                average_score, sorted_results = compute_evaluation_scores(meta_results)
                report_content = build_evaluation_report(
                    skill_name=skill_name,
                    average_score=average_score,
                    meta_comment=meta_comment,
                    code_comment=None,
                    sorted_results=sorted_results,
                )

                # Normalize score to 0-1 if it's 5-point scale
                normalized_score = average_score / 5.0
                feedback = report_content

                # Record detailed history for this evaluation
                self.history.append(
                    {
                        "round": len(self.history) + 1,
                        "skill_content": skill_content,
                        "average_score": average_score,
                        "normalized_score": normalized_score,
                        "feedback": feedback,
                        "details": sorted_results,  # Store dimension scores
                        "meta_comment": meta_comment,
                    }
                )

            except Exception as e:
                print(f"Evaluation failed: {e}")
                normalized_score = 0.0
                feedback = f"Evaluation failed: {str(e)}"
                average_score = 0.0
                sorted_results = []

                self.history.append(
                    {
                        "round": len(self.history) + 1,
                        "skill_content": skill_content,
                        "average_score": 0.0,
                        "normalized_score": 0.0,
                        "feedback": feedback,
                        "details": [],
                        "meta_comment": str(e),
                    }
                )

            # Construct Trajectory
            trajectory = Trajectory(
                skill_content=skill_content,
                score=normalized_score,
                feedback=feedback,
                input=f"Optimize skill: {example.get('skill_name')}",
                output=skill_content,
            )

            rollout_output = RolloutOutput(text=skill_content)

            eval_items.append(
                EvalItem(trajectory=trajectory, rollout_output=rollout_output)
            )

        outputs = []
        scores = []
        trajectories = []
        for item in eval_items:
            outputs.append(item.get("rollout_output", "").get("text", ""))
            scores.append(item.get("trajectory", {}).get("score", 0.0))
            trajectories.append(item.get("trajectory", {}))

        return EvaluationBatch(
            outputs=outputs,
            scores=scores,
            trajectories=trajectories,
        )

    def make_reflective_dataset(
        self,
        candidate: dict[str, str],
        eval_batch: EvaluationBatch,
        components_to_update: list[str],
    ):
        # This is required by GEPAAdapter protocol.
        # It converts evaluation results into feedback for the proposer.
        dataset = {}

        for comp in components_to_update:
            trajs = []

            for traj in eval_batch.trajectories or []:
                trajs.append(
                    {
                        "score": traj.get("score", 0.0),
                        "feedback": traj.get("feedback", ""),
                        "program_input": traj.get("input", ""),
                        "program_output": traj.get("output", ""),
                        "details": (
                            self.history[-1].get("details", []) if self.history else []
                        ),
                    }
                )

            dataset[comp] = trajs

        return dataset


def load_dataset(skill_name, num_examples=1) -> List[DataInst]:
    """
    加载一个占位用的数据集。

    在当前场景中，被优化的对象 (Candidate) 包含了完整的 Skill 内容 (如 SKILL.md)。
    因此，Dataset 不需要提供真实的输入数据，只需要提供一个空的 DataInst
    来驱动 GEPA 的评估循环。

    metric 会直接对 Candidate 中的 Skill 内容进行评分和反馈。
    """
    return [
        DataInst(
            skill_name=skill_name,
            skill_md="",
            references={},
            scripts={},
        )
        for _ in range(num_examples)
    ]


def run_gepa(
    trainset, valset, seed_candidate, max_metric_calls, perfect_score=5.0, verbose=False
):
    adapter = GEPAEvaluationAdapter()
    opt_model = os.environ.get("OPT_MODEL", "deepseek-chat")

    if "deepseek" in opt_model and not opt_model.startswith(("openai/", "deepseek/")):
        opt_model = f"deepseek/{opt_model}"

    # Suppress output if verbose is False
    if not verbose:
        import logging

        # Try to suppress gepa logging if it uses standard logging
        logging.getLogger("gepa").setLevel(logging.WARNING)

    result = gepa.optimize(
        adapter=adapter,
        trainset=trainset,
        valset=valset,
        seed_candidate=seed_candidate,
        max_metric_calls=max_metric_calls,
        reflection_lm=opt_model,
        perfect_score=perfect_score,
    )

    return result, adapter.history
