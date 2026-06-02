const MAX_LABEL_LENGTH = 30;

interface QuestionOption {
  label: string;
  description?: string;
}

interface Question {
  question: string;
  header?: string;
  options?: QuestionOption[];
  multiSelect?: boolean;
}

interface AskUserQuestionArgs {
  questions: Question[];
}

function truncateLabel(label: string, maxLength: number = MAX_LABEL_LENGTH): string {
  if (label.length <= maxLength) {
    return label;
  }
  return label.substring(0, maxLength - 3) + "...";
}

function truncateQuestionLabels(args: AskUserQuestionArgs): AskUserQuestionArgs {
  if (!args.questions || !Array.isArray(args.questions)) {
    return args;
  }

  return {
    ...args,
    questions: args.questions.map((question) => ({
      ...question,
      options:
        question.options?.map((option) => ({
          ...option,
          label: truncateLabel(option.label),
        })) ?? [],
    })),
  };
}

function isQuestionTool(toolName: string | undefined): boolean {
  const normalizedToolName = toolName?.toLowerCase();
  return (
    normalizedToolName === "question"
    || normalizedToolName === "askuserquestion"
    || normalizedToolName === "ask_user_question"
  );
}

export function createQuestionLabelTruncatorHook() {
  return {
    "tool.execute.before": async (
      input: { tool: string },
      output: { args: Record<string, unknown> }
    ): Promise<void> => {
      if (isQuestionTool(input.tool)) {
        const args = output.args as unknown as AskUserQuestionArgs | undefined;

        if (args?.questions) {
          const truncatedArgs = truncateQuestionLabels(args);
          Object.assign(output.args, truncatedArgs);
        }
      }
    },
  };
}
