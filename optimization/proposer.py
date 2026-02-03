SKILL_OPTIMIZATION_PROMPT = """
You are an expert AI Assistant improving a "Skill" definition based on evaluation feedback.
The Skill is a set of instructions or code that defines an agent's capability.

Your goal is to refine the Skill content to improve its performance according to the feedback.
```text
<curr_instructions>
```

Evaluation Feedback (History of attempts and scores):
<inputs_outputs_feedback>

Task:
Analyze the feedback to identify weaknesses in the current Skill.
Generate a NEW, improved version of the Skill Content.
Focus on:
- Addressing specific criticisms in the feedback.
- Improving clarity, robustness, and safety.
- Maintaining the core functionality while enhancing performance.

Return the optimized Skill Content inside a markdown code block:
```instruction
<new skill content>
```
"""
